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
assert_not_contains "$(manager_update_files)" 'scripts/performance-utils.sh'

finish_tests
