#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail

# ========== 路径初始化 ==========
init_paths() {
    REAL_PATH=$(readlink -f "$0")
    SCRIPT_NAME=$(basename "$REAL_PATH")

    # 如果是通过 oplist 快捷方式启动，需要查找原始脚本目录
    if [ "$SCRIPT_NAME" = "oplist" ] || [ "$REAL_PATH" = "/data/data/com.termux/files/usr/bin/oplist" ]; then
        # 尝试从 HOME 目录找到原始脚本
        if [ -f "$HOME/main.sh" ]; then
            SCRIPT_DIR="$HOME"
        elif [ -f "$HOME/openlist_termux/main.sh" ]; then
            SCRIPT_DIR="$HOME/openlist_termux"
        elif [ -f "$HOME/.openlist_termux/main.sh" ]; then
            SCRIPT_DIR="$HOME/.openlist_termux"
        elif [ -f "$HOME/project/openlist_termux/main.sh" ]; then
            SCRIPT_DIR="$HOME/project/openlist_termux"
        else
            # 尝试从 PREFIX 目录找
            if [ -f "$PREFIX/etc/openlist_termux/main.sh" ]; then
                SCRIPT_DIR="$PREFIX/etc/openlist_termux"
            else
                echo -e "${ERROR} 无法找到原始脚本目录！"
                echo -e "${INFO} 请确保所有脚本文件放在以下位置之一："
                echo -e "    - $HOME/"
                echo -e "    - $HOME/openlist_termux/"
                echo -e "    - $HOME/.openlist_termux/"
                exit 1
            fi
        fi
        REAL_PATH="$SCRIPT_DIR/main.sh"
    else
        SCRIPT_DIR=$(dirname "$REAL_PATH")
    fi

    DEST_DIR="$HOME/Openlist"
    DATA_DIR="$DEST_DIR/data"
    OPENLIST_BIN="$PREFIX/bin/openlist"
    OPENLIST_LOGDIR="$DATA_DIR/log"
    OPENLIST_LOG="$OPENLIST_LOGDIR/openlist.log"
    OPENLIST_CONF="$DATA_DIR/config.json"

    ARIA2_DIR="$HOME/aria2"
    ARIA2_LOG="$ARIA2_DIR/aria2.log"
    ARIA2_CONF="$ARIA2_DIR/aria2.conf"
    ARIA2_CMD="aria2c"

    OPLIST_PATH="$PREFIX/bin/oplist"
    CACHE_DIR="$DATA_DIR/.cache"
    VERSION_CACHE="$CACHE_DIR/version.cache"
    VERSION_CHECKING="$CACHE_DIR/version.checking"

    BACKUP_DIR="/sdcard/Download"
    CONFIG_DIR="$HOME/.cloudflared"
    CF_CONFIG="$CONFIG_DIR/config.yml"
    CF_LOG="$CONFIG_DIR/tunnel.log"

    # 模块脚本路径
    OPENLIST_MODULE="$SCRIPT_DIR/openlist.sh"
    ARIA2_MODULE="$SCRIPT_DIR/aria2.sh"
    BACKUP_MODULE="$SCRIPT_DIR/backup.sh"
    TUNNEL_MODULE="$SCRIPT_DIR/tunnel.sh"
}

# ========== 环境初始化 ==========
load_env() {
    local env_candidates=(
        "$SCRIPT_DIR/.env"
        "$HOME/.env"
    )

    for env_file in "${env_candidates[@]}"; do
        if [ -f "$env_file" ]; then
            # shellcheck disable=SC1090
            source "$env_file"
            ENV_FILE="$env_file"
            # 为可选变量设置默认值（兼容 set -u）
            GITHUB_TOKEN="${GITHUB_TOKEN:-}"
            TUNNEL_NAME="${TUNNEL_NAME:-}"
            DOMAIN="${DOMAIN:-}"
            LOCAL_PORT="${LOCAL_PORT:-5244}"
            ARIA2_SECRET="${ARIA2_SECRET:-}"
            return 0
        fi
    done

    echo -e "${ERROR} 未找到配置文件 .env"
    echo -e "${INFO} 请优先在脚本目录放置 .env：${C_BOLD_YELLOW}$SCRIPT_DIR/.env${C_RESET}"
    echo -e "${INFO} 也兼容读取：${C_BOLD_YELLOW}$HOME/.env${C_RESET}"
    exit 1
}

# ========== 模块检查 ==========
check_modules() {
    local missing=0

    for mod in "$OPENLIST_MODULE" "$ARIA2_MODULE" "$BACKUP_MODULE" "$TUNNEL_MODULE"; do
        if [ ! -f "$mod" ]; then
            echo -e "${ERROR} 找不到模块文件：${C_BOLD_YELLOW}$(basename "$mod")${C_RESET}"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        echo ""
        echo -e "${ERROR} 缺少必要的模块文件！"
        echo -e "${INFO} 所有脚本文件应该在同一目录：${C_BOLD_YELLOW}$SCRIPT_DIR${C_RESET}"
        echo -e "${INFO} 需要的文件：main.sh, openlist.sh, aria2.sh, backup.sh, tunnel.sh"
        exit 1
    fi
}

# ========== 快捷方式管理 ==========
ensure_oplist_shortcut() {
    if ! echo "$PATH" | grep -q "$PREFIX/bin"; then
        export PATH="$PATH:$PREFIX/bin"
        if ! grep -q "$PREFIX/bin" ~/.bashrc 2>/dev/null; then
            echo "export PATH=\$PATH:$PREFIX/bin" >> ~/.bashrc
        fi
        echo -e "${INFO} 已将 ${C_BOLD_YELLOW}$PREFIX/bin${C_RESET} 添加到 PATH。请重启终端确保永久生效。"
    fi

    if [ "$REAL_PATH" = "$OPLIST_PATH" ]; then
        return 0
    fi

    cat > "$OPLIST_PATH" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
exec "$REAL_PATH" "\$@"
EOF
    chmod +x "$OPLIST_PATH"

    echo -e "${SUCCESS} 已将脚本安装为全局命令：${C_BOLD_YELLOW}oplist${C_RESET}"
    echo -e "${INFO} 你现在可以随时输入 ${C_BOLD_YELLOW}oplist${C_RESET} 启动管理菜单！"
}

init_cache_dir() {
    [ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
    [ -d "$BACKUP_DIR" ] || mkdir -p "$BACKUP_DIR"
    [ -d "$CONFIG_DIR" ] || mkdir -p "$CONFIG_DIR"
}

# ========== 版本检测 ==========
get_local_version() {
    if [ -f "$OPENLIST_BIN" ]; then
        "$OPENLIST_BIN" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1
    fi
}

get_latest_version() {
    if [ -f "$VERSION_CACHE" ] && [ -s "$VERSION_CACHE" ] && [ "$(find "$VERSION_CACHE" -mmin -20)" ]; then
        head -n1 "$VERSION_CACHE"
    else
        echo "检测更新中..."
    fi
}

check_version_bg() {
    # 清理超过 60 秒的过期锁文件
    if [ -f "$VERSION_CHECKING" ]; then
        local lock_age
        lock_age=$(( $(date +%s) - $(stat -c %Y "$VERSION_CHECKING" 2>/dev/null || echo 0) ))
        if [ "$lock_age" -gt 60 ]; then
            rm -f "$VERSION_CHECKING"
        fi
    fi

    if { [ ! -f "$VERSION_CACHE" ] || [ ! -s "$VERSION_CACHE" ] || [ ! "$(find "$VERSION_CACHE" -mmin -20)" ]; } && [ ! -f "$VERSION_CHECKING" ]; then
        if [ -z "$GITHUB_TOKEN" ]; then
            return
        fi
        touch "$VERSION_CHECKING"
        (
            result=$(curl -s -m 10 -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/OpenListTeam/OpenList/releases/latest" | \
                sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
            if [ -n "$result" ]; then
                printf '%s\n' "$result" > "$VERSION_CACHE"
            fi
            rm -f "$VERSION_CHECKING"
        ) &
    fi
}

# ========== 辅助函数 ==========
divider() {
    echo -e "${C_BOLD_BLUE}======================================${C_RESET}"
}

openlist_status_line() {
    if check_openlist_process; then
        PIDS=$(pgrep -f "$OPENLIST_BIN server")
        echo -e "${INFO} OpenList 状态：${C_BOLD_GREEN}运行中 (PID: $PIDS)${C_RESET}"
    else
        echo -e "${INFO} OpenList 状态：${C_BOLD_RED}未运行${C_RESET}"
    fi
}

aria2_status_line() {
    if check_aria2_process; then
        PIDS=$(pgrep -f "$ARIA2_CMD --conf-path=$ARIA2_CONF")
        echo -e "${INFO} aria2 状态：${C_BOLD_GREEN}运行中 (PID: $PIDS)${C_RESET}"
    else
        echo -e "${INFO} aria2 状态：${C_BOLD_RED}未运行${C_RESET}"
    fi
}

tunnel_status_line() {
    if [ -z "$TUNNEL_NAME" ]; then
        echo -e "${INFO} 隧道状态：${C_BOLD_YELLOW}未配置${C_RESET}"
        return
    fi
    if pgrep -f "cloudflared.*$TUNNEL_NAME" >/dev/null; then
        PIDS=$(pgrep -f "cloudflared.*$TUNNEL_NAME")
        echo -e "${INFO} 隧道状态：${C_BOLD_GREEN}运行中 (PID: $PIDS)${C_RESET}"
    else
        echo -e "${INFO} 隧道状态：${C_BOLD_RED}未运行${C_RESET}"
    fi
}

# ========== 启动和停止组合函数 ==========
start_all() {
    # 启动 aria2
    start_aria2

    # 启动 OpenList
    start_openlist

    divider
    echo -e "${C_BOLD_CYAN}是否开启 OpenList 和 aria2 开机自启？(y/n):${C_RESET}"
    read -r enable_boot
    if [ "$enable_boot" = "y" ] || [ "$enable_boot" = "Y" ]; then
        enable_autostart_openlist
        enable_autostart_aria2
    else
        disable_autostart_openlist
        disable_autostart_aria2
        echo -e "${INFO} 未开启开机自启。"
    fi
    divider

    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock
    fi
    return 0
}

stop_all() {
    # 停止 OpenList
    stop_openlist

    # 停止 aria2
    stop_aria2

    return 0
}

# ========== 一键卸载 ==========
uninstall_all() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│       一键卸载           │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    echo ""
    echo -e "${WARN} 此操作将卸载以下所有组件："
    echo -e "  - OpenList（进程、数据、可执行文件、开机自启）"
    echo -e "  - aria2（进程、配置、数据、开机自启）"
    echo -e "  - Cloudflare Tunnel（进程、凭证、配置、开机自启）"
    echo -e "  - 全局快捷命令 ${C_BOLD_YELLOW}oplist${C_RESET}"
    echo ""
    echo -ne "${C_BOLD_RED}确定全部卸载？此操作不可恢复！(y/n):${C_RESET} "
    read -r confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${INFO} 已取消卸载。"
        wait_enter
        return 0
    fi

    echo ""

    # 停止所有进程
    echo -e "${INFO} 正在停止所有进程..."
    pkill -f "$OPENLIST_BIN" 2>/dev/null || true
    pkill -f "$ARIA2_CMD" 2>/dev/null || true
    pkill -f "cloudflared" 2>/dev/null || true
    sleep 1

    # 禁用开机自启
    disable_autostart_openlist >/dev/null 2>&1 || true
    disable_autostart_aria2 >/dev/null 2>&1 || true
    disable_autostart_tunnel >/dev/null 2>&1 || true

    # 删除数据和配置
    echo -e "${INFO} 正在删除 OpenList..."
    rm -rf "$DEST_DIR"
    rm -f "$OPENLIST_BIN"
    echo -e "${SUCCESS} OpenList 已卸载。"

    echo -e "${INFO} 正在删除 aria2..."
    if command -v pkg >/dev/null 2>&1; then
        pkg uninstall -y aria2 2>/dev/null || true
        apt autoremove -y 2>/dev/null || true
    fi
    rm -rf "$ARIA2_DIR"
    echo -e "${SUCCESS} aria2 已卸载。"

    echo -e "${INFO} 正在删除 Cloudflare Tunnel..."
    if command -v pkg >/dev/null 2>&1; then
        pkg uninstall -y cloudflared 2>/dev/null || true
        apt autoremove -y 2>/dev/null || true
    fi
    rm -rf "$CONFIG_DIR"
    echo -e "${SUCCESS} Cloudflare Tunnel 已卸载。"

    # 删除快捷命令
    rm -f "$OPLIST_PATH"
    echo -e "${SUCCESS} 快捷命令 oplist 已移除。"

    echo ""
    echo -e "${SUCCESS} 全部卸载完成。"
    wait_enter
}

# ========== 更多功能菜单 ==========
show_more_menu() {
    while true; do
        clear
        echo -e "${C_BOLD_BLUE}============= 更多功能 =============${C_RESET}"
        echo -e "${C_BOLD_GREEN}1. 修改 OpenList 密码${C_RESET}"
        echo -e "${C_BOLD_YELLOW}2. 编辑 OpenList 配置文件${C_RESET}"
        echo -e "${C_BOLD_LIME}3. 编辑 aria2 配置文件${C_RESET}"
        echo -e "${C_BOLD_CYAN}4. 更新 aria2 BT Tracker${C_RESET}"
        echo -e "${C_BOLD_RED}5. 备份/还原 Openlist 配置${C_RESET}"
        echo -e "${C_BOLD_ORANGE}6. 开启 OpenList 外网访问${C_RESET}"
        echo -e "${C_BOLD_PINK}7. 停止 OpenList 外网访问${C_RESET}"
        echo -e "${C_BOLD_LIME}8. 查看 Cloudflare Tunnel 日志${C_RESET}"
        echo -e "${C_BOLD_RED}9. 一键卸载${C_RESET}"
        echo -e "${C_BOLD_GRAY}0. 返回主菜单${C_RESET}"
        echo -ne "${C_BOLD_CYAN}请输入选项 (0-9):${C_RESET} "
        read -r sub_choice
        case $sub_choice in
            1) reset_openlist_password ;;
            2) edit_openlist_config ;;
            3) edit_aria2_config ;;
            4) update_bt_tracker ;;
            5) backup_restore_menu ;;
            6) setup_cloudflare_tunnel ;;
            7) stop_cloudflare_tunnel ;;
            8) view_tunnel_log ;;
            9) uninstall_all ;;
            0) break ;;
            *) echo -e "${ERROR} 无效选项，请输入 0-9。"; read -r ;;
        esac
    done
}

# ========== 主菜单显示 ==========
show_menu() {
    clear
    echo -e "${C_BOLD_BLUE}=====================================${C_RESET}"
    echo -e "${C_BOLD_MAGENTA}         🌟 OpenList 管理菜单 🌟${C_RESET}"
    echo -e "${C_BOLD_BLUE}=====================================${C_RESET}"
    init_cache_dir
    local_ver=$(get_local_version)
    latest_ver=$(get_latest_version)
    if [ "$latest_ver" = "检测更新中..." ]; then
        ver_status="${C_BOLD_YELLOW}检测更新中...${C_RESET}"
    elif [ -z "$local_ver" ]; then
        ver_status="${C_BOLD_YELLOW}未安装${C_RESET}"
    elif [ -z "$latest_ver" ]; then
        ver_status="${C_BOLD_GREEN}已安装 $local_ver${C_RESET}"
    elif [ "$local_ver" = "$latest_ver" ]; then
        ver_status="${C_BOLD_GREEN}已是最新 $local_ver${C_RESET}"
    else
        ver_status="${C_BOLD_YELLOW}有新版 $latest_ver (当前 $local_ver)${C_RESET}"
    fi
    openlist_status_line
    aria2_status_line
    tunnel_status_line
    echo -e "${INFO} OpenList 版本：$ver_status"
    echo -e "${C_BOLD_BLUE}=====================================${C_RESET}"
    echo -e "${C_BOLD_GREEN}1. 安装 OpenList${C_RESET}"
    echo -e "${C_BOLD_YELLOW}2. 更新 OpenList${C_RESET}"
    echo -e "${C_BOLD_LIME}3. 启动 OpenList 和 aria2${C_RESET}"
    echo -e "${C_BOLD_RED}4. 停止 OpenList 和 aria2${C_RESET}"
    echo -e "${C_BOLD_ORANGE}5. 查看 OpenList 启动日志${C_RESET}"
    echo -e "${C_BOLD_PINK}6. 查看 aria2 启动日志${C_RESET}"
    echo -e "${C_BOLD_CYAN}7. 更多功能${C_RESET}"
    echo -e "${C_BOLD_GRAY}0. 退出${C_RESET}"
    echo -e "${C_BOLD_BLUE}=====================================${C_RESET}"
    echo -ne "${C_BOLD_CYAN}请输入选项 (0-7):${C_RESET} "
}

# ========== 主程序流程 ==========
init_paths
source "$SCRIPT_DIR/common.sh"
load_env
check_modules
source "$OPENLIST_MODULE"
source "$ARIA2_MODULE"
source "$BACKUP_MODULE"
source "$TUNNEL_MODULE"
ensure_oplist_shortcut

while true; do
    show_menu
    check_version_bg
    read -r choice
    case $choice in
        1) install_openlist; wait_enter ;;
        2) update_openlist; wait_enter ;;
        3) start_all; wait_enter ;;
        4) stop_all; wait_enter ;;
        5) view_openlist_log ;;
        6) view_aria2_log ;;
        7) show_more_menu ;;
        0) echo -e "${INFO} 退出程序。"; exit 0 ;;
        *) echo -e "${ERROR} 无效选项，请输入 0-7。"; wait_enter ;;
    esac
done
