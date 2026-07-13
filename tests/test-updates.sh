#!/usr/bin/env bash

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/test-helper.sh"
source "$ROOT/scripts/hysteria-update.sh"

assert_equals current "$(hy_update_decision 2.9.2 2.9.2)"
assert_equals upgrade "$(hy_update_decision 2.10.0 2.9.2)"
assert_equals installed-newer "$(hy_update_decision 2.9.2 2.10.0)"
assert_equals unknown-current "$(hy_update_decision 2.9.2 '')"
assert_equals unavailable-latest "$(hy_update_decision '' 2.9.2)"

finish_tests
