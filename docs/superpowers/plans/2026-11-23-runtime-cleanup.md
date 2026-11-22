# Runtime Cleanup Implementation Plan

**Goal:** Consolidate active menus and ship only the files reachable from the supported manager and installer workflows.

**Architecture:** Keep `hy2-manager.sh` as the menu entry point and `scripts/manager-update.sh` as the sole runtime inventory. Keep legacy updater payloads at their original URLs without deploying them on new installs.

**Constraints:** No changes to `/etc/hysteria` layout, current menu numbering, command aliases, or configured services during verification. Retain regression tests.

- Exercise top-level option 6 and assert that selecting domains never enters the certificate menu. Exercise current config editing and require the legacy direct editor option to be unavailable.
- Remove overwritten definitions. Route option 6 through one selector and keep one validated full-YAML edit path. Make touched interactive loops return on EOF.
- Remove unused templates, benchmark and download helper, and stop deploying superseded config defaults/loader and diagnostics scripts. Retain the three hard-coded old updater targets until compatibility can be dropped.
- Validate menu interactions, stage a test-only installation, run all regression scripts and Bash syntax checks, and review the diff.
