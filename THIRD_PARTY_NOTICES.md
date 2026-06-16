# Third-Party Notices

## cpuminer-multi

BTC Solo Lab uses `cpuminer-multi` for local Bitcoin mainnet mining experiments. The bootstrap script clones the upstream repository into `vendor/cpuminer-multi` and checks out the pinned ref before building the local miner binary.

- Upstream: https://github.com/tpruvot/cpuminer-multi
- Default pinned ref: `d2927ed23b1d0eacd067c320fce64e6610737adb`
- License: GNU General Public License version 2 or later
- Local build path: `vendor/cpuminer-multi`

The upstream license text is available in `vendor/cpuminer-multi/COPYING` after bootstrap and in this repository's root `LICENSE` file.
