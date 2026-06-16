# Release Checklist

Use this checklist before publishing a GitHub release or distributing a macOS build.

## Source Checks

- [ ] `npm ci`
- [ ] `npm run verify`
- [ ] `git status --short` is clean except intentional release artifacts.
- [ ] `configs/miner.env` is not tracked.
- [ ] `logs/`, `dist/`, `src-tauri/target/`, `.playwright-cli/`, and `vendor/cpuminer-multi/` are not tracked.
- [ ] `CHANGELOG.md` has the release entry.
- [ ] README setup and risk boundaries still match runtime behavior.

## Runtime Safety

- [ ] Default config remains one thread.
- [ ] Default run remains bounded.
- [ ] Real starts still require preflight unless explicitly overridden.
- [ ] Address validation rejects testnet, regtest, and bad checksum addresses.
- [ ] Path guards reject project escapes and symlink escapes.
- [ ] Dry-run and status output redact pool passwords.
- [ ] Real start refuses to run when an existing miner process is detected.

## macOS Packaging

- [ ] `./scripts/bootstrap-cpuminer.sh` has built `vendor/cpuminer-multi/cpuminer`.
- [ ] `npm run package:macos` passes.
- [ ] `scripts/audit-release.sh` passes.
- [ ] Public distribution builds use a real reverse-DNS bundle identifier, not `com.local.btcsololab`.
- [ ] Public distribution builds use Developer ID Application signing.
- [ ] Public distribution builds pass hardened runtime, notarization, stapling, DMG verification, mounted-app verification, and checksum generation.

## Release Notes

- [ ] State that this is real Bitcoin mainnet mining.
- [ ] State that CPU mining is not profitable.
- [ ] Include the tested macOS/CPU environment.
- [ ] Include SHA-256 checksums for attached artifacts.
- [ ] Mention any safety-relevant changes explicitly.
