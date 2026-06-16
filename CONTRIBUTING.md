# Contributing

BTC Solo Lab welcomes focused contributions that improve safety, reproducibility, documentation, or the learning experience.

## Principles

- Keep the project honest: this is a real mainnet lab, not a profit miner.
- Prefer small, reviewable changes.
- Do not broaden runtime permissions unless the safety case is clear.
- Do not commit local config, run logs, build outputs, packaged apps, DMGs, API keys, wallet seed phrases, private keys, or real payout details.
- Preserve conservative defaults unless a change explicitly improves safety.

## Local Setup

```bash
npm install
./scripts/bootstrap-cpuminer.sh
cp configs/miner.env.example configs/miner.env
```

Edit `configs/miner.env` with a self-custody Bitcoin mainnet address before real mining.

## Validation

Before opening a pull request, run:

```bash
npm run verify
```

For documentation-only changes, at least run:

```bash
npm run build
bash -n scripts/*.sh scripts/lib/*.sh
```

## Pull Request Checklist

- Explain the user-facing behavior change.
- State whether real mainnet mining behavior changes.
- State whether resource limits, path guards, redaction, packaging, or config parsing changed.
- Include test output or explain why a check was not run.
- Update README, roadmap, changelog, or security docs when relevant.

## Issue Guidelines

Useful issues include:

- Clear environment details: macOS version, chip, Node/Rust versions, app or CLI path.
- Exact command run.
- Redacted logs.
- Whether this was dry-run, preflight, smoke, or real start.
- Expected vs actual behavior.

Do not post seed phrases, private keys, exchange account details, or unreduced logs containing personal identifiers.
