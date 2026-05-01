#!/data/data/com.termux/files/usr/bin/bash

# ========== 公共定义 (common.sh) ==========
# 被 main.sh 和各模块脚本共享

# 防止重复加载
[ -n "${_COMMON_LOADED:-}" ] && return 0
_COMMON_LOADED=1

# ========== 颜色定义 ==========
C_BOLD_BLUE="\033[1;34m"
C_BOLD_GREEN="\033[1;32m"
C_BOLD_YELLOW="\033[1;33m"
C_BOLD_RED="\033[1;31m"
C_BOLD_CYAN="\033[1;36m"
C_BOLD_MAGENTA="\033[1;35m"
C_BOLD_GRAY="\033[1;30m"
C_BOLD_ORANGE="\033[38;5;208m"
C_BOLD_PINK="\033[38;5;213m"
C_BOLD_LIME="\033[38;5;118m"
C_RESET="\033[0m"

INFO="${C_BOLD_BLUE}[INFO]${C_RESET}"
ERROR="${C_BOLD_RED}[ERROR]${C_RESET}"
SUCCESS="${C_BOLD_GREEN}[OK]${C_RESET}"
WARN="${C_BOLD_YELLOW}[WARN]${C_RESET}"

# ========== 辅助函数 ==========
wait_enter() {
    echo -e "${C_BOLD_MAGENTA}按回车键返回菜单...${C_RESET}"
    read -r
}

rotate_log() {
    local log_file="$1"
    local max_size="${2:-5242880}"  # 默认 5MB
    if [ -f "$log_file" ]; then
        local size
        size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
        if [ "$size" -gt "$max_size" ]; then
            tail -c "$max_size" "$log_file" > "${log_file}.tmp"
            mv -f "${log_file}.tmp" "$log_file"
        fi
    fi
}

start_detached_process() {
    local log_file="$1"
    shift
    local pid

    mkdir -p "$(dirname "$log_file")"
    nohup "$@" > "$log_file" 2>&1 < /dev/null &
    pid=$!
    disown "$pid" 2>/dev/null || true
    printf '%s\n' "$pid"
}

start_detached_process_in_dir() {
    local work_dir="$1"
    local log_file="$2"
    shift 2
    local pid

    mkdir -p "$(dirname "$log_file")"
    (
        cd "$work_dir" || exit 1
        exec nohup "$@" > "$log_file" 2>&1 < /dev/null
    ) &
    pid=$!
    disown "$pid" 2>/dev/null || true
    printf '%s\n' "$pid"
}

force_kill() {
    local pattern="$1"
    local name="${2:-进程}"
    pkill -f "$pattern"
    sleep 1
    if pgrep -f "$pattern" >/dev/null 2>&1; then
        echo -e "${WARN} ${name}未响应 SIGTERM，正在强制终止..."
        pkill -9 -f "$pattern"
        sleep 1
        if pgrep -f "$pattern" >/dev/null 2>&1; then
            echo -e "${ERROR} 无法终止${name}进程。"
            return 1
        fi
    fi
    return 0
}

escape_json_value() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

# ========== runit / termux-services 集成 ==========
# 服务定义在 $SCRIPT_DIR/services/<name>/，安装到 $SV_DIR/<name>/
SV_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/service"
# 所有 sv 命令通过环境变量定位服务目录；不导出会回落到 /var/service。
export SVDIR="$SV_DIR"
SV_TEMPLATES_DIR_DEFAULT() { printf '%s\n' "${SCRIPT_DIR:-.}/services"; }
SERVICES_BOOT_FILE="$HOME/.termux/boot/openlist_termux_services"
SERVICE_DAEMON_PIDFILE="${PREFIX:-/data/data/com.termux/files/usr}/var/run/service-daemon.pid"
RUNSVDIR_BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin/runsvdir"

# 仍保留旧的 boot 脚本名，迁移时一并清理
LEGACY_BOOT_FILES=(
    "$HOME/.termux/boot/openlist_autostart.sh"
    "$HOME/.termux/boot/aria2_autostart.sh"
    "$HOME/.termux/boot/tunnel_autostart.sh"
)

# 找到当前系统上 termux-services 的入口脚本（不同版本命名不同）
find_services_profile() {
    local cand
    for cand in \
        "${PREFIX:-/data/data/com.termux/files/usr}/etc/profile.d/start-services.sh" \
        "${PREFIX:-/data/data/com.termux/files/usr}/etc/profile.d/start-services"; do
        if [ -f "$cand" ]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done
    return 1
}

# Termux 这版 procps 里 `pgrep -x runsvdir` 不匹配，改用 pidfile + cmdline 检测
runsvdir_running() {
    if [ -f "$SERVICE_DAEMON_PIDFILE" ]; then
        local pid
        pid=$(cat "$SERVICE_DAEMON_PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    pgrep -f "$RUNSVDIR_BIN " >/dev/null 2>&1
}

ensure_termux_services() {
    if command -v sv >/dev/null 2>&1 && find_services_profile >/dev/null; then
        return 0
    fi

    echo -e "${WARN} 未检测到 termux-services，正在尝试安装..."
    if ! command -v pkg >/dev/null 2>&1; then
        echo -e "${ERROR} 未检测到 pkg，无法自动安装 termux-services。"
        return 1
    fi
    if ! pkg install -y termux-services; then
        echo -e "${ERROR} 安装 termux-services 失败，请手动执行：${C_BOLD_YELLOW}pkg install termux-services${C_RESET}"
        return 1
    fi
    return 0
}

ensure_runsvdir_running() {
    if runsvdir_running; then
        return 0
    fi

    local profile
    profile=$(find_services_profile) || profile=""

    if [ -n "$profile" ]; then
        # shellcheck disable=SC1090
        . "$profile" >/dev/null 2>&1 || true
    fi

    # 等待 runsvdir 进入 ps（service-daemon 通过 start-stop-daemon 起进程，需要片刻）
    local i=0
    while [ "$i" -lt 5 ]; do
        if runsvdir_running; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done

    # profile 脚本失败兜底：直接 nohup 拉起 runsvdir
    if [ -x "$RUNSVDIR_BIN" ]; then
        mkdir -p "$SV_DIR"
        nohup "$RUNSVDIR_BIN" "$SV_DIR" >/dev/null 2>&1 < /dev/null &
        disown 2>/dev/null || true

        i=0
        while [ "$i" -lt 5 ]; do
            if runsvdir_running; then
                return 0
            fi
            sleep 1
            i=$((i + 1))
        done
    fi

    echo -e "${WARN} runsvdir 未启动，请重启 Termux 或手动执行：${C_BOLD_YELLOW}pkg install termux-services${C_RESET}"
    return 1
}

# install_service <name> [env_file]
# 把 services/<name>/ 拷贝到 $SV_DIR/<name>/，cloudflared 会替换 @@ENV_FILE@@
install_service() {
    local name="$1"
    local env_file="${2:-}"
    local src dst
    src="$(SV_TEMPLATES_DIR_DEFAULT)/$name"
    dst="$SV_DIR/$name"

    if [ ! -d "$src" ]; then
        echo -e "${ERROR} 找不到服务模板：${C_BOLD_YELLOW}$src${C_RESET}"
        return 1
    fi

    mkdir -p "$dst/log" || return 1

    cp -f "$src/run" "$dst/run"
    cp -f "$src/log/run" "$dst/log/run"

    if [ -n "$env_file" ] && grep -q '@@ENV_FILE@@' "$dst/run"; then
        local escaped
        escaped=$(printf '%s' "$env_file" | sed 's/[\\/&|]/\\&/g')
        sed -i "s|@@ENV_FILE@@|$escaped|g" "$dst/run"
    fi

    chmod +x "$dst/run" "$dst/log/run"
    return 0
}

# 服务是否处于"运行中"状态
service_running() {
    local name="$1"
    [ -d "$SV_DIR/$name" ] || return 1
    command -v sv >/dev/null 2>&1 || return 1
    sv status "$name" 2>/dev/null | grep -q '^run:'
}

# 该服务是否设置为自启（即 runsvdir 启动后会拉起）
service_autostart_enabled() {
    local name="$1"
    [ -d "$SV_DIR/$name" ] || return 1
    [ ! -f "$SV_DIR/$name/down" ]
}

# 启用自启（移除 down 文件）
service_enable_autostart() {
    local name="$1"
    [ -d "$SV_DIR/$name" ] || return 1
    rm -f "$SV_DIR/$name/down"
    return 0
}

# 关闭自启（创建 down 文件，下次 runsvdir 启动时不会拉起；当前进程仍在运行）
service_disable_autostart() {
    local name="$1"
    [ -d "$SV_DIR/$name" ] || return 0
    : > "$SV_DIR/$name/down"
    return 0
}

# 删除整个服务定义
remove_service() {
    local name="$1"
    [ -d "$SV_DIR/$name" ] || return 0
    if command -v sv >/dev/null 2>&1; then
        sv force-stop "$name" >/dev/null 2>&1 || true
    fi
    rm -rf "$SV_DIR/$name"
    return 0
}

# 写入统一的开机自启脚本（启动 runsvdir + 拿 wake-lock）
write_services_boot_file() {
    mkdir -p "$HOME/.termux/boot"
    cat > "$SERVICES_BOOT_FILE" <<'BOOT_EOF'
#!/data/data/com.termux/files/usr/bin/sh
# openlist_termux: 启动 runit 监督 + 申请 wake-lock
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
for cand in \
    "$PREFIX/etc/profile.d/start-services.sh" \
    "$PREFIX/etc/profile.d/start-services"; do
    if [ -f "$cand" ]; then
        . "$cand"
        break
    fi
done
BOOT_EOF
    chmod +x "$SERVICES_BOOT_FILE"
}

remove_services_boot_file() {
    [ -f "$SERVICES_BOOT_FILE" ] && rm -f "$SERVICES_BOOT_FILE"
    return 0
}

# 清理旧版（基于 nohup 的）开机自启脚本
clean_legacy_boot_files() {
    local f
    for f in "${LEGACY_BOOT_FILES[@]}"; do
        [ -f "$f" ] && rm -f "$f"
    done
    return 0
}
