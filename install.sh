#!/bin/bash
# mpd2hls 一键安装/管理脚本

BINARY_NAME="mpd2hls"
INSTALL_DIR="/opt/mpd2hls"
SERVICE_NAME="mpd2hls"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_PATH="/usr/local/bin/mpd2hls"
DATA_DIR="$INSTALL_DIR"
INSTALL_SCRIPT_URL="https://github.com/judy-gotv/MPD-HLS/raw/main/install.sh"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  DOWNLOAD_URL="https://github.com/judy-gotv/MPD-HLS/raw/main/mpd2hls" ;;
    aarch64) DOWNLOAD_URL="https://github.com/judy-gotv/MPD-HLS/raw/main/mpd2hls-aarch64" ;;
    armv7l)  DOWNLOAD_URL="https://github.com/judy-gotv/MPD-HLS/raw/main/mpd2hls-armv7" ;;
    *)       DOWNLOAD_URL="" ;;
esac

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "  ${GREEN}✔${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
error()   { echo -e "\n  ${RED}✘  错误：$1${NC}\n"; exit 1; }
step()    { echo -e "  ${CYAN}›${NC}  $1"; }
success() { echo -e "  ${GREEN}✔  $1${NC}"; }

[ "$(id -u)" -eq 0 ] || error "请使用 root 权限运行"

# ─── 工具函数 ─────────────────────────────────────────────────────────────────

get_server_ip() {
    curl -s4 --connect-timeout 4 ifconfig.me 2>/dev/null \
        || curl -s4 --connect-timeout 4 ip.sb 2>/dev/null \
        || curl -s6 --connect-timeout 4 ifconfig.me 2>/dev/null \
        || hostname -I | awk '{print $1}'
}

print_access_urls() {
    local port=$1
    ip -4 addr show 2>/dev/null \
        | grep -oP '(?<=inet\s)\d+(\.\d+){3}' \
        | grep -v '^127\.' \
        | while read -r ip; do
            echo -e "    ${GREEN}▶  http://${ip}:${port}/admin${NC}"
        done
    ip -6 addr show 2>/dev/null \
        | grep -oP '(?<=inet6\s)[0-9a-f:]+' \
        | grep -v '^::1$' \
        | grep -v '^fe80' \
        | while read -r ip; do
            echo -e "    ${GREEN}▶  http://[${ip}]:${port}/admin${NC}"
        done
}

get_running_port() {
    systemctl show "$SERVICE_NAME" -p Environment 2>/dev/null \
        | grep -oE 'PANEL_ADDR=[^ ]+|PANEL_LISTEN=[^ ]+' \
        | sed 's/.*:\([0-9]*\)$/\1/'
}

hr() { echo -e "${DIM}  ──────────────────────────────────────────────────${NC}"; }

# ─── 管理面板 ─────────────────────────────────────────────────────────────────

show_menu() {
    clear
    echo ""
    echo -e "  ${CYAN}${BOLD}███╗   ███╗██████╗ ██████╗ ██████╗ ██╗  ██╗██╗     ███████╗${NC}"
    echo -e "  ${CYAN}${BOLD}████╗ ████║██╔══██╗██╔══██╗╚════██╗██║  ██║██║     ██╔════╝${NC}"
    echo -e "  ${CYAN}${BOLD}██╔████╔██║██████╔╝██║  ██║ █████╔╝███████║██║     ███████╗${NC}"
    echo -e "  ${CYAN}${BOLD}██║╚██╔╝██║██╔═══╝ ██║  ██║██╔═══╝ ██╔══██║██║     ╚════██║${NC}"
    echo -e "  ${CYAN}${BOLD}██║ ╚═╝ ██║██║     ██████╔╝███████╗██║  ██║███████╗███████║${NC}"
    echo -e "  ${CYAN}${BOLD}╚═╝     ╚═╝╚═╝     ╚═════╝ ╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝${NC}"
    echo ""
    echo -e "  ${DIM}作者：${WHITE}Go-iptv${NC}  ${DIM}TG 交流群：${YELLOW}https://t.me/GPT_858${NC}"
    hr

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        PORT=$(get_running_port)
        [ -z "$PORT" ] && PORT="?"
        SERVER_IP=$(get_server_ip)
        echo -e "  ${BOLD}状 态${NC}  ${GREEN}● 运行中${NC}"
        echo -e "  ${BOLD}访 问${NC}  ${GREEN}http://${SERVER_IP}:${PORT}/admin${NC}"
    else
        echo -e "  ${BOLD}状 态${NC}  ${RED}● 未运行${NC}"
    fi

    hr
    echo ""
    echo -e "  ${BOLD}${WHITE} 1 ${NC}  安装程序"
    echo -e "  ${BOLD}${WHITE} 2 ${NC}  重启服务"
    echo -e "  ${BOLD}${WHITE} 3 ${NC}  停止服务"
    echo -e "  ${BOLD}${WHITE} 4 ${NC}  启动服务"
    echo -e "  ${BOLD}${WHITE} 5 ${NC}  查看日志"
    echo -e "  ${BOLD}${WHITE} 6 ${NC}  更新程序"
    echo -e "  ${BOLD}${WHITE} 7 ${NC}  ${RED}卸载程序${NC}"
    echo -e "  ${BOLD}${WHITE} 0 ${NC}  退出"
    echo ""
    hr
    echo ""
    read -rp "  请输入选项: " CHOICE
    echo ""

    case "$CHOICE" in
        1) do_install ;;
        2) do_restart ;;
        3) do_stop ;;
        4) do_start ;;
        5) do_logs ;;
        6) do_update ;;
        7) do_uninstall ;;
        0) echo -e "  ${DIM}再见！${NC}\n"; exit 0 ;;
        *) warn "无效选项，请重新输入"; sleep 1; show_menu ;;
    esac
}

# ─── 安装 ─────────────────────────────────────────────────────────────────────

do_install() {
    clear
    echo ""
    echo -e "  ${CYAN}${BOLD}┌─────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}${BOLD}│             MPD2HLS  一键安装               │${NC}"
    echo -e "  ${CYAN}${BOLD}└─────────────────────────────────────────────┘${NC}"
    echo ""

    # 检查 systemd
    if ! command -v systemctl &>/dev/null; then
        error "当前系统不支持 systemd，无法安装\n  支持：Ubuntu 16.04+ / Debian 8+ / CentOS 7+\n  不支持：OpenVZ 容器"
    fi

    # 检查架构
    if [ -z "$DOWNLOAD_URL" ]; then
        error "不支持的系统架构: $ARCH\n  支持：x86_64 / aarch64 / armv7l"
    fi

    # 检查下载工具
    if command -v curl &>/dev/null; then
        DOWNLOADER="curl"
    elif command -v wget &>/dev/null; then
        DOWNLOADER="wget"
    else
        error "未找到 curl 或 wget，请先安装其中一个"
    fi

    echo -e "  ${DIM}系统架构：${ARCH}${NC}"
    echo ""

    # 输入端口
    while true; do
        echo -e "  ${BOLD}请输入面板端口${NC} ${DIM}（默认 9527，直接回车使用默认值）${NC}"
        read -rp "  端口 > " PORT_INPUT
        PORT="${PORT_INPUT:-9527}"

        if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
            warn "端口无效，请输入 1-65535 之间的数字"
            continue
        fi

        if ss -tlnp 2>/dev/null | grep -q ":${PORT}[^0-9]" || \
           netstat -tlnp 2>/dev/null | grep -q ":${PORT}[^0-9]"; then
            warn "端口 $PORT 已被占用，请更换一个"
            continue
        fi

        break
    done

    echo ""
    hr
    echo -e "  ${BOLD}端口：${NC} ${GREEN}${PORT}${NC}"
    hr
    echo ""
    read -rp "  确认配置，按回车开始安装... " _CONFIRM
    echo ""

    # 停止旧服务
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        step "停止旧服务..."
        systemctl stop "$SERVICE_NAME"
    fi

    step "创建安装目录..."
    mkdir -p "$INSTALL_DIR"

    step "正在下载程序..."
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -L --progress-bar -o "$INSTALL_DIR/$BINARY_NAME" "$DOWNLOAD_URL" || error "下载失败，请检查网络连接"
    else
        wget --show-progress -O "$INSTALL_DIR/$BINARY_NAME" "$DOWNLOAD_URL" || error "下载失败，请检查网络连接"
    fi
    chmod +x "$INSTALL_DIR/$BINARY_NAME"

    step "安装管理命令..."
    install_command

    step "配置系统服务..."
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=MPD2HLS Panel Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStartPre=-/usr/bin/pkill -x $BINARY_NAME
ExecStartPre=/bin/sleep 1
ExecStart=$INSTALL_DIR/$BINARY_NAME
Restart=always
RestartSec=5
Environment=PANEL_ADDR=[::]:${PORT}
Environment=PANEL_ADMIN_PATH=/admin

[Install]
WantedBy=multi-user.target
EOF

    step "启动服务..."
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" --quiet
    systemctl start "$SERVICE_NAME"
    sleep 2

    echo ""
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  ${GREEN}${BOLD}┌─────────────────────────────────────────────┐${NC}"
        echo -e "  ${GREEN}${BOLD}│              ✓  安装成功！                  │${NC}"
        echo -e "  ${GREEN}${BOLD}└─────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${DIM}安装目录${NC}  $INSTALL_DIR"
        echo -e "  ${DIM}服务名称${NC}  $SERVICE_NAME"
        echo -e "  ${DIM}服务文件${NC}  $SERVICE_FILE"
        echo ""
        hr
        echo -e "  ${BOLD}后台访问地址${NC}"
        echo ""
        print_access_urls "$PORT"
        echo ""
        hr
        echo -e "  ${BOLD}默认账号${NC}  admin"
        echo -e "  ${BOLD}默认密码${NC}  ${YELLOW}admin123${NC}  ${DIM}← 登录后请立即修改${NC}"
        echo ""
        hr
        echo -e "  ${BOLD}常用命令${NC}"
        echo ""
        echo -e "  ${DIM}mpd2hls                            # 打开管理面板${NC}"
        echo -e "  ${DIM}systemctl status  $SERVICE_NAME    # 查看服务状态${NC}"
        echo -e "  ${DIM}systemctl restart $SERVICE_NAME    # 重启服务${NC}"
        echo -e "  ${DIM}journalctl -u $SERVICE_NAME -f     # 实时日志${NC}"
        echo ""
        hr
        echo -e "  ${DIM}作者：${WHITE}Go-iptv${NC}  ${DIM}TG 交流群：${YELLOW}https://t.me/GPT_858${NC}"
        hr
        echo ""
    else
        echo -e "  ${RED}${BOLD}┌─────────────────────────────────────────────┐${NC}"
        echo -e "  ${RED}${BOLD}│              ✘  服务启动失败                │${NC}"
        echo -e "  ${RED}${BOLD}└─────────────────────────────────────────────┘${NC}"
        echo ""
        warn "错误日志如下："
        echo ""
        hr
        journalctl -u "$SERVICE_NAME" -n 30 --no-pager 2>/dev/null || true
        hr
        echo ""
        read -rp "  按回车返回菜单..." _
        show_menu
        return
    fi

    read -rp "  按回车返回菜单..." _
    show_menu
}

# ─── 卸载 ─────────────────────────────────────────────────────────────────────

do_uninstall() {
    clear
    echo ""
    echo -e "  ${RED}${BOLD}┌─────────────────────────────────────────────┐${NC}"
    echo -e "  ${RED}${BOLD}│                  卸载程序                   │${NC}"
    echo -e "  ${RED}${BOLD}└─────────────────────────────────────────────┘${NC}"
    echo ""
    warn "此操作将删除以下所有文件，且无法恢复！"
    echo ""
    echo -e "  ${DIM}服务文件：${YELLOW}$SERVICE_FILE${NC}"
    echo -e "  ${DIM}程序目录：${YELLOW}$INSTALL_DIR${NC}（含所有配置数据）"
    echo -e "  ${DIM}管理命令：${YELLOW}$SCRIPT_PATH${NC}"
    echo ""
    hr
    read -rp "  确认卸载？输入 yes 或 y 继续: " CONFIRM
    echo ""

    if [[ "$CONFIRM" != "yes" && "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        warn "已取消卸载"
        sleep 1
        show_menu
        return
    fi

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        step "停止服务..."
        systemctl stop "$SERVICE_NAME"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        step "禁用开机自启..."
        systemctl disable "$SERVICE_NAME" --quiet
    fi

    [ -f "$SERVICE_FILE" ] && { step "删除服务文件..."; rm -f "$SERVICE_FILE"; systemctl daemon-reload; }
    [ -d "$INSTALL_DIR" ]  && { step "删除程序目录..."; rm -rf "$INSTALL_DIR"; }
    [ -f "$SCRIPT_PATH" ]  && { step "删除管理命令..."; rm -f "$SCRIPT_PATH"; }

    echo ""
    success "卸载完成，所有文件已删除"
    echo ""
    exit 0
}

# ─── 其他操作 ─────────────────────────────────────────────────────────────────

do_restart() {
    echo ""
    step "正在重启服务..."
    if systemctl restart "$SERVICE_NAME"; then
        sleep 1
        success "重启成功"
    else
        warn "重启失败，请查看日志"
    fi
    sleep 1; show_menu
}

do_stop() {
    echo ""
    step "正在停止服务..."
    systemctl stop "$SERVICE_NAME" && success "服务已停止" || warn "停止失败"
    sleep 1; show_menu
}

do_start() {
    echo ""
    step "正在启动服务..."
    systemctl start "$SERVICE_NAME" && success "启动成功" || warn "启动失败"
    sleep 1; show_menu
}

do_logs() {
    echo ""
    echo -e "  ${DIM}显示最近 50 行日志，按 Ctrl+C 退出${NC}"
    echo ""
    journalctl -u "$SERVICE_NAME" -n 50 -f
    show_menu
}

do_update() {
    echo ""
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        error "未找到 curl 或 wget"
    fi

    step "停止服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    step "下载最新版本..."
    if command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$INSTALL_DIR/$BINARY_NAME" "$DOWNLOAD_URL" || error "下载失败"
    else
        wget --show-progress -O "$INSTALL_DIR/$BINARY_NAME" "$DOWNLOAD_URL" || error "下载失败"
    fi
    chmod +x "$INSTALL_DIR/$BINARY_NAME"

    step "重启服务..."
    systemctl start "$SERVICE_NAME"
    sleep 2

    echo ""
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        success "更新成功！"
    else
        warn "服务启动失败，请查看日志"
    fi
    echo ""
    read -rp "  按回车返回菜单..." _
    show_menu
}

# ─── 安装管理命令 ─────────────────────────────────────────────────────────────

install_command() {
    local self
    self=$(readlink -f "$0" 2>/dev/null)
    if [ -f "$self" ] && [ "$self" != "/dev/stdin" ]; then
        cp "$self" "$SCRIPT_PATH" && chmod +x "$SCRIPT_PATH" && return
    fi
    if command -v curl &>/dev/null; then
        curl -sL "$INSTALL_SCRIPT_URL" -o "$SCRIPT_PATH" && chmod +x "$SCRIPT_PATH" && return
    elif command -v wget &>/dev/null; then
        wget -qO "$SCRIPT_PATH" "$INSTALL_SCRIPT_URL" && chmod +x "$SCRIPT_PATH" && return
    fi
    warn "管理命令安装失败，可手动执行: curl -sL $INSTALL_SCRIPT_URL | bash"
}

# ─── 入口 ─────────────────────────────────────────────────────────────────────

show_menu
