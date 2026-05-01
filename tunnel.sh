#!/data/data/com.termux/files/usr/bin/bash

# ========== Cloudflare Tunnel 专用模块 ==========
# 负责 Cloudflare Tunnel 的配置、启动、停止等相关操作（runit 接管启停）

source "${SCRIPT_DIR:-.}/common.sh"

get_tunnel_info() {
    if [ -z "$TUNNEL_NAME" ] || [ -z "$DOMAIN" ] || [ -z "$LOCAL_PORT" ]; then
        echo -e "${ERROR} .env 中 Cloudflare 隧道配置不完整（需要 TUNNEL_NAME, DOMAIN, LOCAL_PORT）"
        return 1
    fi

    if ! printf '%s' "$LOCAL_PORT" | grep -Eq '^[0-9]+$'; then
        echo -e "${ERROR} LOCAL_PORT 配置无效：${C_BOLD_YELLOW}$LOCAL_PORT${C_RESET}"
        return 1
    fi

    mkdir -p "$CONFIG_DIR"
    return 0
}

ensure_cloudflared() {
    if command -v cloudflared >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${INFO} cloudflared 未安装，正在安装..."
    if command -v pkg >/dev/null 2>&1; then
        pkg install -y cloudflared || {
            echo -e "${ERROR} 安装 cloudflared 失败，请检查包管理器或网络"
            return 1
        }
    else
        echo -e "${ERROR} 未检测到 pkg，无法自动安装 cloudflared"
        return 1
    fi
}

get_tunnel_uuid() {
    cloudflared tunnel list 2>/dev/null | awk -v name="$TUNNEL_NAME" '$2==name {print $1; exit}'
}

write_cf_config() {
    local uuid="$1"
    local cred_file="$2"
    cat > "$CF_CONFIG" <<EOF
url: http://127.0.0.1:$LOCAL_PORT
tunnel: $uuid
credentials-file: $cred_file
EOF
}

tunnel_log_has_connection() {
    local svlog="$HOME/.cloudflared/log/sv/current"
    if [ -f "$svlog" ] && grep -q "Registered tunnel connection" "$svlog"; then
        return 0
    fi
    [ -f "$CF_LOG" ] && grep -q "Registered tunnel connection" "$CF_LOG"
}

tunnel_log_has_edge_error() {
    local svlog="$HOME/.cloudflared/log/sv/current"
    local pat="TLS handshake with edge error|Unable to establish connection with Cloudflare edge|Serve tunnel error"
    if [ -f "$svlog" ] && grep -Eq "$pat" "$svlog"; then
        return 0
    fi
    [ -f "$CF_LOG" ] && grep -Eq "$pat" "$CF_LOG"
}

wait_for_tunnel_connection() {
    local timeout="${1:-12}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        if tunnel_log_has_connection; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

migrate_legacy_tunnel() {
    if pgrep -f "cloudflared.*${TUNNEL_NAME:-__none__}" >/dev/null 2>&1 && ! service_running cloudflared; then
        echo -e "${INFO} 检测到遗留的 cloudflared nohup 进程，正在迁移到 runit 监督..."
        force_kill "cloudflared.*$TUNNEL_NAME" "Cloudflare Tunnel" >/dev/null 2>&1 || true
    fi
}

ensure_tunnel_service() {
    ensure_termux_services || return 1
    install_service cloudflared "${ENV_FILE:-$HOME/.env}" || return 1
    ensure_runsvdir_running || return 1
    return 0
}

setup_cloudflare_tunnel() {
    local uuid cred_file

    get_tunnel_info || return 1
    ensure_cloudflared || return 1

    pushd "$CONFIG_DIR" >/dev/null || {
        echo -e "${ERROR} 无法切换到 $CONFIG_DIR"
        return 1
    }

    if [ ! -f "cert.pem" ]; then
        echo -e "${INFO} 请在弹出的浏览器页面登录 Cloudflare 账号进行授权"
        echo -e "${INFO} 如果 Termux 未打开浏览器，请手动复制 URL 到浏览器"
        cloudflared tunnel login || {
            echo -e "${ERROR} Cloudflare 授权失败，请检查网络或稍后重试"
            popd >/dev/null || true
            return 1
        }
        if [ ! -f "cert.pem" ]; then
            echo -e "${ERROR} 授权后仍未生成 cert.pem 文件，请检查 Cloudflare 账户权限或重新运行 'cloudflared tunnel login'"
            popd >/dev/null || true
            return 1
        fi
    fi

    if ! cloudflared tunnel list 2>/dev/null | awk '{print $2}' | grep -Fx "$TUNNEL_NAME" >/dev/null; then
        echo -e "${INFO} 创建隧道: $TUNNEL_NAME"
        cloudflared tunnel create "$TUNNEL_NAME" || {
            echo -e "${ERROR} 隧道创建失败，请检查 Cloudflare 配置或网络"
            popd >/dev/null || true
            return 1
        }
    fi

    uuid=$(get_tunnel_uuid)
    if [ -z "$uuid" ]; then
        echo -e "${ERROR} 未能获取隧道 UUID，检查隧道是否创建成功"
        popd >/dev/null || true
        return 1
    fi

    cred_file="$CONFIG_DIR/${uuid}.json"
    if [ ! -f "$cred_file" ]; then
        echo -e "${ERROR} 隧道凭证文件 $cred_file 不存在，请尝试重新创建隧道或检查权限"
        echo -e "${INFO} 可尝试运行：cloudflared tunnel delete -f $TUNNEL_NAME && cloudflared tunnel create $TUNNEL_NAME"
        popd >/dev/null || true
        return 1
    fi

    if [ -f "$CF_CONFIG" ] && \
       grep -q "^tunnel: $uuid$" "$CF_CONFIG" && \
       grep -q "^credentials-file: $cred_file$" "$CF_CONFIG" && \
       grep -q "^url: http://127.0.0.1:$LOCAL_PORT$" "$CF_CONFIG"; then
        echo -e "${INFO} 检测到有效的现有配置文件: $CF_CONFIG，将直接使用"
    else
        write_cf_config "$uuid" "$cred_file"
        echo -e "${SUCCESS} 配置文件已生成/更新: $CF_CONFIG"
    fi

    echo -e "${INFO} 配置 DNS 路由: $DOMAIN"
    cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" >/dev/null 2>&1 || {
        echo -e "${ERROR} DNS 路由配置失败，请检查 Cloudflare 账户权限或域名配置"
        popd >/dev/null || true
        return 1
    }

    popd >/dev/null || true

    migrate_legacy_tunnel
    ensure_tunnel_service || return 1

    # 隧道每次配置后强制重启，确保新的 .env 路径与配置生效
    if service_running cloudflared; then
        echo -e "${INFO} cloudflared 服务已在运行，重启以应用新配置..."
        sv restart cloudflared >/dev/null 2>&1 || true
    else
        echo -e "${INFO} 正在启动 Cloudflare Tunnel (sv up cloudflared)..."
        sv up cloudflared >/dev/null 2>&1 || true
    fi

    # 等待进程启动 + Edge 连接建立
    local i=0
    while [ "$i" -lt 6 ]; do
        if service_running cloudflared; then
            break
        fi
        sleep 1
        i=$((i + 1))
    done

    if ! service_running cloudflared; then
        echo -e "${ERROR} 隧道启动失败，请检查日志或确保 $cred_file 有效。"
        sv status cloudflared 2>/dev/null || true
        local svlog="$HOME/.cloudflared/log/sv/current"
        [ -f "$svlog" ] && tail -n 50 "$svlog"
        return 1
    fi

    if wait_for_tunnel_connection 12; then
        echo -e "${SUCCESS} 隧道已启动 (runit 监督)"
        echo -e "${INFO} 日志目录：${C_BOLD_YELLOW}$HOME/.cloudflared/log/sv/${C_RESET}"
        echo -e "${INFO} 访问地址: https://$DOMAIN"
    else
        echo -e "${ERROR} Cloudflare Tunnel 进程已启动，但未与 Cloudflare Edge 建立连接。"
        if tunnel_log_has_edge_error; then
            echo -e "${INFO} 日志显示 Edge TLS 握手失败，请优先检查网络环境，避免强制使用固定传输协议。"
        fi
        local svlog="$HOME/.cloudflared/log/sv/current"
        [ -f "$svlog" ] && tail -n 50 "$svlog"
        return 1
    fi

    wait_enter
    return 0
}

stop_cloudflare_tunnel() {
    get_tunnel_info || return 1

    # 老 nohup 进程兜底
    if pgrep -f "cloudflared.*$TUNNEL_NAME" >/dev/null 2>&1 && ! service_running cloudflared; then
        echo -e "${INFO} 终止遗留的 cloudflared 进程..."
        force_kill "cloudflared.*$TUNNEL_NAME" "Cloudflare Tunnel" >/dev/null 2>&1 || true
    fi

    if ! [ -d "$SV_DIR/cloudflared" ]; then
        if pgrep -f "cloudflared" >/dev/null 2>&1; then
            return 0
        fi
        echo -e "${WARN} Cloudflare Tunnel 未运行。"
        wait_enter
        return 0
    fi

    echo -e "${INFO} 正在停止 Cloudflare Tunnel (sv down cloudflared)..."
    sv down cloudflared >/dev/null 2>&1 || true

    local i=0
    while [ "$i" -lt 6 ]; do
        if ! service_running cloudflared; then
            break
        fi
        sleep 1
        i=$((i + 1))
    done

    if service_running cloudflared; then
        echo -e "${WARN} cloudflared 未响应，强制终止..."
        sv force-stop cloudflared >/dev/null 2>&1 || true
        sleep 1
    fi

    if service_running cloudflared; then
        echo -e "${ERROR} 无法停止 Cloudflare Tunnel。"
    else
        echo -e "${SUCCESS} Cloudflare Tunnel 已成功终止。"
    fi
    wait_enter
    return 0
}

view_tunnel_log() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│ 查看 Cloudflare Tunnel 日志 │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    local svlog="$HOME/.cloudflared/log/sv/current"
    if [ -f "$svlog" ]; then
        echo -e "${INFO} 显示 svlogd 当前日志：${C_BOLD_YELLOW}$svlog${C_RESET}"
        tail -n 200 "$svlog"
    elif [ -f "$CF_LOG" ]; then
        echo -e "${INFO} 显示 Cloudflare Tunnel 日志文件：${C_BOLD_YELLOW}$CF_LOG${C_RESET}"
        tail -n 200 "$CF_LOG"
    else
        echo -e "${ERROR} 未找到 Cloudflare Tunnel 日志（svlogd 或 $CF_LOG）"
    fi
    wait_enter
}

enable_autostart_tunnel() {
    ensure_tunnel_service || return 1
    write_services_boot_file
    clean_legacy_boot_files
    service_enable_autostart cloudflared
    echo -e "${SUCCESS} Cloudflare Tunnel 已成功设置开机自启（runit 监督）"
}

disable_autostart_tunnel() {
    if [ -d "$SV_DIR/cloudflared" ]; then
        service_disable_autostart cloudflared
        echo -e "${INFO} 已禁用 Cloudflare Tunnel 开机自启（保留服务定义）"
    fi
    rm -f "$HOME/.termux/boot/tunnel_autostart.sh"
}

uninstall_tunnel() {
    echo -e "${C_BOLD_RED}!!! 卸载将删除所有 Cloudflare Tunnel 配置和凭证，是否继续？(y/n):${C_RESET}"
    read -r confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        remove_service cloudflared
        pkill -f "cloudflared" 2>/dev/null || true
        disable_autostart_tunnel >/dev/null 2>&1 || true
        if command -v pkg >/dev/null 2>&1; then
            pkg uninstall -y cloudflared && apt autoremove -y
        fi
        rm -rf "$CONFIG_DIR"
        echo -e "${SUCCESS} Cloudflare Tunnel 已完成卸载。"
    else
        echo -e "${INFO} 已取消卸载。"
    fi
    wait_enter
}
