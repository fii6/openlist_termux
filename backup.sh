#!/data/data/com.termux/files/usr/bin/bash

# ========== 备份还原专用模块 ==========
# 负责备份和还原 OpenList 配置

source "${SCRIPT_DIR:-.}/common.sh"

# ========== 备份 OpenList ==========
backup_openlist() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│    备份 OpenList 配置    │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    echo ""

    local timestamp
    timestamp=$(date "+%Y%m%d_%H%M%S")
    local backup_file="$BACKUP_DIR/backup_${timestamp}.tar.gz"

    if [ ! -d "$DATA_DIR" ]; then
        echo -e "${ERROR} data 目录不存在，无法备份。"
        echo ""
        wait_enter
        return 1
    fi

    echo -e "${INFO} 正在备份 OpenList 配置..."
    echo -e "${INFO} 备份路径：${C_BOLD_YELLOW}$backup_file${C_RESET}"
    echo ""

    if tar -czf "$backup_file" -C "$DEST_DIR" data 2>/dev/null; then
        local file_size
        file_size=$(du -h "$backup_file" | cut -f1)
        echo -e "${SUCCESS} 备份成功！"
        echo -e "${INFO} 文件大小：${C_BOLD_YELLOW}$file_size${C_RESET}"
        echo -e "${INFO} 保存位置：${C_BOLD_YELLOW}$backup_file${C_RESET}"
    else
        echo -e "${ERROR} 备份失败，请检查磁盘空间或权限。"
        rm -f "$backup_file"
        echo ""
        wait_enter
        return 1
    fi

    echo ""
    wait_enter
    return 0
}

# ========== 还原 OpenList ==========
restore_openlist() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│    还原 OpenList 配置    │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    echo ""

    local backups=()
    mapfile -t backups < <(ls -1t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null)

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${WARN} 本地没有可用备份。"
        echo -e "${INFO} 备份目录：${C_BOLD_YELLOW}$BACKUP_DIR${C_RESET}"
        echo ""
        wait_enter
        return 1
    fi

    echo -e "${INFO} 找到 ${#backups[@]} 个本地备份"
    echo ""

    local i=1
    for f in "${backups[@]}"; do
        local file_size
        file_size=$(du -h "$f" | cut -f1)
        local file_time
        file_time=$(stat -c %y "$f" | cut -d' ' -f1,2)
        echo -e "  ${C_BOLD_YELLOW}$i.${C_RESET} $(basename "$f")"
        echo -e "     └─ ${file_size} | ${file_time}"
        ((i++))
    done

    echo ""
    echo -ne "${C_BOLD_CYAN}输入要还原的备份编号 (1-${#backups[@]})，或按 0 返回:${C_RESET} "
    read -r sel

    if [ "$sel" = "0" ]; then
        echo -e "${INFO} 已取消还原。"
        echo ""
        wait_enter
        return 0
    fi

    if [[ ! "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "${#backups[@]}" ]; then
        echo -e "${ERROR} 输入无效，请输入 0-${#backups[@]} 之间的编号。"
        echo ""
        wait_enter
        return 1
    fi

    local restore_file="${backups[$((sel-1))]}"
    local restore_name
    restore_name=$(basename "$restore_file")

    echo ""
    echo -e "${WARN} 还原将覆盖当前所有 OpenList 数据！"
    echo -e "${INFO} 选择备份：${C_BOLD_YELLOW}$restore_name${C_RESET}"
    echo ""
    echo -ne "${C_BOLD_RED}确定继续吗？(y/n):${C_RESET} "
    read -r confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${INFO} 已取消还原。"
        echo ""
        wait_enter
        return 1
    fi

    echo ""
    echo -e "${INFO} 正在还原备份..."

    local tmp_dir current_backup
    tmp_dir=$(mktemp -d) || {
        echo -e "${ERROR} 无法创建临时目录，终止还原。"
        wait_enter
        return 1
    }

    if ! tar -xzf "$restore_file" -C "$tmp_dir" 2>/dev/null || [ ! -d "$tmp_dir/data" ]; then
        rm -rf "$tmp_dir"
        echo -e "${ERROR} 还原失败！"
        echo -e "${ERROR} 请检查备份文件是否损坏。"
        echo ""
        wait_enter
        return 1
    fi

    current_backup=""
    if [ -d "$DATA_DIR" ]; then
        current_backup="$DEST_DIR/data.pre-restore.$(date +%Y%m%d_%H%M%S)"
        mv "$DATA_DIR" "$current_backup" || {
            rm -rf "$tmp_dir"
            echo -e "${ERROR} 无法备份当前 data 目录，终止还原。"
            wait_enter
            return 1
        }
    fi

    if mv "$tmp_dir/data" "$DATA_DIR"; then
        rm -rf "$tmp_dir"
        echo -e "${SUCCESS} 还原成功！"
        echo -e "${INFO} OpenList 配置已还原完成。"
        if [ -n "$current_backup" ]; then
            echo -e "${INFO} 旧数据已备份到：${C_BOLD_YELLOW}$current_backup${C_RESET}"
        fi
    else
        rm -rf "$DATA_DIR"
        if [ -n "$current_backup" ] && [ -d "$current_backup" ]; then
            mv "$current_backup" "$DATA_DIR"
        fi
        rm -rf "$tmp_dir"
        echo -e "${ERROR} 还原失败，已尽量恢复原数据。"
        echo ""
        wait_enter
        return 1
    fi

    echo ""
    wait_enter
    return 0
}

# ========== 清理还原残留 ==========
cleanup_pre_restore() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│  清理还原残留目录        │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    echo ""

    local dirs=()
    mapfile -t dirs < <(ls -1dt "$DEST_DIR"/data.pre-restore.* 2>/dev/null)

    if [ ${#dirs[@]} -eq 0 ]; then
        echo -e "${INFO} 没有发现还原残留目录。"
        echo ""
        wait_enter
        return 0
    fi

    echo -e "${INFO} 发现 ${C_BOLD_YELLOW}${#dirs[@]}${C_RESET} 个还原残留目录："
    echo ""

    local total_size=0
    for d in "${dirs[@]}"; do
        local dir_size
        dir_size=$(du -sh "$d" 2>/dev/null | cut -f1)
        local dir_time
        dir_time=$(stat -c %y "$d" 2>/dev/null | cut -d' ' -f1,2)
        echo -e "  ${C_BOLD_YELLOW}-${C_RESET} $(basename "$d")  (${dir_size}, ${dir_time})"
    done

    local total
    total=$(du -shc "${dirs[@]}" 2>/dev/null | tail -n1 | cut -f1)
    echo ""
    echo -e "${INFO} 总占用空间：${C_BOLD_YELLOW}${total}${C_RESET}"
    echo ""
    echo -ne "${C_BOLD_RED}确定删除全部还原残留目录？(y/n):${C_RESET} "
    read -r confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        for d in "${dirs[@]}"; do
            rm -rf "$d"
        done
        echo -e "${SUCCESS} 已清理全部还原残留目录。"
    else
        echo -e "${INFO} 已取消清理。"
    fi

    echo ""
    wait_enter
}

# ========== 备份还原菜单 ==========
backup_restore_menu() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│    备份/还原功能         │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    echo ""
    echo -e "${C_BOLD_GREEN}1. 备份 OpenList 配置${C_RESET}"
    echo -e "${C_BOLD_YELLOW}2. 还原 OpenList 配置${C_RESET}"
    echo -e "${C_BOLD_RED}3. 清理还原残留目录${C_RESET}"
    echo -e "${C_BOLD_GRAY}0. 返回${C_RESET}"
    echo ""
    echo -ne "${C_BOLD_CYAN}请选择操作 (0-3):${C_RESET} "
    read -r br_choice
    case $br_choice in
        1) backup_openlist ;;
        2) restore_openlist ;;
        3) cleanup_pre_restore ;;
        *) ;;
    esac
}
