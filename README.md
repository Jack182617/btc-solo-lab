# BTC Mainnet Solo Mining Lab

结论：本项目用于真实体验 Bitcoin 主网 solo mining 流程，不用于 CPU 赚钱。

它固定的实践路线是：

```text
Mac CPU miner
  -> solo.ckpool.org:3333
  -> Bitcoin mainnet Stratum job
  -> sha256d hashing
  -> share / reject / difficulty feedback
  -> 极小概率命中主网块
```

## 目标

- 不跑本机 Bitcoin Core 全节点。
- 不使用交易所地址。
- 不做后台常驻。
- 默认只跑 `1` 线程，并用 duty-cycle 做约 `10%` 平均占用。
- 默认 `300` 秒自动停止。
- 每次真实启动前自动跑 preflight。
- 每次运行写入 `logs/miner-*.log`，App 启动时的 preflight 输出也会写入同一个日志。
- 日志文件名包含时间和进程唯一因子，避免连续启动或 dry-run 覆盖同一秒内的旧日志。
- 默认保留最近 `100` 个 miner 日志，避免长期使用时日志无限增长。
- 启动脚本拒绝项目外 `MINER_BIN`、指向项目外的 `MINER_BIN` symlink、项目外 `LOG_DIR` 和逃逸出 `LOG_DIR` 的 `LOG_FILE`。
- App、preflight 和启动脚本都会做 BTC 地址 checksum / network 校验；`bc1...` 使用 Bech32/Bech32m，`1...` / `3...` 使用 Base58Check。
- Dry-run、命令输出、日志尾部和进程状态显示会脱敏 pool password，不把 `-p` 后面的值写到 UI 或日志输出里。
- 真实启动前会拒绝已有 miner 进程；如果无法读取进程列表，也会 fail-closed 拒绝启动。
- 所有真实地址、worker 名和资源限制都放在本地配置里。

## 快速开始

### 可视化 App

如果只想按按钮操作，用本机 Tauri app：

```bash
npm install
./scripts/bootstrap-cpuminer.sh
npm run verify
npm run package:macos
```

产物：

```text
src-tauri/target/release/bundle/macos/BTC Solo Lab.app
src-tauri/target/release/bundle/dmg/BTC Solo Lab_0.1.0_aarch64.dmg
```

App 提供：

- 配置 BTC 地址、worker、运行时长和 duty-cycle。
- 一键 Preflight。
- 一键 Dry Run。
- 一键 Start / Stop。
- 查看最近日志、进程状态、CKPool 用户统计。
- 中英双语界面，默认中文。

打包后的 App 会把运行所需的脚本、示例配置和 `cpuminer` 二进制初始化到：

```text
~/Library/Application Support/com.local.btcsololab
```

GUI 写入的是这个运行时目录里的 `configs/miner.env`，不是源码目录里的本地 CLI 配置。

本项目默认做本机 ad-hoc 签名，适合自用。若要分发给别人，还需要 Apple Developer ID 签名和 notarization。
打包脚本会自动运行发布审计，确认包内只包含运行时脚本、示例配置和 `cpuminer`，不会把真实 `configs/miner.env` 或开发脚本塞进 `.app`。
公开分发还必须先把 `src-tauri/tauri.conf.json` 里的 `identifier` 从 `com.local.btcsololab` 改成你自己的真实 reverse-DNS 标识。

公开分发包使用：

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE=1 \
NOTARY_KEYCHAIN_PROFILE=btc-solo-lab \
npm run package:macos
```

也可以用 `APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_SPECIFIC_PASSWORD` 代替 `NOTARY_KEYCHAIN_PROFILE`。

### CLI 流程

1. 准备一个自托管 BTC 主网地址，优先 `bc1...`。

2. 复制配置模板：

```bash
cp configs/miner.env.example configs/miner.env
```

3. 编辑 `configs/miner.env`，至少填：

```bash
BTC_ADDRESS=你的BTC主网地址
WORKER_NAME=mac-cpu
```

4. 构建 CPU miner：

```bash
./scripts/bootstrap-cpuminer.sh
```

5. 做启动前检查，不挖矿：

```bash
./scripts/preflight.sh
```

6. 预演真实运行命令，不挖矿：

```bash
DRY_RUN=1 ./scripts/run-solo-miner.sh
```

7. 低资源运行，默认 5 分钟自动停止：

```bash
./scripts/run-solo-miner.sh
```

8. 查看本机进程和最近日志：

```bash
./scripts/status.sh
```

9. 查询 CKPool 统计：

```bash
./scripts/check-ckpool-user.sh
```

10. 标准化 smoke：

```bash
./scripts/smoke-start.sh
```

默认只做 dry smoke，不启动 miner。真实 15 秒主网 CPU smoke 需要显式确认：

```bash
REAL_START_SMOKE=1 \
REAL_START_CONFIRM=REAL_MAINNET_CPU_MINING \
SMOKE_SECONDS=15 \
./scripts/smoke-start.sh
```

## 验收标准

首次 5 到 10 分钟只验收这些：

- 成功连接 Stratum。
- 能收到主网 job。
- 本机有稳定 hashrate。
- 没有持续 reject / disconnect。
- CPU、温度、风扇和系统响应都可接受。

不要把 `accepted share` 或统计页出现作为首次短测的硬性要求。CPU 算力太低，CKPool 官方也说明低 hashrate 可能很久才显示统计。

当前本机推荐配置：

```bash
THREADS=1
THROTTLE_MODE=duty-cycle
DUTY_ACTIVE_SECONDS=1
DUTY_IDLE_SECONDS=9
TIME_LIMIT_SECONDS=300
REQUIRE_AC_POWER=1
LOG_RETENTION=100
```

这台 Mac 是 Apple M1 Max，10 个逻辑 CPU，32GB 内存。实测 `cpulimit` 没有可靠限制住 miner 子进程，曾出现单核 `100%`，所以默认不再依赖它。

## 风险边界

- 这是真实主网 mining，但依赖 CKPool 提供区块模板和转发。
- CKPool 官方当前标注命中区块后收取 `2% fee`。
- Mac CPU 命中主网块的概率可视为接近 0。
- Stratum 明文会暴露 BTC 地址和 worker 名。
- 本机 app 是生产级实验工具，不是生产级收益矿机控制系统。
- 当前默认包是自包含本机包；只有设置 `SIGNING_IDENTITY` 和 `NOTARIZE=1` 并通过 stapler 校验后，才适合公开分发。
- 后续若追求收益，应迁移到 ASIC 矿机和独立电力/散热/网络方案。

完整方案见 [docs/best-practice-plan.md](docs/best-practice-plan.md)。

## 开源定位

BTC Solo Lab 是一个用于真实体验 Bitcoin 主网 solo mining 流程的开源实验工具。项目重点不是收益，而是让开发者在低资源、可观察、可停止、带 preflight 和日志脱敏边界的环境里理解生产网络上的 mining 链路。

## License

This project is licensed under the GNU General Public License version 2 or later. See [LICENSE](LICENSE).

The local `vendor/cpuminer-multi` miner component is cloned from upstream by `scripts/bootstrap-cpuminer.sh` and is licensed by its upstream authors under GPLv2 or later. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
