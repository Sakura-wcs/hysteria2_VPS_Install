#!/usr/bin/env bash

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/test-helper.sh"
source "$ROOT/scripts/manager-update.sh"
case "$OSTYPE" in
    msys*|cygwin*)
        export CONFIG_VALIDATE_PYTHON="${CONFIG_VALIDATE_PYTHON:-python}"
        # Windows hosts without Developer Mode cannot create real symlinks.
        ln() { cp -- "$3" "$4"; }
        ;;
esac

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$tmp"' EXIT
candidate="$tmp/candidate"
while IFS= read -r file; do
    mkdir -p "$candidate/$(dirname "$file")"
    cp "$ROOT/$file" "$candidate/$file" || exit 1
done < <(manager_update_files)

manager_update_validate_download "$candidate" || fail 'valid runtime tree rejected'
printf '\nif ; then\n' >> "$candidate/scripts/diagnostics.sh"
if manager_update_validate_download "$candidate" 2>/dev/null; then
    fail 'invalid later module accepted'
fi
cp "$ROOT/scripts/diagnostics.sh" "$candidate/scripts/diagnostics.sh"
rm "$candidate/scripts/diagnostics.sh"
if manager_update_validate_download "$candidate" 2>/dev/null; then
    fail 'missing module accepted'
fi

export MANAGER_UPDATE_INSTALL_DIR="$tmp/install" MANAGER_UPDATE_BIN_DIR="$tmp/bin"
mkdir -p "$MANAGER_UPDATE_INSTALL_DIR" "$MANAGER_UPDATE_BIN_DIR"
printf 'old manager\n' > "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh"
if (manager_deploy "$candidate") >/dev/null 2>&1; then fail 'incomplete tree was deployed'; fi
if (curl() { return 1; }; manager_deploy) >/dev/null 2>&1; then fail 'failed download was deployed'; fi
assert_file_contains "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh" 'old manager'
cp "$ROOT/scripts/diagnostics.sh" "$candidate/scripts/diagnostics.sh"

(
    fixture_revision=0123456789abcdef0123456789abcdef01234567
    curl() {
        local arg url='' dest=''
        while (( $# )); do
            arg="$1"; shift
            case "$arg" in
                https://*) url="$arg" ;;
                -o) dest="$1"; shift ;;
            esac
        done
        case "$url" in
            https://api.github.com/repos/Sakura-wcs/hysteria2_VPS_Install/commits/main) printf '%s\n' "$fixture_revision" ;;
            "https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install/$fixture_revision/"*)
                cp "$candidate/${url#*/$fixture_revision/}" "$dest" ;;
            *) return 1 ;;
        esac
    }
    MANAGER_UPDATE_INSTALL_DIR="$tmp/remote" MANAGER_UPDATE_BIN_DIR="$tmp/remote-bin"
    MANAGER_UPDATE_RAW_URL='https://raw.githubusercontent.com/Sakura-wcs/hysteria2_VPS_Install/main'
    manager_deploy && cmp "$candidate/hy2-manager.sh" "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh"
) >/dev/null 2>&1 || fail 'remote deployment did not fetch every file from one revision'

printf 'unrelated command\n' > "$MANAGER_UPDATE_BIN_DIR/s-hy2"
if (manager_deploy "$candidate") >/dev/null 2>&1; then fail 'deployment overwrote an unrelated command'; fi
assert_file_contains "$MANAGER_UPDATE_BIN_DIR/s-hy2" 'unrelated command'
assert_file_contains "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh" 'old manager'
rm "$MANAGER_UPDATE_BIN_DIR/s-hy2"
if (ln() { return 1; }; manager_deploy "$candidate") >/dev/null; then
    fail 'activation failure was reported as success'
fi
assert_file_contains "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh" 'old manager'
manager_deploy "$candidate" >/dev/null || fail 'valid runtime tree was not deployed'
cmp "$candidate/hy2-manager.sh" "$MANAGER_UPDATE_INSTALL_DIR/hy2-manager.sh" || fail 'installed entry point differs'
assert_file_contains "$MANAGER_UPDATE_BIN_DIR/s-hy2" '#!'
for legacy in templates config/app.conf scripts/config-loader.sh scripts/performance-monitor.sh scripts/post-deploy-check.sh scripts/secure-download.sh; do
    [[ ! -e "$MANAGER_UPDATE_INSTALL_DIR/$legacy" ]] || fail "deployment included unused payload: $legacy"
done

rm "$MANAGER_UPDATE_BIN_DIR/s-hy2"
printf 'unrelated replacement\n' > "$MANAGER_UPDATE_BIN_DIR/s-hy2"
uninstall_result="$(manager_uninstall)" || fail 'manager uninstall failed'
[[ ! -e "$MANAGER_UPDATE_INSTALL_DIR" ]] || fail 'manager install is still active'
assert_file_contains "$MANAGER_UPDATE_BIN_DIR/s-hy2" 'unrelated replacement'
assert_file_contains "${uninstall_result#*: }/hy2-manager.sh" '#!'

source "$ROOT/scripts/config-validator.sh"
printf '%s\n' '"listen": ":443"' 'TrafficStats: {listen: ":9999"}' 'mimic: {enabled: true}' \
    'masquerade: {type: string, listenHTTP: ":8080", listenHTTPS: ":8443"}' > "$tmp/test.yaml"
timeout() {
    local args=" $* " config
    while [[ "$1" != --config ]]; do shift; done
    config="$2"
    [[ "$config" == *.yaml ]] || return 1
    grep -qF '127.0.0.1:0' "$config" || return 1
    if grep -qiE 'trafficstats|mimic|listenhttp|:9999|:8080|:8443' "$config"; then return 1; fi
    if [[ "$args" == *' --log-level info '* ]]; then
        printf '%s\n' "{\"level\":\"info\",\"msg\":\"${PROBE_MESSAGE:-server up and running}\"}"
    fi
    return 124
}
config_validate_with_core "$tmp/test.yaml" || fail 'valid server startup was not detected'
if PROBE_MESSAGE='traffic stats server up and running' config_validate_with_core "$tmp/test.yaml" 2>/dev/null; then
    fail 'auxiliary listener was mistaken for the Hysteria server'
fi

(
    source "$ROOT/quick-install.sh"
    ROOT_OVERRIDE="$ROOT"
    INSTALL_DIR="$tmp/quick" BIN_DIR="$tmp/quick-bin"
    curl() { return 1; }
    quick_install_manager "$ROOT_OVERRIDE" >/dev/null || exit 1
    cmp "$ROOT/hy2-manager.sh" "$INSTALL_DIR/hy2-manager.sh"
) || fail 'local quick install does not reuse the staged deployment'

(
    source "$ROOT/hy2-manager.sh"
    wait_for_user() { :; }
    clear() { :; }
    bash() {
        [[ "$1" == "$ROOT/install.sh" && "${2:-}" == --remove ]] || return 1
        printf 'official remover\n'
    }
    output="$(uninstall_hysteria <<< $'1\ny')" || exit 1
    [[ "$output" == *'official remover'* && "$output" != *'nginx'* ]]
) || fail 'uninstall menu did not use the config-preserving core remover'

finish_tests
