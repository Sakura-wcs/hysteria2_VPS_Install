#!/usr/bin/env bash

set -uo pipefail

MANAGER_UPDATE_RAW_URL="${MANAGER_UPDATE_RAW_URL:-https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install/main}"
MANAGER_UPDATE_INSTALL_DIR="${MANAGER_UPDATE_INSTALL_DIR:-/opt/s-hy2}"
MANAGER_UPDATE_BIN_DIR="${MANAGER_UPDATE_BIN_DIR:-/usr/local/bin}"

manager_update_files() {
    cat <<'EOF'
hy2-manager.sh
install.sh
quick-install.sh
scripts/certificate-sync.sh
scripts/config-loader.sh
scripts/config.sh
scripts/hysteria-update.sh
scripts/manager-update.sh
scripts/outbound-manager.sh
scripts/post-deploy-check.sh
config/app.conf
README.md
EOF
}

manager_update_download_file() {
    local file="$1"
    local dest_root="$2"
    local dest="$dest_root/$file"

    mkdir -p "$(dirname "$dest")" || return 1
    curl -fsSL --connect-timeout 8 --max-time 30 "$MANAGER_UPDATE_RAW_URL/$file" -o "$dest"
}

manager_update_download_all() {
    local dest_root="$1"
    local failed=0
    local file

    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        echo "  下载 $file"
        if ! manager_update_download_file "$file" "$dest_root"; then
            echo "    失败: $file"
            ((failed++))
        fi
    done < <(manager_update_files)

    [[ "$failed" -eq 0 ]]
}

manager_update_validate_download() {
    local root="$1"
    local files=()
    local file

    while IFS= read -r file; do
        [[ "$file" == *.sh ]] || continue
        files+=("$root/$file")
    done < <(manager_update_files)

    bash -n "${files[@]}"
}

manager_update_backup_current() {
    local backup_dir="/var/backups/s-hy2/manager-$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$backup_dir" || return 1
    if [[ -d "$MANAGER_UPDATE_INSTALL_DIR" ]]; then
        cp -a "$MANAGER_UPDATE_INSTALL_DIR/." "$backup_dir/"
    fi

    echo "$backup_dir"
}

manager_update_apply() {
    local source_root="$1"

    mkdir -p "$MANAGER_UPDATE_INSTALL_DIR" || return 1
    cp -a "$source_root/." "$MANAGER_UPDATE_INSTALL_DIR/"
    chmod +x "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh" "$MANAGER_UPDATE_INSTALL_DIR/install.sh" "$MANAGER_UPDATE_INSTALL_DIR/quick-install.sh" 2>/dev/null || true
    chmod +x "$MANAGER_UPDATE_INSTALL_DIR"/scripts/*.sh 2>/dev/null || true

    ln -sf "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh" "$MANAGER_UPDATE_BIN_DIR/hy2-manager"
    ln -sf "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh" "$MANAGER_UPDATE_BIN_DIR/s-hy2"
}

manage_script_update() {
    echo ""
    echo "=== 管理脚本更新 ==="
    echo "更新源: $MANAGER_UPDATE_RAW_URL"
    echo "安装目录: $MANAGER_UPDATE_INSTALL_DIR"
    echo ""
    echo "此操作只更新 s-hy2 管理脚本文件，不会修改 /etc/hysteria 配置，也不会更新 Hysteria2 内核。"
    echo "更新范围: 主菜单、安装入口、快速安装器、更新模块、配置/证书权限相关模块、版本配置和 README。"
    echo ""
    echo -n "是否开始更新管理脚本? [y/N]: "

    local choice
    read -r choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo "已取消。"
        return 0
    fi

    local tmp_dir backup_dir
    tmp_dir="$(mktemp -d)"

    echo "[INFO] 下载最新脚本文件..."
    if ! manager_update_download_all "$tmp_dir"; then
        echo "[ERROR] 下载失败，未修改当前安装。"
        rm -rf "$tmp_dir"
        return 1
    fi

    echo "[INFO] 校验脚本语法..."
    if ! manager_update_validate_download "$tmp_dir"; then
        echo "[ERROR] 新脚本语法校验失败，未修改当前安装。"
        rm -rf "$tmp_dir"
        return 1
    fi

    echo "[INFO] 备份当前脚本..."
    backup_dir="$(manager_update_backup_current)" || {
        echo "[ERROR] 备份失败，未修改当前安装。"
        rm -rf "$tmp_dir"
        return 1
    }

    echo "[INFO] 应用更新..."
    if ! manager_update_apply "$tmp_dir"; then
        echo "[ERROR] 应用更新失败。备份位置: $backup_dir"
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"

    echo "[SUCCESS] 管理脚本更新完成。"
    echo "备份位置: $backup_dir"
    echo "重新运行: sudo s-hy2"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    manage_script_update
fi
