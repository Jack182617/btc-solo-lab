# Best Practice Plan

## Recommendation

Use CKPool for the first real mainnet solo mining experience, and keep this project as a bounded, observable lab around it.

This is the right first step because it gives you real Bitcoin mainnet Stratum jobs and real `sha256d` work without syncing a full node or buying ASIC hardware upfront. The tradeoff is that CKPool is still a service dependency and currently charges a `2%` fee if you find a block.

Official references:

- CKPool configuration and caveats: <https://solo.ckpool.org/>
- cpuminer-multi repository and build notes: <https://github.com/tpruvot/cpuminer-multi>

## Scope

This project covers:

- Mac CPU proof-of-flow mining.
- CKPool mainnet solo configuration.
- Local-only BTC address configuration.
- Low CPU and low scheduling priority defaults.
- Manual start/stop only.
- Upgrade path to ASIC hardware later.

This project does not cover:

- Profitability.
- Automated 24/7 mining.
- Custodial payout addresses.
- Local Bitcoin Core full-node solo mining.
- GPU mining.

## Architecture

```text
BTC Solo Lab.app
  -> Tauri command allowlist
  -> Application Support runtime root
  -> configs/miner.env
  -> scripts/preflight.sh
  -> scripts/run-solo-miner.sh
  -> logs/miner-*.log
  -> vendor/cpuminer-multi/cpuminer
  -> stratum+tcp://solo.ckpool.org:3333
  -> Bitcoin mainnet work
```

Local responsibilities:

- Own the BTC address.
- Compile and run the miner.
- Control resource limits.
- Enforce short bounded runs.
- Observe logs, process state, and machine health.
- Provide a bounded local GUI for start, stop, preflight, dry-run, logs, and CKPool status.

CKPool responsibilities:

- Provide Stratum endpoint.
- Provide Bitcoin mainnet block templates.
- Relay solved blocks.
- Expose pool/user statistics.

## Configuration Standard

The runnable local config is `configs/miner.env`. It is ignored by git because the BTC address and worker name are public identifiers.
Scripts parse this file through an explicit key allowlist and never shell-source it, so config text is data rather than executable script.

For CLI usage, `configs/miner.env` lives in the project directory. For the packaged macOS app, the first launch seeds a writable runtime root at `~/Library/Application Support/com.local.btcsololab`; GUI config and logs live there, while the `.app` bundle only provides clean runtime resources.

Required:

```bash
BTC_ADDRESS=bc1...
WORKER_NAME=mac-cpu
```

Default pool:

```bash
POOL_HOST=solo.ckpool.org
POOL_PORT=3333
POOL_PASSWORD=x
```

Default resource limits:

```bash
THREADS=1
THROTTLE_MODE=duty-cycle
DUTY_ACTIVE_SECONDS=1
DUTY_IDLE_SECONDS=9
TIME_LIMIT_SECONDS=300
REQUIRE_AC_POWER=1
ALLOW_UNLIMITED_RUN=0
ALLOW_MULTI_THREAD=0
```

Increase resource usage only after confirming logs, process state, temperature, fan noise, and normal desktop responsiveness.

Path boundaries:

```bash
MINER_BIN=vendor/cpuminer-multi/cpuminer
LOG_DIR=logs
LOG_RETENTION=100
```

`MINER_BIN` and `LOG_DIR` must resolve inside the project root, and `LOG_FILE` must stay under `LOG_DIR`. `MINER_BIN` is resolved through symlinks, so an in-project symlink to an external executable is rejected. These checks are enforced by the actual startup script as well as preflight, so disabling preflight does not bypass the file/path safety boundary. `LOG_RETENTION` keeps the newest miner logs and defaults to `100`.

## Current Mac Profile

The local machine observed during setup:

```text
CPU: Apple M1 Max
Logical CPU: 10
Performance cores: 8
Efficiency cores: 2
Memory: 32GB
Power: AC Power
```

Recommended profile for this machine:

```bash
THREADS=1
THROTTLE_MODE=duty-cycle
DUTY_ACTIVE_SECONDS=1
DUTY_IDLE_SECONDS=9
TIME_LIMIT_SECONDS=300
```

Reasoning:

- One active mining thread already reaches roughly one full CPU core when unthrottled.
- Full-time one-thread mining produced about `2.2 MH/s` in this environment.
- The default duty-cycle produced about `210 kH/s` average while keeping the process paused most of the time.
- CKPool minimum share difficulty is high enough that CPU-level accepted shares are not a realistic short-run target.
- Therefore the best learning profile is not higher hashrate; it is bounded, observable, low-heat protocol exposure.

## First Run Protocol

1. Build miner with `./scripts/bootstrap-cpuminer.sh`.
2. Build the desktop app with `npm run package:macos`.
3. Open `src-tauri/target/release/bundle/macos/BTC Solo Lab.app`.
4. Run `Preflight`.
5. Run `Dry Run`.
6. Run `Start`.
7. Let the default `TIME_LIMIT_SECONDS=300` stop it automatically, or press `Stop`.
8. Confirm no miner remains in the app status panel or with `./scripts/status.sh`.
9. Check CKPool stats from the app or with `./scripts/check-ckpool-user.sh`.
10. For repeatable CLI acceptance, run `./scripts/smoke-start.sh`. It is dry by default; a real 5..60 second mainnet CPU smoke requires `REAL_START_SMOKE=1 REAL_START_CONFIRM=REAL_MAINNET_CPU_MINING`.

Pass criteria:

- Miner starts without build/runtime errors.
- Stratum connection is established.
- New jobs are received.
- Local hashrate is visible.
- No repeated rejects or reconnect loops.
- Mac remains comfortable to use.

Non-pass criteria:

- `accepted` share does not appear quickly.
- CKPool user page says not found during the first short run.

Those are expected at CPU-level hashrate.

## Address Rules

Use:

- Self-custody Bitcoin mainnet address.
- Prefer `bc1q...` or `bc1p...`.
- Address generated by your own wallet.

Do not use:

- Exchange deposit address.
- Lightning invoice.
- Testnet address such as `tb1...`.
- Regtest address such as `bcrt...`.
- Worker name containing real name, email, phone, or device serial.

## Operating Limits

Recommended first run:

```bash
THREADS=1
THROTTLE_MODE=duty-cycle
DUTY_ACTIVE_SECONDS=1
DUTY_IDLE_SECONDS=9
TIME_LIMIT_SECONDS=300
```

If the Mac is cool and responsive:

```bash
DUTY_ACTIVE_SECONDS=1
DUTY_IDLE_SECONDS=4
```

If fan or heat is noticeable:

```bash
DUTY_ACTIVE_SECONDS=1
DUTY_IDLE_SECONDS=19
```

Do not use all cores. For this project, the goal is protocol experience, not hashrate.

On macOS, `cpulimit` can fail to control the actual miner process reliably. It did fail in this setup: the miner process still showed about one full CPU core. The default `duty-cycle` mode uses the same primitive class that CPU limiters use, `SIGSTOP` / `SIGCONT`, but applies it directly to the known miner PID and verifies the paused state with `scripts/status.sh`.

This is intentionally slower, but it is more predictable for a learning run.

## Operational Guardrails

The scripts enforce these guardrails by default:

- `preflight` must pass before `run-solo-miner`.
- AC power is required.
- `THREADS=1` unless explicitly overridden.
- `TIME_LIMIT_SECONDS` is required unless explicitly overridden.
- Worker names are restricted to anonymous safe characters.
- The startup script independently validates the critical resource limits even if preflight is disabled.
- Miner binary and log paths must stay inside the project boundary.
- Existing miner processes block startup. If the startup script cannot inspect the process list, it refuses real mining instead of assuming the machine is clear.
- Bitcoin addresses are validated by checksum and network before use: Bech32/Bech32m for `bc1...`, Base58Check for legacy `1...` and `3...`.
- Run logs are written under `logs/`, including preflight output for app-started runs.
- Log filenames include a timestamp plus a process or high-resolution runtime component, so rapid repeated dry-runs and starts do not overwrite each other.
- Dry-run command output, command stderr/stdout, log tails, and process-status views redact pool passwords before showing command arguments in the UI.
- Old run logs are pruned by the startup script according to `LOG_RETENTION`.
- CKPool `404` user stats are treated as expected low-hashrate behavior, not as a failure.

The desktop app adds these guardrails:

- Rust commands are exposed through a fixed allowlist, not arbitrary shell execution.
- Packaged runs do not depend on the source checkout path; runtime files are initialized into the app data directory.
- GUI edits only write the safe learning profile: `sha256d`, CKPool, `THREADS=1`, `duty-cycle`, bounded runtime.
- GUI config writes are atomic and use the same runtime log directory as the CLI scripts inside the packaged app.
- Start refuses to run while an app-managed miner is already active.
- Stop sends `TERM`, waits briefly, then kills only the app-managed miner process.
- Production build uses a restricted Tauri CSP, local assets, explicit icons, strict app signature verification, and DMG checksum verification.

## macOS App Packaging

Use:

```bash
npm run verify
npm run package:macos
```

Build `vendor/cpuminer-multi/cpuminer` first with `./scripts/bootstrap-cpuminer.sh` on a fresh checkout. The miner binary is a local build artifact, not a source-controlled configuration file.

`npm run tauri:build` intentionally builds only the `.app` bundle. The DMG is created only by `npm run package:macos`, because that script adds signing verification, DMG verification, mounted-image verification, and checksum output.

The packaging script:

- Runs the Vite/Tauri production build.
- Bundles only the runtime allowlist: `preflight`, `run-solo-miner`, `status`, `check-ckpool-user`, `smoke-start`, their shared env parser, `configs/miner.env.example`, and the compiled `cpuminer` binary.
- Creates `BTC Solo Lab.app`.
- Applies ad-hoc signing by default.
- If `SIGNING_IDENTITY="Developer ID Application: ..."` is provided, signs the app with hardened runtime and timestamping.
- Verifies the app with `codesign --verify --deep --strict`.
- Creates a DMG with the app and an `/Applications` link.
- Verifies the DMG with `hdiutil verify`.
- If `NOTARIZE=1`, submits the signed DMG with `xcrun notarytool`, staples the ticket, and validates it with `xcrun stapler validate`.
- Mounts the DMG and verifies the app inside the mounted image.
- Prints a SHA-256 checksum.
- Runs `scripts/audit-release.sh`, which rejects bundled real config, retired development scripts, missing runtime resources, invalid signatures, broken DMG images, and distribution builds that still use the local `com.local...` bundle identifier.

For private local use, ad-hoc signing is enough. For external distribution, use:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE=1 \
NOTARY_KEYCHAIN_PROFILE=btc-solo-lab \
npm run package:macos
```

Before public distribution, replace `com.local.btcsololab` in `src-tauri/tauri.conf.json` with your real reverse-DNS bundle identifier. The package script rejects `NOTARIZE=1` while the local development identifier is still present.

Alternatively, pass `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD` instead of `NOTARY_KEYCHAIN_PROFILE`. Treat a package as public-distribution ready only after Developer ID signing, hardened runtime, notarization, stapling, DMG verification, and mounted-app signature verification all pass.

## Apple Silicon Build Note

On `arm64` / `aarch64` Macs, the bootstrap script disables cpuminer-multi assembly routines by default. The upstream project is old and its ARM assembly path can fail to link on modern Apple Silicon. This is intentional for this lab: portable C `sha256d` is slower, but the experiment needs correctness and real Stratum behavior more than CPU speed.

## What To Observe

Watch miner output for:

- Stratum connection.
- New job notifications.
- Hashrate.
- Share submissions.
- Accepted / rejected messages.
- Reconnect loops.

Watch macOS for:

- CPU percentage.
- Package temperature if you use a sensor tool.
- Fan noise.
- UI responsiveness.
- Battery state. Prefer plugged-in operation.

## Upgrade Path To Real Mining

If you later move toward revenue:

1. Stop using Mac CPU mining for production.
2. Buy ASIC hardware sized for power, noise, heat, and circuit capacity.
3. Use the same BTC address convention only if privacy is acceptable.
4. Point ASICs to `solo.ckpool.org:3333` for solo lottery mode, or to a normal payout pool for predictable revenue.
5. Separate mining network, monitoring, power metering, and ventilation.
6. Track real cost per kWh and ASIC efficiency in J/TH.

The project boundary remains useful: `configs/miner.env` becomes the canonical pool/address reference, while ASIC devices take over hashing.
