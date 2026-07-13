# Hysteria2 VPS Install Maintenance Design

## Goal

Maintain the deployment manager for current Hysteria 2 releases while making
the command-line workflow faster, clearer, and safer. The project continues to
use the official Hysteria installer and release source.

## Scope

### Menu and module loading

`hy2-manager.sh` remains the stable executable entry point. It is responsible
only for startup checks, the top-level menu, and loading a module when the user
opens its menu. It must not source large optional modules during startup.

The top-level menu groups actions by intent:

- Install and update
- Configuration management
- Service and diagnostics
- Network and system
- Node and subscription information
- Certificates and domains
- Outbounds and firewall
- About and manager update

Quick and manual configuration move into a "create or reset configuration"
submenu. Each destructive action must explain that it replaces the current
configuration and require confirmation. Editing the current configuration is a
separate action.

New shell modules are justified only when they contain a coherent feature used
by an entry point or are shared by multiple modules. Short helpers stay with
their caller.

### Official configuration support

The configuration interface supports commonly administered Hysteria server
fields: listener, TLS or ACME, authentication, obfuscation, masquerade,
bandwidth, client bandwidth behavior, UDP behavior, ACL, outbounds, and
routing. Existing valid fields outside this set remain intact.

An advanced full-YAML editor backs up the configuration before editing. It
validates the candidate using `hysteria config check`; only a valid candidate
replaces the live configuration, and restart remains an explicit user choice.

The source of truth for server schema and core behavior is the current official
documentation at https://v2.hysteria.network/zh/docs/advanced/Full-Server-Config/
and the upstream repository https://github.com/apernet/hysteria.

### Diagnostics and repair

A diagnostic module reports configuration syntax, binary and service state,
file ownership and permissions, certificate readability, UDP listener and port
conflicts, firewall exposure, ACME prerequisites, configuration/core
compatibility, and BBR/FQ state.

Each result includes a status, reason, and action. The user may confirm repairs
only for deterministic, non-destructive findings: service enable/start,
configuration and certificate permissions, firewall rule creation, and BBR/FQ
configuration. DNS, ACME issuance, and a port owned by another service are
reported without an automated destructive repair.

### BBR and FQ

The network module detects the active congestion control and default queue
discipline. On confirmation it writes only `/etc/sysctl.d/99-s-hy2-network.conf`
with `net.ipv4.tcp_congestion_control=bbr` and `net.core.default_qdisc=fq`,
applies the settings, and verifies them. No unrelated sysctl file is replaced.

### Updates

The core update module obtains release versions from the official
`apernet/hysteria` Release API, with existing fallbacks retained. When the
installed version equals the latest version, it displays that the core is
current and does not offer a normal update. A force reinstall remains available
as an explicit action. Installation and upgrades use `https://get.hy2.sh/`.

### Node and subscription output

All generated URI and subscription output explicitly includes `insecure=0`
unless the user has explicitly selected certificate verification bypass, in
which case it includes `insecure=1`. Authentication and Salamander passwords
are percent-encoded in URIs and safely quoted and escaped in YAML and JSON
outputs.

### Cleanup and documentation

Unused startup-cache and command-batch functionality is removed. Comments are
kept only where they explain a non-obvious constraint or safety decision.
README documents the official sources, installation, new menu structure,
diagnostics, BBR/FQ behavior, and update process.

## Verification

Automated shell tests cover version comparison and update decisions, URI
encoding, explicit `insecure=0`, YAML quoting, diagnostic finding and repair
selection, BBR/FQ file generation, and lazy module loading. The complete script
set is checked with `bash -n`. Manual checks cover menu navigation and a valid
and invalid full-YAML edit using a fixture Hysteria binary.

## Non-goals

This release does not replace the official Hysteria installer, silently modify
unknown valid configuration, issue certificates without user confirmation, or
terminate unrelated processes that occupy a configured port.
