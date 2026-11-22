#!/usr/bin/env bash

MANAGER_UPSTREAM_RAW='https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install'
MANAGER_UPDATE_RAW_URL="${MANAGER_UPDATE_RAW_URL:-$MANAGER_UPSTREAM_RAW/main}"
MANAGER_UPDATE_INSTALL_DIR="${MANAGER_UPDATE_INSTALL_DIR:-/opt/s-hy2}"
MANAGER_UPDATE_BIN_DIR="${MANAGER_UPDATE_BIN_DIR:-/usr/local/bin}"

manager_update_files() {
    cat <<'EOF'
hy2-manager.sh
install.sh
quick-install.sh
scripts/certificate-sync.sh
scripts/common.sh
scripts/config.sh
scripts/config-advanced.sh
scripts/config-validator.sh
scripts/diagnostics.sh
scripts/domain-test.sh
scripts/firewall-manager.sh
scripts/hysteria-update.sh
scripts/input-validation.sh
scripts/manager-update.sh
scripts/network-tuning.sh
scripts/node-info.sh
scripts/outbound-manager.sh
scripts/service.sh
README.md
EOF
}

manager_update_download_file() {
    local file="$1"
    local dest_root="$2"
    local dest="$dest_root/$file"

    mkdir -p "$(dirname "$dest")" || return 1
    curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 30 "$MANAGER_UPDATE_RAW_URL/$file" -o "$dest"
}

manager_update_download_all() {
    local dest_root="$1"
    local source_root="${2:-}" file revision
    local MANAGER_UPDATE_RAW_URL="$MANAGER_UPDATE_RAW_URL"

    if [[ -z "$source_root" && "$MANAGER_UPDATE_RAW_URL" == "$MANAGER_UPSTREAM_RAW/main" ]]; then
        revision="$(curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 30 \
            -H 'Accept: application/vnd.github.sha' \
            https://api.github.com/repos/Sakura-wcs/hysteria2_VPS_Install/commits/main)" || return 1
        [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo '未获取到有效的上游提交。' >&2; return 1; }
        MANAGER_UPDATE_RAW_URL="$MANAGER_UPSTREAM_RAW/$revision"
    fi

    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        if [[ -n "$source_root" ]]; then
            mkdir -p "$(dirname "$dest_root/$file")" && cp -- "$source_root/$file" "$dest_root/$file" || return 1
        elif ! manager_update_download_file "$file" "$dest_root"; then
            printf '下载失败: %s\n' "$file" >&2
            return 1
        fi
    done < <(manager_update_files)
}

manager_update_validate_download() {
    local root="$1"
    local file

    while IFS= read -r file; do
        if [[ ! -s "$root/$file" ]]; then
            printf '文件缺失或为空: %s\n' "$file" >&2
            return 1
        fi
        case "$file" in
            *.sh) bash -n "$root/$file" || return 1 ;;
        esac
    done < <(manager_update_files)
}

manager_command_is_ours() {
    [[ -L "$1" && "$(readlink -- "$1")" == "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh" ]]
}

manager_deploy() (
    local source_root="${1:-}" install_dir="$MANAGER_UPDATE_INSTALL_DIR"
    local parent stage='' backup='' link lock file publishing=0 activated=0
    local -a new_links=()
    parent="$(dirname -- "$install_dir")" || return 1
    mkdir -p -- "$parent" "$MANAGER_UPDATE_BIN_DIR" || return 1
    lock="$install_dir.lock"
    mkdir -- "$lock" || { echo "无法获取部署锁: $lock" >&2; return 1; }

    manager_deploy_cleanup() {
        local status=$? item moved=1
        if (( ! activated )); then
            for item in "${new_links[@]}"; do
                if manager_command_is_ours "$item"; then rm -- "$item" || status=1; fi
            done
            if (( publishing )) && [[ ! -d "$stage/runtime" ]]; then
                mv -T -- "$install_dir" "$stage/failed" || moved=0
            fi
            if [[ -n "$backup" && -d "$backup/previous" ]]; then
                if (( moved )) && mv -T -- "$backup/previous" "$install_dir"; then
                    rmdir -- "$backup" || status=1
                else
                    printf '自动回退失败，原安装保留在: %s/previous\n' "$backup" >&2
                    status=1
                fi
            elif [[ -n "$backup" ]]; then
                rmdir -- "$backup" || status=1
            fi
        fi
        if [[ -n "$stage" ]]; then rm -rf -- "$stage" || status=1; fi
        rmdir -- "$lock" || status=1
        return "$status"
    }
    trap manager_deploy_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if [[ -L "$install_dir" || ( -e "$install_dir" && ! -f "$install_dir/hy2-manager.sh" ) ]]; then
        printf '不是可识别的 s-hy2 安装目录: %s\n' "$install_dir" >&2
        return 1
    fi
    for link in "$MANAGER_UPDATE_BIN_DIR/hy2-manager" "$MANAGER_UPDATE_BIN_DIR/s-hy2"; do
        if [[ -e "$link" || -L "$link" ]] && ! manager_command_is_ours "$link"; then
            printf '保留已有命令，不会覆盖: %s\n' "$link" >&2
            return 1
        fi
    done

    stage="$(mktemp -d "$parent/.s-hy2-stage.XXXXXXXX")" || return 1
    mkdir -m 755 -- "$stage/runtime" || return 1
    manager_update_download_all "$stage/runtime" "$source_root" || return 1
    manager_update_validate_download "$stage/runtime" || return 1
    while IFS= read -r file; do
        case "$file" in *.sh) chmod 755 "$stage/runtime/$file" || return 1 ;; esac
    done < <(manager_update_files)

    if [[ -d "$install_dir" ]]; then
        backup="$(mktemp -d "$parent/.s-hy2-backup.XXXXXXXX")" || return 1
        mv -T -- "$install_dir" "$backup/previous" || return 1
    fi
    publishing=1
    mv -T -- "$stage/runtime" "$install_dir" || return 1
    for link in "$MANAGER_UPDATE_BIN_DIR/hy2-manager" "$MANAGER_UPDATE_BIN_DIR/s-hy2"; do
        if ! manager_command_is_ours "$link"; then
            new_links+=("$link")
            ln -sT -- "$install_dir/hy2-manager.sh" "$link" || return 1
        fi
    done
    activated=1
    if [[ -n "$backup" ]]; then printf '旧安装备份: %s/previous\n' "$backup"; fi
    return 0
)

manager_uninstall() (
    local install_dir="$MANAGER_UPDATE_INSTALL_DIR" lock parent backup link result=0
    lock="$install_dir.lock"
    [[ ! -L "$install_dir" && -f "$install_dir/hy2-manager.sh" ]] || {
        printf '未找到可识别的 s-hy2 安装: %s\n' "$install_dir" >&2
        return 1
    }
    mkdir -- "$lock" || { echo "无法获取部署锁: $lock" >&2; return 1; }
    trap 'rmdir -- "$lock"' EXIT
    parent="$(dirname -- "$install_dir")" || return 1
    backup="$(mktemp -d "$parent/.s-hy2-backup.XXXXXXXX")" || return 1
    if ! mv -T -- "$install_dir" "$backup/previous"; then
        rmdir -- "$backup"
        return 1
    fi
    for link in "$MANAGER_UPDATE_BIN_DIR/hy2-manager" "$MANAGER_UPDATE_BIN_DIR/s-hy2"; do
        if manager_command_is_ours "$link"; then rm -- "$link" || result=1; fi
    done
    printf '管理器文件已移出安装目录，可从此处恢复: %s/previous\n' "$backup"
    return "$result"
)

manage_script_update() {
    echo ""
    echo "=== 管理脚本更新 ==="
    echo "更新源: $MANAGER_UPDATE_RAW_URL"
    echo "安装目录: $MANAGER_UPDATE_INSTALL_DIR"
    echo ""
    echo "此操作只更新 s-hy2 管理脚本文件，不会修改 /etc/hysteria 配置，也不会更新 Hysteria2 内核。"
    echo "更新范围: 全部运行脚本和 README。"
    echo ""
    echo -n "是否开始更新管理脚本? [y/N]: "

    local choice
    read -r choice || return 0
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo "已取消。"
        return 0
    fi

    if ! manager_deploy; then
        echo "[ERROR] 管理脚本更新失败。" >&2
        return 1
    fi

    echo "[SUCCESS] 管理脚本更新完成。"
    echo "重新运行: sudo s-hy2"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    manage_script_update
fi
