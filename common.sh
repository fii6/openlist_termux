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
