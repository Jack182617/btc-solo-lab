# Changelog

All notable changes will be documented in this file.

## Unreleased

- No unreleased changes yet.

## 0.1.0 - 2026-06-16

- Published the initial open-source release.
- Reworked the public README to be English-first with screenshots, architecture, safety boundaries, and verification guidance.
- Added security policy, contribution guide, roadmap, issue templates, PR template, and CI workflow.
- Added Tauri desktop app and CLI workflows for bounded Bitcoin mainnet solo mining experiments.
- Added CKPool configuration, preflight, dry-run, start/stop, status, and CKPool user-stat checks.
- Added BTC mainnet address validation for Bech32/Bech32m and Base58Check.
- Added local config parsing through an allowlist instead of shell-sourcing config.
- Added low-resource defaults: one thread, duty-cycle throttling, AC power requirement, and bounded runtime.
- Added path guards for miner binary, log directory, and log file.
- Added password redaction in dry-run output, process views, and log tails.
- Added macOS packaging and release audit scripts.
