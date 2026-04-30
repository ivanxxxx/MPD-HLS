#!/bin/bash
# mpd2hls 一键安装/管理脚本
# 用法: bash install.sh

BINARY_NAME="mpd2hls"
INSTALL_DIR="/opt/mpd2hls"
SERVICE_NAME="mpd2hls"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_PATH="/usr/local/bin/mpd2hls"

# 根据架构选择下载地址
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
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }
title() { echo -e "${CYAN}$1${NC}"; }

# 检查 root
[ "$(id -u)" -eq 0 ] || error "请使用 root 权限运行"

# ─── 管理面板 ────────────────────────────────────────────────────────────────
show_menu() {
    clear
    title "================================================"
    title "         MPD2HLS 管理面板                       "
    title "================================================"
    echo ""

    # 显示当前状态
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        PORT=$(systemctl show "$SERVICE_NAME" -p Environment 2>/dev/null \
            | grep -o 'PANEL_LISTEN=[^ ]*' | cut -d: -f2 || echo "?")
        SERVER_IP=$(curl -s4 --connect-timeout 3 ifconfig.me 2>/dev/null \
            || hostname -I | awk '{print $1}')
        echo -e "  状态: ${GREEN}运行中${NC}"
        echo -e "  访问: ${GREEN}http://${SERVER_IP}:${PORT}/admin${NC}"
    else
        echo -e "  状态: ${RED}未运行${NC}"
    fi

    echo ""
    echo "  1. 安装"
    echo "  2. 重启服务"
    echo "  3. 停止服务"
    echo "  4. 启动服务"
    echo "  5. 查看日志"
    echo "  6. 更新程序"
    echo "  7. 卸载（删除所有安装的文件）"
    echo "  0. 退出"
    echo ""
    read -rp "请选择 > " CHOICE

    case "$CHOICE" in
        1) do_install ;;
        2) do_restart ;;
        3) do_stop ;;
        4) do_start ;;
        5) do_logs ;;
        6) do_update ;;
        7) do_uninstall ;;
        0) exit 0 ;;
        *) warn "无效选项"; sleep 1; show_menu ;;
    esac
}

# ─── 安装 ────────────────────────────────────────────────────────────────────
do_install() {
    clear
    title "================================================"
    title "         MPD2HLS 一键安装                       "
    title "================================================"
    echo ""

    # 检查系统架构
    if [ -z "$DOWNLOAD_URL" ]; then
        error "不支持的系统架构: $ARCH（支持 x86_64 / aarch64 / armv7l）"
    fi
    info "系统架构: $ARCH"

    # 检查下载工具
    if command -v curl &>/dev/null; then
        DOWNLOADER="curl"
    elif command -v wget &>/dev/null; then
        DOWNLOADER="wget"
    else
        error "未找到 curl 或 wget，请先安装其中一个"
    fi

    # 输入端口
    while true; do
        echo -e "请输入面板端口 ${YELLOW}[默认: 9527]${NC}"
        read -rp "端口 > " PORT_INPUT
        PORT="${PORT_INPUT:-9527}"

        if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
            warn "端口无效，请输入 1-65535 之间的数字"
            continue
        fi

        if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${PORT} "; then
            warn "端口 $PORT 已被占用，请换一个"
            continue
        fi

        break
    done

    echo ""
    echo -e "  端口: ${GREEN}$PORT${NC}"
    echo ""
    read -rp "确认以上配置，按回车开始安装..." _CONFIRM
    echo ""

    # 停止旧服务
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        info "停止旧服务..."
        systemctl stop "$SERVICE_NAME"
    fi

    # 创建目录
    info "创建安装目录 $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    # 下载
    info "正在下载程序..."
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -L --progress-bar -o "$INSTALL_DIR/$BINARY_NAME" "$DOWNLOAD_URL" || error "下载失败，请检查网络"
    else
        wget --show-progress -O "$INSTALL_DIR/$BINARY_NAME" "$DOWNLOAD_URL" || error "下载失败，请检查网络"
    fi
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    info "下载完成"

    # 安装管理命令
    install_command

    # 创建 systemd 服务
    info "配置系统服务..."
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=MPD2HLS Panel Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStartPre=/usr/bin/pkill -f $INSTALL_DIR/$BINARY_NAME || true
ExecStartPre=/bin/sleep 1
ExecStart=$INSTALL_DIR/$BINARY_NAME
Restart=always
RestartSec=5
Environment=PANEL_LISTEN=0.0.0.0:${PORT}
Environment=PANEL_ADMIN_PATH=/admin

[Install]
WantedBy=multi-user.target
EOF

    info "启动服务..."
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        SERVER_IP=$(curl -s4 --connect-timeout 5 ifconfig.me 2>/dev/null \
            || curl -s4 --connect-timeout 5 ip.sb 2>/dev/null \
            || hostname -I | awk '{print $1}')
        echo ""
        title "================================================"
        title "              安装成功！                        "
        title "================================================"
        echo ""
        echo -e "  访问地址: ${GREEN}http://${SERVER_IP}:${PORT}/admin${NC}"
        echo -e "  默认账号: ${GREEN}admin${NC}"
        echo -e "  默认密码: ${GREEN}admin123${NC}"
        echo ""
        echo -e "  输入 ${CYAN}mpd2hls${NC} 可随时返回此管理面板"
        echo ""
    else
        error "服务启动失败，请运行: journalctl -u $SERVICE_NAME -n 50"
    fi

    read -rp "按回车返回菜单..." _
    show_menu
}

# ─── 卸载 ────────────────────────────────────────────────────────────────────
do_uninstall() {
    echo ""
    warn "此操作将删除所有安装的文件，包括程序、配置和服务！"
    echo -e "  - 服务文件: $SERVICE_FILE"
    echo -e "  - 程序目录: $INSTALL_DIR（含所有配置数据）"
    echo -e "  - 管理命令: $SCRIPT_PATH"
    echo ""
    read -rp "确认卸载？输入 yes 继续: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        warn "已取消"
        sleep 1
        show_menu
        return
    fi

    echo ""
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        info "停止服务..."
        systemctl stop "$SERVICE_NAME"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        info "禁用开机自启..."
        systemctl disable "$SERVICE_NAME"
    fi

    [ -f "$SERVICE_FILE" ] && { info "删除服务文件..."; rm -f "$SERVICE_FILE"; systemctl daemon-reload; }
    [ -d "$INSTALL_DIR" ] && { info "删除程序目录..."; rm -rf "$INSTALL_DIR"; }
    [ -f "$SCRIPT_PATH" ] && { info "删除管理命令..."; rm -f "$SCRIPT_PATH"; }

    echo ""
    title "================================================"
    title "              卸载完成！                        "
    title "================================================"
    echo ""
    info "所有文件已删除"
    echo ""
    exit 0
}

# ─── 其他操作 ─────────────────────────────────────────────────────────────────
do_restart() {
    info "重启服务..."
    systemctl restart "$SERVICE_NAME" && info "重启成功" || warn "重启失败"
    sleep 1; show_menu
}

do_stop() {
    info "停止服务..."
    systemctl stop "$SERVICE_NAME" && info "已停止" || warn "停止失败"
    sleep 1; show_menu
}

do_start() {
    info "启动服务..."
    systemctl start "$SERVICE_NAME" && info "启动成功" || warn "启动失败"
    sleep 1; show_menu
}

do_logs() {
    echo ""
    info "显示最近 50 行日志（Ctrl+C 退出）"
    echo ""
    journalctl -u "$SERVICE_NAME" -n 50 -f
    show_menu
}

do_update() {
    echo ""
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        error "未找到 curl 或 wget"
    fi

    info "停止服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    info "下载最新版本..."
    if command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$INSTALL_DIR/$BINARY_NAME" "$DOWNLOAD_URL" || error "下载失败"
    else
        wget --show-progress -O "$INSTALL_DIR/$BINARY_NAME" "$DOWNLOAD_URL" || error "下载失败"
    fi
    chmod +x "$INSTALL_DIR/$BINARY_NAME"

    info "重启服务..."
    systemctl start "$SERVICE_NAME"
    sleep 1

    systemctl is-active --quiet "$SERVICE_NAME" && info "更新成功！" || warn "服务启动失败"
    read -rp "按回车返回菜单..." _
    show_menu
}

# ─── 安装管理命令 ─────────────────────────────────────────────────────────────
install_command() {
    cp "$0" "$SCRIPT_PATH" 2>/dev/null || cp "$(readlink -f "$0")" "$SCRIPT_PATH" 2>/dev/null || true
    chmod +x "$SCRIPT_PATH" 2>/dev/null || true
}

# ─── 入口 ─────────────────────────────────────────────────────────────────────
show_menu
