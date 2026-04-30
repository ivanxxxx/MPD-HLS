from pathlib import Path

readme = r"""# MPD2HLS 一键安装脚本

MPD2HLS 一键安装脚本用于快速部署 `mpd2hls` 服务，安装完成后会自动创建系统服务，并提供 `mpd2hls` 管理命令，方便后续安装、启动、停止、重启、查看日志、更新和卸载。

---

## 功能说明

- 一键安装 `mpd2hls`
- 自动创建安装目录
- 自动下载程序文件
- 自动配置 `systemd` 服务
- 自动启动服务
- 提供命令行管理面板
- 支持查看日志、重启、停止、启动、更新
- 支持完整卸载，删除服务文件、程序目录和管理命令

---

## 默认信息

| 项目 | 默认值 |
|---|---|
| 默认面板端口 | `9527` |
| 默认账号 | `admin` |
| 默认密码 | `admin123` |
| 安装目录 | `/opt/mpd2hls` |
| 服务文件 | `/etc/systemd/system/mpd2hls.service` |
| 管理命令 | `/usr/local/bin/mpd2hls` |
| 管理面板路径 | `/admin` |

---

## 安装方式

执行安装脚本后，会提示输入面板端口：

```bash
bash install.sh
