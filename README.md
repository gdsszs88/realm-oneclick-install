# Realm 一键安装

适用于带 systemd 的 Linux VPS。自动安装 [Realm](https://github.com/zhboner/realm)、配置转发规则、启用 systemd 守护，并默认启用 BBR。

## 一键安装

把下面的端口和目标地址改成你自己的：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gdsszs88/realm-oneclick-install/main/install.sh) 443:1.2.3.4:443 8443:example.com:443
```

每个参数格式为 `本机监听端口:目标地址:目标端口`，可一次传入多条规则。脚本必须以 root 身份运行；普通用户请在命令前加 `sudo`（见下方兼容写法）。

如果系统或当前 shell 不支持进程替换，可用：

```bash
curl -fsSL https://raw.githubusercontent.com/gdsszs88/realm-oneclick-install/main/install.sh | sudo bash -s -- 443:1.2.3.4:443
```

同时转发 TCP 和 UDP：

```bash
curl -fsSL https://raw.githubusercontent.com/gdsszs88/realm-oneclick-install/main/install.sh | sudo ENABLE_UDP=1 bash -s -- 443:1.2.3.4:443
```

## 管理命令

```bash
systemctl status realm --no-pager
journalctl -u realm -f
systemctl restart realm
```

配置位于 `/etc/realm/config.toml`。再次运行安装命令会更新程序和规则，并自动备份旧配置。

## 说明

- 支持 x86_64 和 ARM64 Linux。
- 默认下载 Realm 官方最新稳定版；可设置 `REALM_VERSION=v2.x.x` 固定版本。
- BBR 写入独立的 `/etc/sysctl.d/99-realm-bbr.conf`，重复运行不会污染 `/etc/sysctl.conf`。
- 脚本不会自动修改云厂商安全组或主机防火墙，需自行放行监听端口。
- 只从本仓库与 Realm 官方 GitHub Release 下载代码。正式环境建议先审阅脚本再执行远程命令。
