# Hysteria2 Maintenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a faster modular manager with current Hysteria2 configuration support, diagnostics, BBR/FQ, safe subscriptions, and correct core updates.

**Architecture:** `hy2-manager.sh` stays the launcher and lazy dispatcher. New coherent modules own advanced configuration, diagnostics, and network tuning; existing modules retain their domains. Bash fixtures and command stubs test behavior without modifying the host.

**Tech Stack:** Bash, systemd, sysctl, iproute2, Hysteria2 CLI, curl, GitHub Release API.

---

## File Boundaries

- `hy2-manager.sh`: one grouped top-level menu and lazy module loader.
- `scripts/config-advanced.sh`: common official fields and validated full-YAML replacement.
- `scripts/diagnostics.sh`: diagnosis result collection and whitelisted repairs.
- `scripts/network-tuning.sh`: BBR/FQ detection and `/etc/sysctl.d/99-s-hy2-network.conf` management.
- `scripts/node-info.sh`: URI, YAML, and JSON serialization.
- `scripts/hysteria-update.sh`: pure version decision and interactive update flow.
- `tests/*.sh`: shell regression tests and fixtures.
- `quick-install.sh`, `scripts/manager-update.sh`, `README.md`: package manifest and user documentation.

### Task 1: Test Harness and Safe Subscription Output

**Files:** Create `tests/test-helper.sh`, `tests/test-subscriptions.sh`; modify `scripts/node-info.sh`.

- [ ] **Step 1: Write the failing test**

```bash
source "$ROOT/tests/test-helper.sh"
source "$ROOT/scripts/node-info.sh"
link="$(generate_node_link 'example.com' 443 'a b@/' 'o&b' 'sni.example' false)"
assert_contains "$link" 'a%20b%40%2F@example.com:443'
assert_contains "$link" 'insecure=0'
assert_contains "$link" 'obfs-password=o%26b'
```

- [ ] **Step 2: Verify RED**

Run: `bash tests/test-subscriptions.sh`

Expected: failed assertion because credentials are raw and `insecure=0` is absent.

- [ ] **Step 3: Implement minimal serialization helpers**

```bash
uri_encode() {
    local input="$1" out="" char
    LC_ALL=C
    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        [[ "$char" =~ [a-zA-Z0-9.~_-] ]] && out+="$char" || printf -v out '%s%%%02X' "$out" "'${char}"
    done
    printf '%s' "$out"
}
```

Apply URI encoding to user info and query values, always emit `insecure=0` or
`insecure=1`, and JSON/YAML quote passwords before interpolation.

- [ ] **Step 4: Verify GREEN and commit**

Run: `bash tests/test-subscriptions.sh && bash -n scripts/node-info.sh`

Expected: exit code 0.

```bash
git add tests/test-helper.sh tests/test-subscriptions.sh scripts/node-info.sh
git commit -m "fix: encode subscription credentials safely"
```

### Task 2: Core Update Decision

**Files:** Create `tests/test-updates.sh`; modify `scripts/hysteria-update.sh`.

- [ ] **Step 1: Write the failing test**

```bash
source "$ROOT/tests/test-helper.sh"
source "$ROOT/scripts/hysteria-update.sh"
assert_equals current "$(hy_update_decision 2.9.2 2.9.2)"
assert_equals upgrade "$(hy_update_decision 2.10.0 2.9.2)"
assert_equals unknown-current "$(hy_update_decision 2.9.2 '')"
```

- [ ] **Step 2: Verify RED**

Run: `bash tests/test-updates.sh`

Expected: `hy_update_decision: command not found`.

- [ ] **Step 3: Implement decision and menu behavior**

```bash
hy_update_decision() {
    local latest="$(hy_update_normalize_version "$1")" current="$(hy_update_normalize_version "$2")"
    [[ -n "$current" ]] || { printf '%s\n' unknown-current; return; }
    [[ "$latest" == "$current" ]] && { printf '%s\n' current; return; }
    hy_update_is_newer "$latest" "$current" && printf '%s\n' upgrade || printf '%s\n' installed-newer
}
```

For `current`, report the installed core is current and return. Offer a
separately labelled force reinstall only after that message.

- [ ] **Step 4: Verify GREEN and commit**

Run: `bash tests/test-updates.sh && bash -n scripts/hysteria-update.sh`

Expected: exit code 0.

```bash
git add tests/test-updates.sh scripts/hysteria-update.sh
git commit -m "fix: skip core update when already current"
```

### Task 3: BBR/FQ and Diagnostics

**Files:** Create `scripts/network-tuning.sh`, `scripts/diagnostics.sh`, `tests/test-network-diagnostics.sh`; modify `hy2-manager.sh`.

- [ ] **Step 1: Write failing BBR/FQ and diagnostic tests**

```bash
source "$ROOT/tests/test-helper.sh"
SYSCTL_CONF="$TEST_TMP/network.conf"
source "$ROOT/scripts/network-tuning.sh"
network_write_bbr_fq
assert_file_contains "$SYSCTL_CONF" 'net.core.default_qdisc=fq'
assert_file_contains "$SYSCTL_CONF" 'net.ipv4.tcp_congestion_control=bbr'
```

- [ ] **Step 2: Verify RED**

Run: `bash tests/test-network-diagnostics.sh`

Expected: source failure because the network module does not exist.

- [ ] **Step 3: Implement scoped network configuration**

```bash
network_write_bbr_fq() {
    local path="${SYSCTL_CONF:-/etc/sysctl.d/99-s-hy2-network.conf}"
    install -d -m 755 "$(dirname "$path")" || return 1
    printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' > "$path"
    sysctl -p "$path"
}
```

Implement checks for config syntax, binary/service state, service-readable
config and certificates, UDP port conflict, firewall, ACME prerequisites, and
BBR/FQ. `diagnostic_repair` must only dispatch service enable/start, file
permissions, firewall rule creation, and BBR/FQ; DNS, ACME, and occupied ports
are report-only.

- [ ] **Step 4: Verify GREEN and commit**

Run: `bash tests/test-network-diagnostics.sh && bash -n scripts/network-tuning.sh scripts/diagnostics.sh hy2-manager.sh`

Expected: exit code 0.

```bash
git add tests/test-network-diagnostics.sh scripts/network-tuning.sh scripts/diagnostics.sh hy2-manager.sh
git commit -m "feat: add diagnostics and bbr fq management"
```

### Task 4: Advanced Official Configuration Editing

**Files:** Create `scripts/config-advanced.sh`; modify `scripts/config.sh`, `hy2-manager.sh`, `tests/test-network-diagnostics.sh`.

- [ ] **Step 1: Write failing candidate validation test**

```bash
CONFIG_ADVANCED_PATH="$TEST_TMP/config.yaml"
HYSTERIA_BIN="$TEST_TMP/hysteria"
printf '#!/usr/bin/env bash\nexit 0\n' > "$HYSTERIA_BIN"
chmod +x "$HYSTERIA_BIN"
config_advanced_apply "$TEST_TMP/candidate.yaml"
assert_file_contains "$CONFIG_ADVANCED_PATH" 'listen: :443'
```

- [ ] **Step 2: Verify RED**

Run: `bash tests/test-network-diagnostics.sh`

Expected: `config_advanced_apply: command not found`.

- [ ] **Step 3: Implement atomic validation and replacement**

```bash
config_advanced_apply() {
    local candidate="$1" target="${CONFIG_ADVANCED_PATH:-$CONFIG_PATH}" binary="${HYSTERIA_BIN:-hysteria}"
    "$binary" config check "$candidate" || return 1
    cp -a "$target" "$target.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    install -m 600 "$candidate" "$target"
    set_hysteria_file_permissions "$target"
}
```

Add interactive common fields for listener, TLS/ACME, auth, obfuscation,
masquerade, bandwidth, UDP, ACL, outbounds, and routing. Copy the full config
to a secure temporary candidate for `${EDITOR:-nano}`; validate before replace.
Put quick/manual reset under a dedicated submenu with a second confirmation.

- [ ] **Step 4: Verify GREEN and commit**

Run: `bash tests/test-network-diagnostics.sh && bash -n scripts/config.sh scripts/config-advanced.sh hy2-manager.sh`

Expected: exit code 0.

```bash
git add tests/test-network-diagnostics.sh scripts/config-advanced.sh scripts/config.sh hy2-manager.sh
git commit -m "feat: add validated advanced configuration editing"
```

### Task 5: Lazy Menus, Packaging, Cleanup, and Docs

**Files:** Create `tests/test-menu-loading.sh`; modify `hy2-manager.sh`, `quick-install.sh`, `scripts/manager-update.sh`, `README.md`; delete `scripts/performance-utils.sh`.

- [ ] **Step 1: Write failing lazy-load and packaging tests**

```bash
source "$ROOT/tests/test-helper.sh"
source "$ROOT/hy2-manager.sh"
load_new_modules
assert_not_defined manage_outbound
source "$ROOT/scripts/manager-update.sh"
assert_contains "$(manager_update_files)" 'scripts/diagnostics.sh'
assert_not_contains "$(manager_update_files)" 'scripts/performance-utils.sh'
```

- [ ] **Step 2: Verify RED**

Run: `bash tests/test-menu-loading.sh`

Expected: optional functions are already defined and new modules are absent.

- [ ] **Step 3: Implement a single lazy loader and grouped menu**

```bash
load_module() {
    local name="$1" file="$2"
    [[ " ${LOADED_MODULES:-} " == *" $name "* ]] && return 0
    source "$SCRIPTS_DIR/$file" || return 1
    LOADED_MODULES="${LOADED_MODULES:-} $name"
}
```

Eagerly load only `common.sh`. Delete duplicate menu overrides and unused
`performance-utils.sh`. Add the three new modules to both download/update
lists, remove the deleted file, update the shared script version, and document
sources, grouped menus, advanced validation, diagnostics boundaries, BBR/FQ,
and in-menu updates in README.

- [ ] **Step 4: Verify complete project and publish**

Run: `bash tests/test-subscriptions.sh && bash tests/test-updates.sh && bash tests/test-network-diagnostics.sh && bash tests/test-menu-loading.sh && bash -n hy2-manager.sh install.sh quick-install.sh scripts/*.sh && git diff --check`

Expected: every command exits 0 and `git diff --check` has no output.

```bash
git add -A
git commit -m "feat: improve manager diagnostics and configuration"
git push origin publish-hysteria2-vps-install
```

## Self-Review

- Task 1 covers explicit certificate validation and safe credentials.
- Task 2 covers current-version update behavior using the official release flow.
- Task 3 covers self-check, repair boundaries, BBR, and FQ.
- Task 4 covers full current-core YAML validation and safely separated reset/edit actions.
- Task 5 covers fast lazy startup, menu organization, package manifests, dead-code removal, README, full verification, and GitHub publication.
