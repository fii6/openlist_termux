#!/data/data/com.termux/files/usr/bin/bash

# ========== OpenList 专用模块 ==========
# 负责 OpenList 的安装、启动、更新、停止等相关操作

source "${SCRIPT_DIR:-.}/common.sh"

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
    wait_enter
}

view_openlist_log() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│ 查看 OpenList 日志       │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    local svlog="$HOME/Openlist/data/log/sv/current"
    if [ -f "$OPENLIST_LOG" ]; then
        echo -e "${INFO} 显示 OpenList 主日志：${C_BOLD_YELLOW}$OPENLIST_LOG${C_RESET}"
        tail -n 200 "$OPENLIST_LOG"
    elif [ -f "$svlog" ]; then
        echo -e "${INFO} 显示 svlogd 当前日志：${C_BOLD_YELLOW}$svlog${C_RESET}"
        tail -n 200 "$svlog"
    else
        echo -e "${ERROR} 未找到 OpenList 日志（$OPENLIST_LOG 或 svlogd current）"
    fi
    wait_enter
}

reset_openlist_password() {
    echo -e "${C_BOLD_BLUE}┌─────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│ OpenList 密码重置           │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└─────────────────────────────┘${C_RESET}"

    if [ ! -x "$OPENLIST_BIN" ]; then
        echo -e "${ERROR} 未找到 OpenList 可执行文件，请先安装。"
        wait_enter
        return 1
    fi

    mkdir -p "$DEST_DIR" "$DATA_DIR"

    while true; do
        echo -ne "${C_BOLD_CYAN}请输入新密码:${C_RESET} "
        read -rs pwd1
        echo
        echo -ne "${C_BOLD_CYAN}请再次输入新密码:${C_RESET} "
        read -rs pwd2
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
                wait_enter
                return 1
            fi
        fi
    done
    wait_enter
}

check_openlist_process() {
    if service_running openlist; then
        return 0
    fi
    # 兼容仍以 nohup 方式残留的旧进程
    pgrep -f "$OPENLIST_BIN server" >/dev/null 2>&1
}

# 把任何遗留的 nohup OpenList 进程清理掉，让 runit 接管
migrate_legacy_openlist() {
    if pgrep -f "$OPENLIST_BIN server" >/dev/null 2>&1 && ! service_running openlist; then
        echo -e "${INFO} 检测到遗留的 OpenList nohup 进程，正在迁移到 runit 监督..."
        force_kill "$OPENLIST_BIN server" "OpenList server" >/dev/null 2>&1 || true
    fi
}

ensure_openlist_service() {
    ensure_termux_services || return 1
    install_service openlist || return 1
    ensure_runsvdir_running || return 1
    return 0
}

enable_autostart_openlist() {
    ensure_openlist_service || return 1
    write_services_boot_file
    clean_legacy_boot_files
    service_enable_autostart openlist
    echo -e "${SUCCESS} OpenList 已成功设置开机自启（runit 监督）"
}

disable_autostart_openlist() {
    if [ -d "$SV_DIR/openlist" ]; then
        service_disable_autostart openlist
        echo -e "${INFO} 已禁用 OpenList 开机自启（保留服务定义）"
    fi
    # 旧的 nohup 自启脚本若残留，一并清理
    rm -f "$HOME/.termux/boot/openlist_autostart.sh"
}

start_openlist() {
    if [ ! -f "$OPENLIST_BIN" ]; then
        echo -e "${ERROR} 未找到 openlist 可执行文件，请先安装 OpenList。"
        return 1
    fi

    mkdir -p "$DEST_DIR" "$DATA_DIR" "$OPENLIST_LOGDIR"
    rotate_log "$OPENLIST_LOG"

    migrate_legacy_openlist
    ensure_openlist_service || return 1

    if service_running openlist; then
        echo -e "${WARN} OpenList server 已在 runit 下运行。"
        sv status openlist 2>/dev/null
        return 0
    fi

    if [ ! -x "$OPENLIST_BIN" ]; then
        chmod +x "$OPENLIST_BIN"
    fi

    echo -e "${INFO} 启动 OpenList server (sv up openlist)..."
    sv up openlist >/dev/null 2>&1 || true

    # runsv 启动有约 1 秒延迟
    local i=0
    while [ "$i" -lt 6 ]; do
        if service_running openlist; then
            break
        fi
        sleep 1
        i=$((i + 1))
    done

    if ! service_running openlist; then
        echo -e "${ERROR} OpenList server 启动失败。"
        sv status openlist 2>/dev/null || true
        local svlog="$HOME/Openlist/data/log/sv/current"
        [ -f "$svlog" ] && tail -n 50 "$svlog"
        return 1
    fi

    local pid
    pid=$(sv status openlist 2>/dev/null | sed -n 's/^run: openlist: (pid \([0-9]\+\)).*/\1/p')
    echo -e "${SUCCESS} OpenList server 已启动 (PID: ${C_BOLD_YELLOW}${pid:-?}${C_RESET})."

    # 轮询 svlogd 当前日志直到出现初始密码（最长 12s）。
    # openlist 首次启动时会把 "initial password is: ..." 打到 stdout，
    # 经 runsv → svlogd → current 写入文件，需要给 IO 一点时间。
    local svlog="$HOME/Openlist/data/log/sv/current"
    local PASSWORD=""
    local k=0
    while [ "$k" -lt 12 ]; do
        if [ -f "$svlog" ]; then
            PASSWORD=$(sed -n 's/.*initial password is: \([^[:space:]]\+\).*/\1/p' "$svlog" | head -n 1)
            [ -n "$PASSWORD" ] && break
        fi
        if [ -f "$OPENLIST_LOG" ]; then
            PASSWORD=$(sed -n 's/.*initial password is: \([^[:space:]]\+\).*/\1/p' "$OPENLIST_LOG" | head -n 1)
            [ -n "$PASSWORD" ] && break
        fi
        sleep 1
        k=$((k + 1))
    done
    if [ -n "$PASSWORD" ]; then
        echo -e "${SUCCESS} 检测到 OpenList 初始账户信息："
        echo -e "    用户名：${C_BOLD_YELLOW}admin${C_RESET}"
        echo -e "    密码：  ${C_BOLD_YELLOW}$PASSWORD${C_RESET}"
    else
        echo -e "${INFO} 非首次启动未在日志中找到初始密码，请使用您设置的密码。"
    fi
    echo -e "${INFO} 请在系统浏览器访问：${C_BOLD_YELLOW}http://127.0.0.1:5244${C_RESET}"
    return 0
}

stop_openlist() {
    # 老进程兜底
    if pgrep -f "$OPENLIST_BIN server" >/dev/null 2>&1 && ! service_running openlist; then
        echo -e "${INFO} 终止遗留的 OpenList 进程..."
        force_kill "$OPENLIST_BIN server" "OpenList server" >/dev/null 2>&1 || true
    fi

    if ! [ -d "$SV_DIR/openlist" ]; then
        if check_openlist_process; then
            return 0
        fi
        echo -e "${WARN} OpenList server 未运行。"
        return 0
    fi

    echo -e "${INFO} 正在停止 OpenList server (sv down openlist)..."
    sv down openlist >/dev/null 2>&1 || true

    local i=0
    while [ "$i" -lt 6 ]; do
        if ! service_running openlist; then
            break
        fi
        sleep 1
        i=$((i + 1))
    done

    if service_running openlist; then
        echo -e "${WARN} OpenList 未响应，强制终止..."
        sv force-stop openlist >/dev/null 2>&1 || true
        sleep 1
    fi

    if service_running openlist; then
        echo -e "${ERROR} 无法停止 OpenList server。"
        return 1
    fi
    echo -e "${SUCCESS} OpenList server 已成功终止。"
    return 0
}

uninstall_openlist() {
    echo -e "${C_BOLD_RED}!!! 卸载将删除所有 OpenList 数据和配置，是否继续？(y/n):${C_RESET}"
    read -r confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        remove_service openlist
        pkill -f "$OPENLIST_BIN" 2>/dev/null || true
        disable_autostart_openlist >/dev/null 2>&1 || true
        rm -rf "$DEST_DIR"
        rm -f "$OPENLIST_BIN"
        echo -e "${SUCCESS} OpenList 已完成卸载。"
    else
        echo -e "${INFO} 已取消卸载。"
    fi
    wait_enter
}
