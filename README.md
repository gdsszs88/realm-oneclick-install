# Realm 一键安装

适用于带 systemd 的 Linux VPS。自动安装 [Realm](https://github.com/zhboner/realm)、配置转发规则、启用 systemd 守护，并默认启用 BBR。

## 一键安装

直接安装并生成 `/root/realm/config.toml` 默认模板：

```bash
curl -fsSL https://raw.githubusercontent.com/gdsszs88/realm-oneclick-install/main/install.sh | sudo bash
```

默认模板使用 `54321` 端口及 `0.0.0.0` 占位目标。安装后必须把目标改成 3x-ui 面板服务器的真实 IP，否则不能形成有效中转：

```bash
nano /root/realm/config.toml
systemctl restart realm
```

也可以在安装命令中直接指定一条或多条规则，每个参数格式为 `本机监听端口:目标地址:目标端口`：

```bash
curl -fsSL https://raw.githubusercontent.com/gdsszs88/realm-oneclick-install/main/install.sh | sudo bash -s -- 443:1.2.3.4:443 8443:example.com:443
```

## 管理命令

```bash
systemctl status realm --no-pager
journalctl -u realm -f
systemctl restart realm
```

Realm 程序和配置分别位于 `/root/realm/realm`、`/root/realm/config.toml`。再次运行安装命令会更新程序和规则，并自动备份旧配置。

手动编辑配置：

```bash
nano /root/realm/config.toml
systemctl restart realm
```

## 说明

- 支持 x86_64 和 ARM64 Linux。
- 默认下载 Realm 官方最新稳定版；可设置 `REALM_VERSION=v2.x.x` 固定版本。
- BBR 写入独立的 `/etc/sysctl.d/99-realm-bbr.conf`，重复运行不会污染 `/etc/sysctl.conf`。
- 脚本不会自动修改云厂商安全组或主机防火墙，需自行放行监听端口。
- 只从本仓库与 Realm 官方 GitHub Release 下载代码。正式环境建议先审阅脚本再执行远程命令。
