#!/usr/bin/env bash

set -u

TEST_FAILURES=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    TEST_FAILURES=$((TEST_FAILURES + 1))
}

assert_equals() {
    local expected="$1" actual="$2"
    [[ "$expected" == "$actual" ]] || fail "expected [$expected], got [$actual]"
}

assert_contains() {
    local actual="$1" expected="$2"
    [[ "$actual" == *"$expected"* ]] || fail "expected [$actual] to contain [$expected]"
}

assert_not_contains() {
    local actual="$1" unexpected="$2"
    [[ "$actual" != *"$unexpected"* ]] || fail "expected [$actual] not to contain [$unexpected]"
}

assert_file_contains() {
    local file="$1" expected="$2"
    [[ -f "$file" ]] || { fail "expected file [$file] to exist"; return; }
    assert_contains "$(<"$file")" "$expected"
}

assert_defined() {
    declare -F "$1" >/dev/null || fail "expected function [$1] to be defined"
}

assert_not_defined() {
    declare -F "$1" >/dev/null && fail "expected function [$1] not to be defined"
}

finish_tests() {
    if [[ "$TEST_FAILURES" -gt 0 ]]; then
        printf '%s test assertion(s) failed\n' "$TEST_FAILURES" >&2
        return 1
    fi
    printf 'PASS\n'
}
