#!/usr/bin/env bash

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/test-helper.sh"
source "$ROOT/hy2-manager.sh"

load_new_modules
assert_not_defined manage_outbound
assert_not_defined manage_firewall
assert_defined log_info

source "$ROOT/scripts/manager-update.sh"
assert_contains "$(manager_update_files)" 'scripts/diagnostics.sh'
assert_contains "$(manager_update_files)" 'scripts/network-tuning.sh'
assert_contains "$(manager_update_files)" 'scripts/config-advanced.sh'
assert_contains "$(manager_update_files)" 'scripts/config-validator.sh'
assert_not_contains "$(manager_update_files)" 'scripts/performance-utils.sh'

bash -c "source '$ROOT/scripts/config-advanced.sh'; declare -F config_validate_with_core >/dev/null" || fail 'advanced configuration should load its validator dependency'

(
    check_root() { :; }
    check_script_integrity() { :; }
    print_header() { :; }
    show_status() { :; }
    domain_management() { echo 'visited:domain'; }
    certificate_management() { echo 'visited:certificate'; }
    output="$(main <<< $'6\n2\n0')"
    assert_contains "$output" 'visited:domain'
    assert_not_contains "$output" 'visited:certificate'
    finish_tests
) || fail 'top-level option 6 should dispatch only the selected submenu'

(
    CONFIG_PATH="$ROOT/README.md"
    clear() { :; }
    sleep() { :; }
    edit_config_file() { echo 'edited:direct'; }
    output="$(config_management <<< $'6\n0' 2>&1)"
    assert_not_contains "$output" 'edited:direct'
    finish_tests
) || fail 'current configuration menu must not bypass the validated YAML editor'

finish_tests
