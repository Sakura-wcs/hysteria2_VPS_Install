# Safe Maintenance Implementation Plan

**Goal:** Repair configuration checks, manager deployment and uninstall without changing existing Hysteria configuration or removing shared system packages.

**Architecture:** `scripts/manager-update.sh` owns the runtime file list and staged deployment. `quick-install.sh` reuses that module from the checkout or bootstraps it over HTTPS. Keep the installed command names and existing Hysteria config paths.

**Tech stack:** Bash, GNU coreutils, curl, Linux/systemd; portable regression tests in Git Bash.

- [x] Add regressions for invalid later modules, incomplete downloads, failed activation and Hysteria startup logging; run them against the existing scripts.
- [x] Make `manager_update_validate_download ROOT` check every runtime file and process shell files individually. Make `manager_deploy [LOCAL_ROOT]` stage, validate and publish a complete tree, retaining the old tree as a backup and refusing to overwrite unrelated command entries.
- [x] Route quick installation through the shared deployment, remove obsolete desktop integration, and make uninstall preserve shared system packages and existing Hysteria configuration by default.
- [x] Correct the readiness check and document what the runtime probe does and does not validate.
- [x] Run all regression scripts, individually syntax-check Bash files and inspect `git diff --check`; do not install on the host or push.
