#!/usr/bin/env bash
set -Eeuo pipefail

REPO="zhboner/realm"
INSTALL_DIR="/opt/realm"
CONFIG_DIR="/etc/realm"
CONFIG_FILE="${CONFIG_DIR}/config.toml"
SERVICE_FILE="/etc/systemd/system/realm.service"
SYSCTL_FILE="/etc/sysctl.d/99-realm-bbr.conf"

log() { printf '\033[1;32m[realm] %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m[realm] 错误: %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法：
  sudo bash install.sh 本地端口:目标地址:目标端口 [更多规则...]

示例：
  sudo bash install.sh 443:1.2.3.4:443 8443:example.com:443

环境变量：
  ENABLE_UDP=1        同时转发 UDP（默认仅 TCP）
  ENABLE_BBR=0        不配置 BBR（默认配置）
  REALM_VERSION=v2.x  安装指定版本（默认 latest）
EOF
}

[[ ${EUID} -eq 0 ]] || die "请用 root 用户或 sudo 运行"
[[ $# -gt 0 ]] || { usage; exit 2; }
command -v systemctl >/dev/null || die "仅支持使用 systemd 的 Linux 系统"

case "$(uname -m)" in
  x86_64|amd64) target="x86_64-unknown-linux-gnu" ;;
  aarch64|arm64) target="aarch64-unknown-linux-gnu" ;;
  *) die "暂不支持架构：$(uname -m)（当前支持 x86_64、ARM64）" ;;
esac

if command -v curl >/dev/null; then
  fetch() { curl -fL --retry 3 --connect-timeout 15 "$@"; }
elif command -v wget >/dev/null; then
  fetch() { wget -qO- "$1"; }
else
  die "需要 curl 或 wget"
fi

for rule in "$@"; do
  [[ $rule =~ ^([0-9]{1,5}):([A-Za-z0-9._-]+):([0-9]{1,5})$ ]] || die "规则格式错误：${rule}"
  (( 10#${BASH_REMATCH[1]} >= 1 && 10#${BASH_REMATCH[1]} <= 65535 )) || die "本地端口超出范围：${rule}"
  (( 10#${BASH_REMATCH[3]} >= 1 && 10#${BASH_REMATCH[3]} <= 65535 )) || die "目标端口超出范围：${rule}"
done

if [[ ${REALM_VERSION:-latest} == latest ]]; then
  version="$(fetch "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p')"
  [[ -n $version ]] || die "无法获取 Realm 最新版本"
else
  version="${REALM_VERSION}"
fi

archive="realm-${target}.tar.gz"
url="https://github.com/${REPO}/releases/download/${version}/${archive}"
tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$tmpdir"' EXIT

log "下载 Realm ${version}（${target}）"
fetch "$url" > "${tmpdir}/${archive}"
tar -xzf "${tmpdir}/${archive}" -C "$tmpdir"
[[ -x ${tmpdir}/realm || -f ${tmpdir}/realm ]] || die "下载包中没有 realm 程序"

install -d -m 0755 "$INSTALL_DIR" "$CONFIG_DIR"
install -m 0755 "${tmpdir}/realm" "${INSTALL_DIR}/realm"

if [[ -f $CONFIG_FILE ]]; then
  cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
fi
{
  printf '[log]\nlevel = "warn"\noutput = "stdout"\n\n[network]\nuse_udp = %s\n\n' "$( [[ ${ENABLE_UDP:-0} == 1 ]] && echo true || echo false )"
  for rule in "$@"; do
    local_port="${rule%%:*}"
    remainder="${rule#*:}"
    remote_host="${remainder%:*}"
    remote_port="${remainder##*:}"
    printf '[[endpoints]]\nlisten = "0.0.0.0:%s"\nremote = "%s:%s"\n\n' "$local_port" "$remote_host" "$remote_port"
  done
} > "$CONFIG_FILE"
chmod 0600 "$CONFIG_FILE"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Realm network relay
Documentation=https://github.com/zhboner/realm
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_DIR}/realm -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

if [[ ${ENABLE_BBR:-1} == 1 ]]; then
  cat > "$SYSCTL_FILE" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  sysctl -p "$SYSCTL_FILE" >/dev/null || die "应用 BBR 参数失败；请检查内核是否支持 BBR"
fi

systemctl daemon-reload
systemctl enable realm.service >/dev/null
systemctl restart realm.service
if ! systemctl is-active --quiet realm.service; then
  journalctl -u realm.service -n 30 --no-pager >&2 || true
  die "Realm 服务启动失败"
fi

log "安装完成：$(${INSTALL_DIR}/realm --version 2>/dev/null || echo "$version")"
log "配置文件：${CONFIG_FILE}"
log "查看状态：systemctl status realm --no-pager"
log "修改配置后：systemctl restart realm"
if [[ ${ENABLE_BBR:-1} == 1 ]]; then
  log "当前拥塞控制：$(sysctl -n net.ipv4.tcp_congestion_control)"
fi
