import { invoke } from "@tauri-apps/api/core";

export type ConfigView = {
  btc_address: string;
  address_preview: string;
  worker_name: string;
  pool_host: string;
  pool_port: string;
  algo: string;
  threads: number;
  max_threads: number;
  throttle_mode: string;
  duty_active_seconds: number;
  duty_idle_seconds: number;
  time_limit_seconds: number | null;
  require_ac_power: boolean;
  allow_unlimited_run: boolean;
  allow_multi_thread: boolean;
  cpuminer_ref: string;
  miner_bin: string;
  config_path: string;
};

export type ConfigUpdate = {
  btc_address: string;
  worker_name: string;
  threads: number;
  throttle_mode: string;
  duty_active_seconds: number;
  duty_idle_seconds: number;
  time_limit_seconds: number | null;
  require_ac_power: boolean;
  allow_multi_thread: boolean;
};

export type CommandResult = {
  ok: boolean;
  code: number | null;
  stdout: string;
  stderr: string;
};

export type MinerStatus = {
  running: boolean;
  pid: number | null;
  started_at: number | null;
  log_file: string | null;
  processes: string[];
  process_error: string | null;
  latest_log_file: string | null;
  latest_log_tail: string;
};

export type Dashboard = {
  config: ConfigView;
  status: MinerStatus;
};

export type StartResult = {
  running: boolean;
  pid: number;
  log_file: string;
  started_at: number;
};

export const PREVIEW_LOG_MARKER = "__BTC_SOLO_LAB_BROWSER_PREVIEW__";
export const PREVIEW_RUNTIME_REQUIRED_MARKER = "__BTC_SOLO_LAB_TAURI_REQUIRED__";

const hasTauri = () =>
  typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

const previewConfig: ConfigView = {
  btc_address: "bc1qexamplepreviewaddress000000000000000000",
  address_preview: "bc1qexam...000000",
  worker_name: "mac-cpu",
  pool_host: "solo.ckpool.org",
  pool_port: "3333",
  algo: "sha256d",
  threads: 1,
  max_threads: 10,
  throttle_mode: "duty-cycle",
  duty_active_seconds: 1,
  duty_idle_seconds: 9,
  time_limit_seconds: 300,
  require_ac_power: true,
  allow_unlimited_run: false,
  allow_multi_thread: false,
  cpuminer_ref: "d2927ed23b1d0eacd067c320fce64e6610737adb",
  miner_bin: "vendor/cpuminer-multi/cpuminer",
  config_path: "configs/miner.env"
};

const previewStatus: MinerStatus = {
  running: false,
  pid: null,
  started_at: null,
  log_file: null,
  processes: [],
  process_error: null,
  latest_log_file: null,
  latest_log_tail: PREVIEW_LOG_MARKER
};

const previewCommand = (): CommandResult => ({
  ok: false,
  code: null,
  stdout: PREVIEW_RUNTIME_REQUIRED_MARKER,
  stderr: ""
});

export const api = {
  dashboard: () =>
    hasTauri()
      ? invoke<Dashboard>("get_dashboard")
      : Promise.resolve({ config: previewConfig, status: previewStatus }),
  saveConfig: (update: ConfigUpdate) =>
    hasTauri()
      ? invoke<ConfigView>("save_config", { update })
      : Promise.resolve({ ...previewConfig, ...update, address_preview: "preview" }),
  preflight: () =>
    hasTauri()
      ? invoke<CommandResult>("run_preflight")
      : Promise.resolve(previewCommand()),
  dryRun: () =>
    hasTauri()
      ? invoke<CommandResult>("dry_run")
      : Promise.resolve(previewCommand()),
  checkCkpool: () =>
    hasTauri()
      ? invoke<CommandResult>("check_ckpool")
      : Promise.resolve(previewCommand()),
  status: () =>
    hasTauri() ? invoke<MinerStatus>("get_status") : Promise.resolve(previewStatus),
  readLatestLog: (maxLines = 160) =>
    hasTauri()
      ? invoke<string>("read_latest_log", { maxLines })
      : Promise.resolve(previewStatus.latest_log_tail),
  start: (timeLimitSeconds?: number) =>
    hasTauri()
      ? invoke<StartResult>("start_mining", { timeLimitSeconds })
      : Promise.resolve({
          running: false,
          pid: 0,
          log_file: "preview",
          started_at: Math.floor(Date.now() / 1000)
        }),
  stop: () =>
    hasTauri() ? invoke<MinerStatus>("stop_mining") : Promise.resolve(previewStatus)
};
