#!/data/data/com.termux/files/usr/bin/bash

# ========== OpenList 专用模块 ==========
# 负责 OpenList 的安装、启动、更新、停止等相关操作

# 颜色定义（来自主脚本）
C_BOLD_BLUE="\033[1;34m"
C_BOLD_GREEN="\033[1;32m"
C_BOLD_YELLOW="\033[1;33m"
C_BOLD_RED="\033[1;31m"
C_BOLD_CYAN="\033[1;36m"
C_BOLD_MAGENTA="\033[1;35m"
C_RESET="\033[0m"

INFO="${C_BOLD_BLUE}[INFO]${C_RESET}"
ERROR="${C_BOLD_RED}[ERROR]${C_RESET}"
SUCCESS="${C_BOLD_GREEN}[OK]${C_RESET}"
WARN="${C_BOLD_YELLOW}[WARN]${C_RESET}"

OPENLIST_LATEST_URL="https://github.com/OpenListTeam/OpenList/releases/latest/download/openlist-android-arm64.tar.gz"

require_openlist_tools() {
    local missing=0
    for cmd in curl tar; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${ERROR} 缺少必要命令：${C_BOLD_YELLOW}$cmd${C_RESET}"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        echo -e "${INFO} 请先在 Termux 中安装缺失依赖后重试。"
        return 1
    fi
    return 0
}

get_latest_url() {
    printf '%s\n' "$OPENLIST_LATEST_URL"
}

download_with_progress() {
    local url="$1"
    local output="$2"
    local tmp_file="${output}.tmp"

    rm -f "$tmp_file"
    if curl -fL --retry 2 --connect-timeout 15 --progress-bar -o "$tmp_file" "$url"; then
        mv -f "$tmp_file" "$output"
        return 0
    fi

    rm -f "$tmp_file"
    return 1
}

extract_openlist_binary() {
    local archive="$1"
    local extract_dir="$2"
    local binary_path=""

    mkdir -p "$extract_dir" || return 1
    tar -zxf "$archive" -C "$extract_dir" || return 1

    binary_path=$(find "$extract_dir" -maxdepth 3 -type f -name openlist | head -n 1)
    if [ -z "$binary_path" ] || [ ! -f "$binary_path" ]; then
        return 1
    fi

    printf '%s\n' "$binary_path"
}

install_or_update_openlist() {
    local mode="$1"
    local file_name="openlist-android-arm64.tar.gz"
    local download_url tmp_dir archive extract_dir binary_path

    require_openlist_tools || return 1
    download_url=$(get_latest_url)
    if [ -z "$download_url" ]; then
        echo -e "${ERROR} 未能获取到 OpenList 安装包下载地址。"
        return 1
    fi

    tmp_dir=$(mktemp -d) || {
        echo -e "${ERROR} 无法创建临时目录。"
        return 1
    }
    archive="$tmp_dir/$file_name"
    extract_dir="$tmp_dir/extract"

    echo -e "${INFO} 正在下载 ${C_BOLD_YELLOW}$file_name${C_RESET} ..."
    if ! download_with_progress "$download_url" "$archive"; then
        rm -rf "$tmp_dir"
        echo -e "${ERROR} 下载文件失败。"
        return 1
    fi

    echo -e "${INFO} 正在解压 ${C_BOLD_YELLOW}$file_name${C_RESET} ..."
    binary_path=$(extract_openlist_binary "$archive" "$extract_dir") || {
        rm -rf "$tmp_dir"
        echo -e "${ERROR} 解压文件失败或未找到 openlist 可执行文件。"
        return 1
    }

    mkdir -p "$DEST_DIR" "$DATA_DIR" "$OPENLIST_LOGDIR"
    cp -f "$binary_path" "$OPENLIST_BIN" || {
        rm -rf "$tmp_dir"
        echo -e "${ERROR} 无法写入 ${C_BOLD_YELLOW}$OPENLIST_BIN${C_RESET}"
        return 1
    }
    chmod +x "$OPENLIST_BIN"
    rm -rf "$tmp_dir"
    rm -f "$VERSION_CACHE"

    if [ "$mode" = "install" ]; then
        echo -e "${SUCCESS} OpenList 安装完成！（已放入 $OPENLIST_BIN）"
    else
        echo -e "${SUCCESS} OpenList 更新完成！"
    fi
    return 0
}

install_openlist() {
    install_or_update_openlist install
}

update_openlist() {
    if [ ! -f "$OPENLIST_BIN" ]; then
        echo -e "${WARN} 未检测到已安装的 openlist，可直接执行安装流程。"
    fi
    install_or_update_openlist update
}

edit_openlist_config() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│ 编辑 OpenList 配置文件   │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    if [ -f "$OPENLIST_CONF" ]; then
        echo -e "${INFO} 正在编辑 OpenList 配置文件：${C_BOLD_YELLOW}$OPENLIST_CONF${C_RESET}"
        vi "$OPENLIST_CONF"
        echo -e "${SUCCESS} OpenList 配置文件编辑完成。"
    else
        echo -e "${ERROR} 未找到 OpenList 配置文件：${C_BOLD_YELLOW}$OPENLIST_CONF${C_RESET}"
    fi
    echo -e "${C_BOLD_MAGENTA}按回车键返回菜单...${C_RESET}"
    read
}

view_openlist_log() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│ 查看 OpenList 日志       │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    if [ -f "$OPENLIST_LOG" ]; then
        echo -e "${INFO} 显示 OpenList 日志文件：${C_BOLD_YELLOW}$OPENLIST_LOG${C_RESET}"
        tail -n 200 "$OPENLIST_LOG"
    else
        echo -e "${ERROR} 未找到 OpenList 日志文件：${C_BOLD_YELLOW}$OPENLIST_LOG${C_RESET}"
    fi
    echo -e "${C_BOLD_MAGENTA}按回车键返回菜单...${C_RESET}"
    read
}

reset_openlist_password() {
    echo -e "${C_BOLD_BLUE}┌─────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│ OpenList 密码重置           │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└─────────────────────────────┘${C_RESET}"

    if [ ! -x "$OPENLIST_BIN" ]; then
        echo -e "${ERROR} 未找到 OpenList 可执行文件，请先安装。"
        echo -e "${C_BOLD_MAGENTA}按回车键返回菜单...${C_RESET}"
        read
        return 1
    fi

    mkdir -p "$DEST_DIR" "$DATA_DIR"

    while true; do
        echo -ne "${C_BOLD_CYAN}请输入新密码:${C_RESET} "
        read -s pwd1
        echo
        echo -ne "${C_BOLD_CYAN}请再次输入新密码:${C_RESET} "
        read -s pwd2
        echo
        if [ "$pwd1" != "$pwd2" ]; then
            echo -e "${ERROR} 两次输入的密码不一致，请重新输入。"
        elif [ -z "$pwd1" ]; then
            echo -e "${ERROR} 密码不能为空，请重新输入。"
        else
            if (cd "$DEST_DIR" && "$OPENLIST_BIN" admin set "$pwd1"); then
                echo -e "${SUCCESS} 密码已设置完成。"
                break
            else
                echo -e "${ERROR} 密码设置失败，请检查 OpenList 是否已正确安装。"
                echo -e "${C_BOLD_MAGENTA}按回车键返回菜单...${C_RESET}"
                read
                return 1
            fi
        fi
    done
    echo -e "${C_BOLD_MAGENTA}按回车键返回菜单...${C_RESET}"
    read
}

check_openlist_process() {
    pgrep -f "$OPENLIST_BIN server" >/dev/null 2>&1
}

enable_autostart_openlist() {
    mkdir -p "$HOME/.termux/boot"
    local boot_file="$HOME/.termux/boot/openlist_autostart.sh"
    cat > "$boot_file" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
mkdir -p "$DEST_DIR" "$DATA_DIR" "$OPENLIST_LOGDIR"
cd "$DEST_DIR" || exit 1
"$OPENLIST_BIN" server > "$OPENLIST_LOG" 2>&1 &
EOF
    chmod +x "$boot_file"
    echo -e "${SUCCESS} OpenList 已成功设置开机自启"
}

disable_autostart_openlist() {
    local boot_file="$HOME/.termux/boot/openlist_autostart.sh"
    if [ -f "$boot_file" ]; then
        rm -f "$boot_file"
        echo -e "${INFO} 已禁用 OpenList 开机自启"
    fi
}

start_openlist() {
    if [ ! -f "$OPENLIST_BIN" ]; then
        echo -e "${ERROR} 未找到 openlist 可执行文件，请先安装 OpenList。"
        return 1
    fi

    mkdir -p "$DEST_DIR" "$DATA_DIR" "$OPENLIST_LOGDIR"

    if check_openlist_process; then
        PIDS=$(pgrep -f "$OPENLIST_BIN server")
        echo -e "${WARN} OpenList server 已运行，PID：${C_BOLD_YELLOW}$PIDS${C_RESET}"
        return 0
    fi

    if [ ! -x "$OPENLIST_BIN" ]; then
        chmod +x "$OPENLIST_BIN"
    fi

    echo -e "${INFO} 启动 OpenList server..."
    cd "$DEST_DIR" || {
        echo -e "${ERROR} 进入 ${C_BOLD_YELLOW}$DEST_DIR${C_RESET} 失败。"
        return 1
    }
    "$OPENLIST_BIN" server > "$OPENLIST_LOG" 2>&1 &
    OPENLIST_PID=$!
    cd "$SCRIPT_DIR" || true
    sleep 3

    if ! ps -p "$OPENLIST_PID" >/dev/null 2>&1; then
        echo -e "${ERROR} OpenList server 启动失败。"
        [ -f "$OPENLIST_LOG" ] && tail -n 50 "$OPENLIST_LOG"
        return 1
    fi

    echo -e "${SUCCESS} OpenList server 已启动 (PID: ${C_BOLD_YELLOW}$OPENLIST_PID${C_RESET})."
    if [ -f "$OPENLIST_LOG" ]; then
        PASSWORD=$(sed -n 's/.*initial password is: \([^[:space:]]\+\).*/\1/p' "$OPENLIST_LOG" | head -n 1)
        if [ -n "$PASSWORD" ]; then
            echo -e "${SUCCESS} 检测到 OpenList 初始账户信息："
            echo -e "    用户名：${C_BOLD_YELLOW}admin${C_RESET}"
            echo -e "    密码：  ${C_BOLD_YELLOW}$PASSWORD${C_RESET}"
        else
            echo -e "${INFO} 非首次启动未在日志中找到初始密码，请使用您设置的密码。"
        fi
    else
        echo -e "${WARN} 尚未生成 openlist.log 日志文件。"
    fi
    echo -e "${INFO} 请在系统浏览器访问：${C_BOLD_YELLOW}http://127.0.0.1:5244${C_RESET}"
    return 0
}

stop_openlist() {
    if check_openlist_process; then
        PIDS=$(pgrep -f "$OPENLIST_BIN server")
        echo -e "${INFO} 检测到 OpenList server 正在运行，PID：${C_BOLD_YELLOW}$PIDS${C_RESET}"
        echo -e "${INFO} 正在终止 OpenList server..."
        pkill -f "$OPENLIST_BIN server"
        sleep 1
        if check_openlist_process; then
            echo -e "${ERROR} 无法终止 OpenList server 进程。"
            return 1
        fi
        echo -e "${SUCCESS} OpenList server 已成功终止。"
    else
        echo -e "${WARN} OpenList server 未运行。"
    fi
    return 0
}

uninstall_openlist() {
    echo -e "${C_BOLD_RED}!!! 卸载将删除所有 OpenList 数据和配置，是否继续？(y/n):${C_RESET}"
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        pkill -f "$OPENLIST_BIN" 2>/dev/null || true
        disable_autostart_openlist >/dev/null 2>&1 || true
        rm -rf "$DEST_DIR"
        rm -f "$OPENLIST_BIN"
        echo -e "${SUCCESS} OpenList 已完成卸载。"
    else
        echo -e "${INFO} 已取消卸载。"
    fi
    echo -e "${C_BOLD_MAGENTA}按回车键返回菜单...${C_RESET}"
    read
}
