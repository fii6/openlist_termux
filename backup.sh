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

        # 自动清理旧的还原残留目录（保留本次生成的）
        local old_dirs=()
        mapfile -t old_dirs < <(ls -1dt "$DEST_DIR"/data.pre-restore.* 2>/dev/null)
        for d in "${old_dirs[@]}"; do
            [ "$d" = "$current_backup" ] && continue
            rm -rf "$d"
        done
        if [ ${#old_dirs[@]} -gt 1 ]; then
            echo -e "${INFO} 已自动清理 $((${#old_dirs[@]} - 1)) 个旧的还原残留目录。"
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

# ========== 备份还原菜单 ==========
backup_restore_menu() {
    echo -e "${C_BOLD_BLUE}┌──────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD_BLUE}│    备份/还原功能         │${C_RESET}"
    echo -e "${C_BOLD_BLUE}└──────────────────────────┘${C_RESET}"
    echo ""
    echo -e "${C_BOLD_GREEN}1. 备份 OpenList 配置${C_RESET}"
    echo -e "${C_BOLD_YELLOW}2. 还原 OpenList 配置${C_RESET}"
    echo -e "${C_BOLD_GRAY}0. 返回${C_RESET}"
    echo ""
    echo -ne "${C_BOLD_CYAN}请选择操作 (0-2):${C_RESET} "
    read -r br_choice
    case $br_choice in
        1) backup_openlist ;;
        2) restore_openlist ;;
        *) ;;
    esac
}
