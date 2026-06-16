# Roadmap

This roadmap is intentionally conservative. The project should become safer and easier to understand before it becomes more powerful.

## Near Term

- Keep README and setup docs clear for first-time users.
- Add and maintain GitHub Actions CI.
- Improve screenshots and short demo materials.
- Add release notes for each public release.
- Keep all real mining starts bounded by default.
- Expand tests around config parsing, path guards, redaction, and BTC address validation.

## Safety And Release Quality

- Add a public release checklist.
- Improve package audit output for distribution builds.
- Document Developer ID signing and notarization more thoroughly.
- Add stronger release artifact checks before attaching DMGs to GitHub releases.

## UX Improvements

- Improve app copy for first-run safety.
- Add clearer CKPool `404` / low-hashrate explanations.
- Add a guided dry-run-first flow.
- Add richer status parsing for hashrate, rejects, reconnects, and block/job changes.

## Longer Term

- Document ASIC migration as a separate learning path without turning the app into a 24/7 controller.
- Add optional metrics export for local-only analysis.
- Consider a local full-node solo-mining comparison guide as documentation, not as the default workflow.

## Non-Goals

- Profit optimization.
- Cloud mining.
- Custodial payout flows.
- Exchange deposit address support.
- Background auto-start.
- Default unbounded mining.
