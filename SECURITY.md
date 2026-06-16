# Security Policy

BTC Solo Lab is a real Bitcoin mainnet mining lab. Please treat security reports seriously even when the project is used only for learning.

## Supported Versions

Only the latest `main` branch and the latest tagged release are actively maintained.

## What To Report

Please report issues that can affect local safety, privacy, or release integrity, including:

- Real `configs/miner.env` leakage.
- BTC address validation bypasses.
- Path traversal or symlink bypasses for `MINER_BIN`, `LOG_DIR`, or `LOG_FILE`.
- Command injection in config parsing or script execution.
- Pool password leakage in dry-run output, logs, process views, or UI.
- Ability to start unbounded or multi-threaded mining without explicit opt-in.
- Failure to stop the app-managed miner process.
- Packaging that bundles real config, development scripts, or unexpected runtime files.
- Incorrect signing, notarization, or release verification guidance.

## Reporting Process

Open a GitHub issue if the report does not contain sensitive information.

If the report includes private configuration, addresses, logs, or a reproducible exploit that should not be public yet, please open a minimal public issue stating that you have a security report and avoid posting the sensitive details. The maintainer will coordinate next steps through GitHub.

## Maintainer Response

The maintainer aims to:

- Acknowledge valid reports within 7 days.
- Reproduce and classify the issue.
- Prioritize fixes that prevent unintended real mainnet mining, credential leakage, or unsafe packaging.
- Credit reporters in release notes when appropriate.

## Non-Goals

The project cannot make CPU mining profitable, prevent all network-level observation of plaintext Stratum traffic, or guarantee CKPool availability. Those are documented operational limits, not security vulnerabilities.
