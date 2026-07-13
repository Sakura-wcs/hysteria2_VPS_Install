#!/usr/bin/env bash

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/test-helper.sh"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

SYSCTL_CONF="$TEST_TMP/99-s-hy2-network.conf"
SYSCTL_LOG="$TEST_TMP/sysctl.log"
SYSCTL_BIN="$TEST_TMP/sysctl"
cat > "$SYSCTL_BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSCTL_LOG"
EOF
chmod +x "$SYSCTL_BIN"
export SYSCTL_CONF SYSCTL_LOG SYSCTL_BIN

source "$ROOT/scripts/network-tuning.sh"

network_write_bbr_fq
assert_file_contains "$SYSCTL_CONF" 'net.core.default_qdisc=fq'
assert_file_contains "$SYSCTL_CONF" 'net.ipv4.tcp_congestion_control=bbr'
assert_contains "$(<"$SYSCTL_LOG")" "-p $SYSCTL_CONF"

DIAGNOSTIC_CONFIG="$TEST_TMP/config.yaml"
HYSTERIA_BIN="$TEST_TMP/hysteria"
printf '%s\n' 'listen: :443' 'auth:' '  type: password' '  password: test' > "$DIAGNOSTIC_CONFIG"
cat > "$HYSTERIA_BIN" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == config && "$2" == check && -f "$3" ]]
EOF
chmod +x "$HYSTERIA_BIN"
export DIAGNOSTIC_CONFIG HYSTERIA_BIN

DIAGNOSTIC_RESULTS=""
DIAGNOSTIC_REPAIRABLE=""
source "$ROOT/scripts/diagnostics.sh"
diagnostic_collect
assert_contains "$DIAGNOSTIC_RESULTS" 'config:ok'
assert_contains "$DIAGNOSTIC_REPAIRABLE" 'network-bbr-fq'

CONFIG_ADVANCED_PATH="$TEST_TMP/live-config.yaml"
candidate="$TEST_TMP/candidate.yaml"
printf '%s\n' 'listen: :443' 'auth:' '  type: password' '  password: test' > "$candidate"
source "$ROOT/scripts/config-advanced.sh"
config_advanced_apply "$candidate"
assert_file_contains "$CONFIG_ADVANCED_PATH" 'listen: :443'

finish_tests
