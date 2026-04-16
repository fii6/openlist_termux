#!/data/data/com.termux/files/usr/bin/bash

# ========== aria2 专用模块 ==========
# 负责 aria2 的配置、启动、更新等相关操作
# 说明：配置思路参考 P3TERX/aria2.conf，并按 Android Termux 环境做了裁剪与适配

source "${SCRIPT_DIR:-.}/common.sh"

# 上游参考
P3TERX_DHT_DAT_URLS=(
    "https://raw.githubusercontent.com/P3TERX/aria2.conf/master/dht.dat"
    "https://raw.githubusercontent.com/giturass/aria2.conf/refs/heads/master/dht.dat"
)
P3TERX_DHT6_DAT_URLS=(
    "https://raw.githubusercontent.com/P3TERX/aria2.conf/master/dht6.dat"
    "https://raw.githubusercontent.com/giturass/aria2.conf/refs/heads/master/dht6.dat"
)
TRACKER_URLS=(
    "https://trackerslist.com/all_aria2.txt"
    "https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt"
    "https://trackers.p3terx.com/all_aria2.txt"
)

get_aria2_secret() {
    if [ -z "$ARIA2_SECRET" ]; then
        echo -e "${ERROR} .env 中未设置 ARIA2_SECRET"
        return 1
    fi
}

ensure_download_tool() {
    if command -v curl >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${WARN} 未检测到 curl，正在尝试安装..."
    if command -v pkg >/dev/null 2>&1; then
        pkg install -y curl || {
            echo -e "${ERROR} 安装 curl 失败，请检查包管理器或网络。"
            return 1
        }
    else
        echo -e "${ERROR} 未检测到 curl，且无法自动安装。"
        return 1
    fi
}

ensure_aria2() {
    if command -v aria2c >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${WARN} 未检测到 aria2，正在尝试安装..."
    if command -v pkg >/dev/null 2>&1; then
        pkg install -y aria2 || {
            echo -e "${ERROR} 安装 aria2 失败，请检查包管理器或网络。"
            return 1
        }
    else
        echo -e "${ERROR} 无法自动安装 aria2，请手动安装后重试。"
        return 1
    fi
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\\/&|]/\\&/g'
}

get_default_download_dir() {
    if [ -d "/sdcard/Download" ] && [ -w "/sdcard/Download" ]; then
        echo "/sdcard/Download"
        return 0
    fi

    if [ -d "$HOME/storage/downloads" ] && [ -w "$HOME/storage/downloads" ]; then
        echo "$HOME/storage/downloads"
        return 0
    fi

    mkdir -p "$HOME/Downloads"
    echo "$HOME/Downloads"
}

fetch_with_fallbacks() {
    local output="$1"
    shift
    local tmp_file="${output}.tmp"

    rm -f "$tmp_file"
    for url in "$@"; do
        if curl -fsSL --connect-timeout 10 --retry 2 "$url" -o "$tmp_file" && [ -s "$tmp_file" ]; then
            mv -f "$tmp_file" "$output"
            return 0
        fi
    done

    rm -f "$tmp_file"
    return 1
}

write_termux_aria2_conf() {
    local download_dir="$1"

    cat > "$ARIA2_CONF" <<EOF
# openlist_termux Termux aria2 config
# Based on: https://github.com/P3TERX/aria2.conf
# Tuned for Android Termux: lower resource usage, local RPC by default,
# and no GNU/Linux-only hook scripts.

## 文件保存设置 ##
dir=$download_dir

disk-cache=32M
file-allocation=none
continue=true
always-resume=false
max-resume-failure-tries=0
remote-time=true

## 进度保存设置 ##
input-file=$ARIA2_DIR/aria2.session
save-session=$ARIA2_DIR/aria2.session
save-session-interval=10
auto-save-interval=20
force-save=false

## 下载连接设置 ##
max-file-not-found=5
max-tries=10
retry-wait=5
connect-timeout=10
timeout=30
max-concurrent-downloads=5
max-connection-per-server=8
split=16
min-split-size=10M
piece-length=1M
allow-piece-length-change=true
lowest-speed-limit=0
max-overall-download-limit=0
max-download-limit=0
disable-ipv6=true
http-accept-gzip=true
reuse-uri=false
no-netrc=true
allow-overwrite=false
auto-file-renaming=true
content-disposition-default-utf8=true

## BT/PT 下载设置 ##
listen-port=51413
dht-listen-port=51413
enable-dht=true
enable-dht6=false
dht-file-path=$ARIA2_DIR/dht.dat
dht-file-path6=$ARIA2_DIR/dht6.dat
dht-entry-point=dht.transmissionbt.com:6881
dht-entry-point6=dht.transmissionbt.com:6881
bt-enable-lpd=false
enable-peer-exchange=true
bt-max-peers=64
bt-request-peer-speed-limit=5M
max-overall-upload-limit=1M
max-upload-limit=0
seed-ratio=1.0
seed-time=0
bt-hash-check-seed=true
bt-seed-unverified=false
bt-tracker-connect-timeout=10
bt-tracker-timeout=10
bt-prioritize-piece=head=16M,tail=16M
rpc-save-upload-metadata=true
follow-torrent=true
pause-metadata=false
bt-save-metadata=true
bt-load-saved-metadata=true
bt-remove-unselected-file=true
bt-force-encryption=true
bt-detach-seed-only=true

## 客户端伪装 ##
user-agent=Mozilla/5.0 (Linux; Android 13; Termux) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36
peer-agent=Deluge 1.3.15
peer-id-prefix=-DE13F0-

## RPC 设置 ##
enable-rpc=true
rpc-allow-origin-all=true
rpc-listen-all=false
rpc-listen-port=6800
rpc-secret=$ARIA2_SECRET
rpc-max-request-size=10M

## 日志设置 ##
log=$ARIA2_LOG
log-level=notice
console-log-level=notice
quiet=false
summary-interval=0
show-console-readout=false

## BitTorrent trackers ##
bt-tracker=
EOF

    chmod 600 "$ARIA2_CONF"
}

patch_existing_aria2_conf() {
    local download_dir="$1"
    local escaped_secret escaped_session escaped_dht escaped_dht6 escaped_log escaped_dir

    escaped_secret=$(escape_sed_replacement "$ARIA2_SECRET")
    escaped_session=$(escape_sed_replacement "$ARIA2_DIR/aria2.session")
    escaped_dht=$(escape_sed_replacement "$ARIA2_DIR/dht.dat")
    escaped_dht6=$(escape_sed_replacement "$ARIA2_DIR/dht6.dat")
    escaped_log=$(escape_sed_replacement "$ARIA2_LOG")
    escaped_dir=$(escape_sed_replacement "$download_dir")

    if grep -q '^rpc-secret=' "$ARIA2_CONF"; then
        sed -i "s|^rpc-secret=.*|rpc-secret=${escaped_secret}|" "$ARIA2_CONF"
    else
        printf '\nrpc-secret=%s\n' "$ARIA2_SECRET" >> "$ARIA2_CONF"
    fi

    if grep -q '^input-file=' "$ARIA2_CONF"; then
        sed -i "s|^input-file=.*|input-file=${escaped_session}|" "$ARIA2_CONF"
    else
        printf 'input-file=%s\n' "$ARIA2_DIR/aria2.session" >> "$ARIA2_CONF"
    fi

    if grep -q '^save-session=' "$ARIA2_CONF"; then
        sed -i "s|^save-session=.*|save-session=${escaped_session}|" "$ARIA2_CONF"
    else
        printf 'save-session=%s\n' "$ARIA2_DIR/aria2.session" >> "$ARIA2_CONF"
    fi

    if grep -q '^dht-file-path=' "$ARIA2_CONF"; then
        sed -i "s|^dht-file-path=.*|dht-file-path=${escaped_dht}|" "$ARIA2_CONF"
    else
        printf 'dht-file-path=%s\n' "$ARIA2_DIR/dht.dat" >> "$ARIA2_CONF"
    fi

    if grep -q '^dht-file-path6=' "$ARIA2_CONF"; then
        sed -i "s|^dht-file-path6=.*|dht-file-path6=${escaped_dht6}|" "$ARIA2_CONF"
    else
        printf 'dht-file-path6=%s\n' "$ARIA2_DIR/dht6.dat" >> "$ARIA2_CONF"
    fi

    if grep -q '^log=' "$ARIA2_CONF"; then
        sed -i "s|^log=.*|log=${escaped_log}|" "$ARIA2_CONF"
    else
        printf 'log=%s\n' "$ARIA2_LOG" >> "$ARIA2_CONF"
    fi

    if grep -q '^dir=/root/Download$' "$ARIA2_CONF"; then
        sed -i "s|^dir=.*|dir=${escaped_dir}|" "$ARIA2_CONF"
    fi

    sed -i '/^on-download-stop=/d;/^on-download-complete=/d;/^on-download-error=/d' "$ARIA2_CONF"
}

ensure_aria2_files() {
    local download_dir backup_conf

    get_aria2_secret || return 1
    ensure_download_tool || return 1

    mkdir -p "$ARIA2_DIR"
    touch "$ARIA2_DIR/aria2.session"
    chmod 600 "$ARIA2_DIR/aria2.session"

    if [ ! -s "$ARIA2_DIR/dht.dat" ]; then
        echo -e "${INFO} 正在下载 dht.dat ..."
        fetch_with_fallbacks "$ARIA2_DIR/dht.dat" "${P3TERX_DHT_DAT_URLS[@]}" || {
            echo -e "${WARN} dht.dat 下载失败，稍后仍可继续使用 aria2。"
        }
    fi

    if [ ! -s "$ARIA2_DIR/dht6.dat" ]; then
        echo -e "${INFO} 正在下载 dht6.dat ..."
        fetch_with_fallbacks "$ARIA2_DIR/dht6.dat" "${P3TERX_DHT6_DAT_URLS[@]}" || {
            echo -e "${WARN} dht6.dat 下载失败，稍后仍可继续使用 aria2。"
        }
    fi

    download_dir=$(get_default_download_dir)

    if [ ! -f "$ARIA2_CONF" ]; then
        echo -e "${INFO} 正在生成 Termux 版 aria2 配置文件..."
        write_termux_aria2_conf "$download_dir"
        return 0
    fi

    if grep -q '^# openlist_termux Termux aria2 config$' "$ARIA2_CONF"; then
        patch_existing_aria2_conf "$download_dir"
        return 0
    fi

    if grep -q '^input-file=/root/' "$ARIA2_CONF" || grep -q '^on-download-stop=/root/.aria2/' "$ARIA2_CONF" || grep -q '^on-download-complete=/root/.aria2/' "$ARIA2_CONF"; then
        backup_conf="$ARIA2_CONF.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$ARIA2_CONF" "$backup_conf"
        echo -e "${WARN} 检测到旧版/非 Termux 友好的 aria2 配置，已备份到：${C_BOLD_YELLOW}$backup_conf${C_RESET}"
        write_termux_aria2_conf "$download_dir"
        return 0
    fi

    patch_existing_aria2_conf "$download_dir"
}

create_aria2_conf() {
    ensure_aria2_files
}

edit_aria2_config() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│ 编辑 aria2 配置文件      │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"

    ensure_aria2_files || return 1

    echo -e "${INFO} 正在编辑 aria2 配置文件：${C_BOLD_YELLOW}$ARIA2_CONF${C_RESET}"
    vi "$ARIA2_CONF"
    echo -e "${SUCCESS} aria2 配置文件编辑完成。"
    wait_enter
}

view_aria2_log() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│ 查看 aria2 日志          │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    if [ -f "$ARIA2_LOG" ]; then
        echo -e "${INFO} 显示 aria2 日志文件：${C_BOLD_YELLOW}$ARIA2_LOG${C_RESET}"
        tail -n 200 "$ARIA2_LOG"
    else
        echo -e "${ERROR} 未找到 aria2 日志文件：${C_BOLD_YELLOW}$ARIA2_LOG${C_RESET}"
    fi
    wait_enter
}

fetch_trackers() {
    local trackers_raw=""
    local url

    for url in "${TRACKER_URLS[@]}"; do
        trackers_raw=$(curl -fsSL --connect-timeout 8 --max-time 20 --retry 2 "$url" 2>/dev/null | tr -d '\r')
        if [ -n "$trackers_raw" ]; then
            break
        fi
    done

    if [ -z "$trackers_raw" ]; then
        return 1
    fi

    printf '%s\n' "$trackers_raw" | tr ',' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ',' | sed 's/,$//'
}

apply_trackers_via_rpc() {
    local trackers="$1"
    local rpc_port rpc_secret payload

    rpc_port=$(grep '^rpc-listen-port=' "$ARIA2_CONF" | cut -d= -f2-)
    rpc_secret=$(grep '^rpc-secret=' "$ARIA2_CONF" | cut -d= -f2-)

    [ -n "$rpc_port" ] || return 1

    local escaped_secret escaped_trackers
    escaped_secret=$(escape_json_value "${rpc_secret:-}")
    escaped_trackers=$(escape_json_value "$trackers")

    if [ -n "$rpc_secret" ]; then
        payload="{\"jsonrpc\":\"2.0\",\"method\":\"aria2.changeGlobalOption\",\"id\":\"openlist_termux\",\"params\":[\"token:${escaped_secret}\",{\"bt-tracker\":\"${escaped_trackers}\"}]}"
    else
        payload="{\"jsonrpc\":\"2.0\",\"method\":\"aria2.changeGlobalOption\",\"id\":\"openlist_termux\",\"params\":[{\"bt-tracker\":\"${escaped_trackers}\"}]}"
    fi

    curl -fsS -H 'Content-Type: application/json' -d "$payload" "http://127.0.0.1:${rpc_port}/jsonrpc" >/dev/null 2>&1
}

update_bt_tracker() {
    local trackers

    ensure_download_tool || return 1
    ensure_aria2_files || return 1

    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│ 更新 BT Tracker          │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    echo -e "${INFO} 正在获取最新 BT Tracker 列表..."

    trackers=$(fetch_trackers)
    if [ -z "$trackers" ]; then
        echo -e "${ERROR} 获取 BT Tracker 失败，请检查网络后重试。"
        wait_enter
        return 1
    fi

    if grep -q '^bt-tracker=' "$ARIA2_CONF"; then
        sed -i "s|^bt-tracker=.*|bt-tracker=${trackers}|" "$ARIA2_CONF"
    else
        printf '\nbt-tracker=%s\n' "$trackers" >> "$ARIA2_CONF"
    fi

    if check_aria2_process && apply_trackers_via_rpc "$trackers"; then
        echo -e "${SUCCESS} BT Tracker 已更新，并已同步到正在运行的 aria2。"
    else
        echo -e "${SUCCESS} BT Tracker 已写入配置文件。"
        echo -e "${INFO} 若 aria2 正在运行但未同步成功，可重启 aria2 生效。"
    fi

    wait_enter
}

check_aria2_process() {
    pgrep -f "$ARIA2_CMD --conf-path=$ARIA2_CONF" >/dev/null 2>&1
}

enable_autostart_aria2() {
    mkdir -p "$HOME/.termux/boot"
    local boot_file="$HOME/.termux/boot/aria2_autostart.sh"
    cat > "$boot_file" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
mkdir -p "$(dirname "$ARIA2_LOG")"
ARIA2_CMD="$ARIA2_CMD"
ARIA2_CONF="$ARIA2_CONF"
nohup "\$ARIA2_CMD" --conf-path="\$ARIA2_CONF" > "$ARIA2_LOG" 2>&1 < /dev/null &
EOF
    chmod +x "$boot_file"
    echo -e "${SUCCESS} aria2 已成功设置开机自启"
}

disable_autostart_aria2() {
    local boot_file="$HOME/.termux/boot/aria2_autostart.sh"
    if [ -f "$boot_file" ]; then
        rm -f "$boot_file"
        echo -e "${INFO} 已禁用 aria2 开机自启"
    fi
}

start_aria2() {
    ensure_aria2 || return 1
    ensure_aria2_files || return 1

    if check_aria2_process; then
        PIDS=$(pgrep -f "$ARIA2_CMD --conf-path=$ARIA2_CONF")
        echo -e "${WARN} aria2 已运行，PID：${C_BOLD_YELLOW}$PIDS${C_RESET}"
        return 0
    fi

    mkdir -p "$ARIA2_DIR"
    rotate_log "$ARIA2_LOG"
    echo -e "${INFO} 启动 aria2 ..."
    ARIA2_PID=$(start_detached_process "$ARIA2_LOG" "$ARIA2_CMD" --conf-path="$ARIA2_CONF")
    sleep 2

    if [ -n "$ARIA2_PID" ] && ps -p "$ARIA2_PID" >/dev/null 2>&1; then
        echo -e "${SUCCESS} aria2 已启动 (PID: ${C_BOLD_YELLOW}$ARIA2_PID${C_RESET})."
        echo -e "${INFO} 配置文件：${C_BOLD_YELLOW}$ARIA2_CONF${C_RESET}"
        echo -e "${INFO} 下载目录：${C_BOLD_YELLOW}$(get_default_download_dir)${C_RESET}"
        echo -e "${INFO} RPC 端口：${C_BOLD_YELLOW}6800${C_RESET}（密钥已从 .env 注入）"
    else
        echo -e "${ERROR} aria2 启动失败。"
        [ -f "$ARIA2_LOG" ] && tail -n 50 "$ARIA2_LOG"
        return 1
    fi
    return 0
}

stop_aria2() {
    if check_aria2_process; then
        PIDS=$(pgrep -f "$ARIA2_CMD --conf-path=$ARIA2_CONF")
        echo -e "${INFO} 检测到 aria2 正在运行，PID：${C_BOLD_YELLOW}$PIDS${C_RESET}"
        echo -e "${INFO} 正在终止 aria2 ..."
        if force_kill "$ARIA2_CMD --conf-path=$ARIA2_CONF" "aria2"; then
            echo -e "${SUCCESS} aria2 已成功终止。"
        fi
    else
        echo -e "${WARN} aria2 未运行。"
    fi
    return 0
}

uninstall_aria2() {
    echo -e "${C_BOLD_RED}!!! 卸载将删除所有 aria2 数据和配置，是否继续？(y/n):${C_RESET}"
    read -r confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        pkill -f "$ARIA2_CMD" 2>/dev/null || true
        if command -v pkg >/dev/null 2>&1; then
            pkg uninstall -y aria2 && apt autoremove -y
        fi
        rm -rf "$ARIA2_DIR"
        echo -e "${SUCCESS} aria2 已完成卸载。"
    else
        echo -e "${INFO} 已取消卸载。"
    fi
    wait_enter
}
