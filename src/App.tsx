import {
  Activity,
  BadgeCheck,
  Bitcoin,
  Clock3,
  Cpu,
  FileText,
  PauseCircle,
  Play,
  Power,
  RefreshCw,
  Save,
  Search,
  ShieldCheck,
  Square,
  Terminal,
  Wifi
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  api,
  CommandResult,
  ConfigUpdate,
  ConfigView,
  Dashboard,
  MinerStatus,
  PREVIEW_LOG_MARKER,
  PREVIEW_RUNTIME_REQUIRED_MARKER
} from "./api";
import { Locale, messages, readInitialLocale } from "./i18n";

type FormState = {
  btc_address: string;
  worker_name: string;
  threads: string;
  duty_active_seconds: string;
  duty_idle_seconds: string;
  time_limit_seconds: string;
  require_ac_power: boolean;
  allow_multi_thread: boolean;
};

type MetricSummary = {
  difficulty: string;
  block: string;
  hashrate: string;
  accepted: number;
  rejected: number;
  disconnected: number;
};

const emptyMetrics: MetricSummary = {
  difficulty: "none",
  block: "none",
  hashrate: "none",
  accepted: 0,
  rejected: 0,
  disconnected: 0
};

function hashrateToHashes(value: string, unit: string): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  const prefix = unit.trim().charAt(0).toUpperCase();
  const multiplier =
    prefix === "T" ? 1e12 : prefix === "G" ? 1e9 : prefix === "M" ? 1e6 : prefix === "K" ? 1e3 : 1;
  return parsed * multiplier;
}

function formatHashrateValue(hashesPerSecond: number): string {
  if (!Number.isFinite(hashesPerSecond) || hashesPerSecond <= 0) return "none";
  const units = [
    ["TH/s", 1e12],
    ["GH/s", 1e9],
    ["MH/s", 1e6],
    ["kH/s", 1e3]
  ] as const;
  for (const [unit, divisor] of units) {
    if (hashesPerSecond >= divisor) {
      return `${(hashesPerSecond / divisor).toFixed(2)} ${unit}`;
    }
  }
  return `${hashesPerSecond.toFixed(2)} H/s`;
}

function formFromConfig(config: ConfigView): FormState {
  return {
    btc_address: config.btc_address,
    worker_name: config.worker_name,
    threads: String(config.threads),
    duty_active_seconds: String(config.duty_active_seconds),
    duty_idle_seconds: String(config.duty_idle_seconds),
    time_limit_seconds: String(config.time_limit_seconds ?? 300),
    require_ac_power: config.require_ac_power,
    allow_multi_thread: config.allow_multi_thread
  };
}

function updateFromForm(form: FormState): ConfigUpdate {
  return {
    btc_address: form.btc_address.trim(),
    worker_name: form.worker_name.trim(),
    threads: Number(form.threads),
    throttle_mode: "duty-cycle",
    duty_active_seconds: Number(form.duty_active_seconds),
    duty_idle_seconds: Number(form.duty_idle_seconds),
    time_limit_seconds: numberOrNull(form.time_limit_seconds),
    require_ac_power: form.require_ac_power,
    allow_multi_thread: form.allow_multi_thread
  };
}

function parseMetrics(log: string): MetricSummary {
  if (!log.trim()) return emptyMetrics;
  const lines = log.split("\n");
  let difficulty = "none";
  let block = "none";
  let hashrate = "none";
  let accepted = 0;
  let rejected = 0;
  let disconnected = 0;
  const cpuHashrates = new Map<string, number>();

  for (const line of lines) {
    const difficultyMatch = line.match(/Stratum difficulty set to ([^\s]+)/);
    if (difficultyMatch) difficulty = difficultyMatch[1];

    const blockMatch = line.match(/sha256d block ([0-9]+)/);
    if (blockMatch) block = blockMatch[1];

    const hashMatch = line.match(/CPU #(\d+):\s+([0-9.]+)\s*([kMGT]?H\/s)/i);
    if (hashMatch) {
      cpuHashrates.set(hashMatch[1], hashrateToHashes(hashMatch[2], hashMatch[3]));
    }

    if (/accepted/i.test(line)) accepted += 1;
    if (/reject/i.test(line)) rejected += 1;
    if (/disconnect|connection failed|stratum_recv_line failed/i.test(line)) disconnected += 1;
  }

  if (cpuHashrates.size > 0) {
    hashrate = formatHashrateValue(
      [...cpuHashrates.values()].reduce((sum, value) => sum + value, 0)
    );
  }

  return { difficulty, block, hashrate, accepted, rejected, disconnected };
}

function formatCommand(result: CommandResult | null, t: typeof messages["zh-CN"]): string {
  if (!result) return t.empty.commandOutput;
  const stdout =
    result.stdout.trim() === PREVIEW_RUNTIME_REQUIRED_MARKER
      ? t.empty.desktopRuntimeRequired
      : result.stdout.trim();
  const parts = [
    `${t.command.exit}: ${result.code ?? t.command.signal} ${
      result.ok ? t.command.ok : t.command.failed
    }`,
    stdout,
    result.stderr.trim()
  ].filter(Boolean);
  return parts.join("\n\n");
}

function numberOrNull(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : null;
}

function SectionTitle({
  icon,
  title,
  aside
}: {
  icon: React.ReactNode;
  title: string;
  aside?: React.ReactNode;
}) {
  return (
    <div className="section-title">
      <div className="section-title-main">
        {icon}
        <h2>{title}</h2>
      </div>
      {aside}
    </div>
  );
}

function StatusPill({ ok, label }: { ok: boolean; label: string }) {
  return <span className={ok ? "pill pill-ok" : "pill pill-warn"}>{label}</span>;
}

export default function App() {
  const [locale, setLocale] = useState<Locale>(() => readInitialLocale());
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);
  const [form, setForm] = useState<FormState | null>(null);
  const [commandOutput, setCommandOutput] = useState<CommandResult | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [backendError, setBackendError] = useState<string | null>(null);
  const t = messages[locale];

  const status: MinerStatus | null = dashboard?.status ?? null;
  const config: ConfigView | null = dashboard?.config ?? null;
  const latestLogTail =
    status?.latest_log_tail === PREVIEW_LOG_MARKER
      ? t.empty.previewLog
      : status?.latest_log_tail;
  const metrics = useMemo(
    () => parseMetrics(status?.latest_log_tail ?? ""),
    [status?.latest_log_tail]
  );
  const pendingUpdate = useMemo(() => (form ? updateFromForm(form) : null), [form]);
  const hasUnsavedConfig = useMemo(() => {
    if (!config || !pendingUpdate) return false;
    return (
      pendingUpdate.btc_address !== config.btc_address ||
      pendingUpdate.worker_name !== config.worker_name ||
      pendingUpdate.threads !== config.threads ||
      pendingUpdate.duty_active_seconds !== config.duty_active_seconds ||
      pendingUpdate.duty_idle_seconds !== config.duty_idle_seconds ||
      pendingUpdate.time_limit_seconds !== config.time_limit_seconds ||
      pendingUpdate.require_ac_power !== config.require_ac_power ||
      pendingUpdate.allow_multi_thread !== config.allow_multi_thread
    );
  }, [config, pendingUpdate]);

  const loadDashboard = useCallback(async () => {
    try {
      const data = await api.dashboard();
      setDashboard(data);
      setForm((current) => current ?? formFromConfig(data.config));
      setBackendError(null);
    } catch (error) {
      setBackendError(error instanceof Error ? error.message : String(error));
    }
  }, []);

  useEffect(() => {
    void loadDashboard();
    const timer = window.setInterval(() => {
      void loadDashboard();
    }, 3000);
    return () => window.clearInterval(timer);
  }, [loadDashboard]);

  useEffect(() => {
    document.documentElement.lang = locale;
    window.localStorage.setItem("btc-solo-lab-locale", locale);
  }, [locale]);

  const runAction = async (name: string, action: () => Promise<unknown>) => {
    setBusy(name);
    try {
      const result = await action();
      if (
        result &&
        typeof result === "object" &&
        "stdout" in result &&
        "stderr" in result
      ) {
        setCommandOutput(result as CommandResult);
      }
      await loadDashboard();
      setBackendError(null);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setBackendError(message.split("\n")[0]);
      setCommandOutput({
        ok: false,
        code: null,
        stdout: "",
        stderr: message
      });
    } finally {
      setBusy(null);
    }
  };

  const save = async () => {
    if (!form) return;
    await runAction("save", async () => {
      const saved = await api.saveConfig(updateFromForm(form));
      setForm(formFromConfig(saved));
      return null;
    });
  };

  const start = async () => {
    await runAction("start", async () => {
      let activeConfig = config;
      if (form && hasUnsavedConfig) {
        activeConfig = await api.saveConfig(updateFromForm(form));
        setForm(formFromConfig(activeConfig));
      }
      const seconds =
        numberOrNull(form?.time_limit_seconds ?? "") ??
        activeConfig?.time_limit_seconds ??
        300;
      return api.start(seconds);
    });
  };

  const stop = async () => runAction("stop", () => api.stop());

  const buttonDisabled = () => Boolean(busy);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand-block">
          <div className="brand-mark">
            <Bitcoin size={26} aria-hidden />
          </div>
          <div>
            <h1>BTC Solo Lab</h1>
            <div className="subline">
              <StatusPill ok label={t.labels.mainnet} />
              <StatusPill ok label="CKPool" />
              <StatusPill ok={status?.running ?? false} label={status?.running ? t.labels.running : t.labels.idle} />
            </div>
          </div>
        </div>
        <div className="top-actions">
          <label className="language-select">
            <span>{t.labels.language}</span>
            <select
              value={locale}
              onChange={(event) => setLocale(event.target.value as Locale)}
              aria-label={t.labels.language}
            >
              <option value="zh-CN">{t.labels.zhCn}</option>
              <option value="en-US">{t.labels.enUs}</option>
            </select>
          </label>
          <button
            className="icon-button"
            title={t.titles.refresh}
            onClick={() => void loadDashboard()}
            disabled={buttonDisabled()}
          >
            <RefreshCw size={18} />
          </button>
        </div>
      </header>

      {backendError ? (
        <div className="banner banner-error">
          <Terminal size={18} />
          <span>{backendError}</span>
        </div>
      ) : null}

      <section className="grid">
        <section className="panel run-panel">
          <SectionTitle
            icon={<Power size={18} />}
            title={t.sections.runControl}
            aside={<StatusPill ok={Boolean(status?.running)} label={status?.running ? `pid ${status.pid}` : t.labels.stopped} />}
          />
          <div className="control-grid">
            <button
              className="command-button"
              onClick={() => runAction("preflight", api.preflight)}
              disabled={buttonDisabled() || status?.running}
              title={t.titles.preflight}
            >
              <ShieldCheck size={18} />
              <span>{t.actions.preflight}</span>
            </button>
            <button
              className="command-button"
              onClick={() => runAction("dry", api.dryRun)}
              disabled={buttonDisabled() || status?.running}
              title={t.titles.dryRun}
            >
              <Terminal size={18} />
              <span>{t.actions.dryRun}</span>
            </button>
            <button
              className="command-button primary"
              onClick={() => void start()}
              disabled={buttonDisabled() || status?.running}
              title={t.titles.start}
            >
              <Play size={18} />
              <span>{t.actions.start}</span>
            </button>
            <button
              className="command-button danger"
              onClick={() => void stop()}
              disabled={buttonDisabled() || !status?.running}
              title={t.titles.stop}
            >
              <Square size={18} />
              <span>{t.actions.stop}</span>
            </button>
          </div>

          <div className="stat-grid">
            <div className="stat">
              <span>{t.metrics.block}</span>
              <strong>{metrics.block === "none" ? t.labels.none : metrics.block}</strong>
            </div>
            <div className="stat">
              <span>{t.metrics.poolDifficulty}</span>
              <strong>{metrics.difficulty === "none" ? t.labels.none : metrics.difficulty}</strong>
            </div>
            <div className="stat">
              <span>{t.metrics.hashrate}</span>
              <strong>{metrics.hashrate === "none" ? t.labels.none : metrics.hashrate}</strong>
            </div>
            <div className="stat">
              <span>{t.metrics.accepted}</span>
              <strong>{metrics.accepted}</strong>
            </div>
          </div>

          <div className="status-list">
            <div>
              <BadgeCheck size={16} />
              <span>{config?.address_preview ?? t.labels.noAddress}</span>
            </div>
            <div>
              <Clock3 size={16} />
              <span>{t.labels.boundedRun(config?.time_limit_seconds ?? 300)}</span>
            </div>
            <div>
              <PauseCircle size={16} />
              <span>
                {t.labels.dutyCycle(config?.duty_active_seconds ?? 1, config?.duty_idle_seconds ?? 9)}
              </span>
            </div>
            <div>
              <Cpu size={16} />
              <span>{t.labels.threadProfile(config?.threads ?? 1, config?.max_threads ?? 1)}</span>
            </div>
            <div>
              <Wifi size={16} />
              <span>{config?.pool_host ?? "solo.ckpool.org"}:{config?.pool_port ?? "3333"}</span>
            </div>
          </div>
        </section>

        <section className="panel config-panel">
          <SectionTitle icon={<ShieldCheck size={18} />} title={t.sections.configuration} />
          {form ? (
            <div className="form-grid">
              <label className="field field-wide">
                <span>{t.fields.btcAddress}</span>
                <input
                  value={form.btc_address}
                  onChange={(event) => setForm({ ...form, btc_address: event.target.value })}
                  spellCheck={false}
                />
              </label>
              <label className="field">
                <span>{t.fields.worker}</span>
                <input
                  value={form.worker_name}
                  onChange={(event) => setForm({ ...form, worker_name: event.target.value })}
                  spellCheck={false}
                />
              </label>
              <label className="field">
                <span>{t.fields.timeLimit}</span>
                <input
                  type="number"
                  min={1}
                  max={3600}
                  value={form.time_limit_seconds}
                  onChange={(event) =>
                    setForm({ ...form, time_limit_seconds: event.target.value })
                  }
                />
              </label>
              <label className="field">
                <span>{t.fields.activeSeconds}</span>
                <input
                  type="number"
                  min={1}
                  max={60}
                  value={form.duty_active_seconds}
                  onChange={(event) =>
                    setForm({ ...form, duty_active_seconds: event.target.value })
                  }
                />
              </label>
              <label className="field">
                <span>{t.fields.pausedSeconds}</span>
                <input
                  type="number"
                  min={0}
                  max={60}
                  value={form.duty_idle_seconds}
                  onChange={(event) =>
                    setForm({ ...form, duty_idle_seconds: event.target.value })
                  }
                />
              </label>
              <label className="toggle-row">
                <input
                  type="checkbox"
                  checked={form.require_ac_power}
                  onChange={(event) =>
                    setForm({ ...form, require_ac_power: event.target.checked })
                  }
                />
                <span>{t.fields.requireAcPower}</span>
              </label>
              <details className="advanced-config field-wide">
                <summary>
                  <Cpu size={16} />
                  <span>{t.fields.advancedMining}</span>
                </summary>
                <div className="advanced-grid">
                  <label className="toggle-row">
                    <input
                      type="checkbox"
                      checked={form.allow_multi_thread}
                      onChange={(event) =>
                        setForm({
                          ...form,
                          allow_multi_thread: event.target.checked,
                          threads: event.target.checked ? form.threads : "1"
                        })
                      }
                    />
                    <span>{t.fields.allowMultiThread}</span>
                  </label>
                  <label className="field">
                    <span>{t.fields.threads}</span>
                    <input
                      type="number"
                      min={1}
                      max={config?.max_threads ?? 1}
                      value={form.threads}
                      disabled={!form.allow_multi_thread}
                      onChange={(event) =>
                        setForm({ ...form, threads: event.target.value })
                      }
                    />
                  </label>
                </div>
              </details>
              <button
                className="command-button save-button"
                onClick={() => void save()}
                disabled={buttonDisabled() || status?.running}
                title={t.titles.save}
              >
                <Save size={18} />
                <span>{t.actions.save}</span>
              </button>
            </div>
          ) : (
            <div className="empty">{t.empty.loadingConfig}</div>
          )}
        </section>

        <section className="panel output-panel">
          <SectionTitle
            icon={<Terminal size={18} />}
            title={t.sections.commandOutput}
            aside={
              <button
                className="inline-button"
                onClick={() => runAction("pool", api.checkCkpool)}
                disabled={buttonDisabled()}
                title={t.titles.checkCkpool}
              >
                <Search size={16} />
                <span>{t.actions.checkCkpool}</span>
              </button>
            }
          />
          <pre className="terminal">{formatCommand(commandOutput, t)}</pre>
        </section>

        <section className="panel log-panel">
          <SectionTitle
            icon={<FileText size={18} />}
            title={t.sections.latestLog}
            aside={<span className="path-label">{status?.latest_log_file ?? t.labels.none}</span>}
          />
          <pre className="terminal log-view">
            {latestLogTail?.trim() || t.empty.noRunLog}
          </pre>
        </section>

        <section className="panel process-panel">
          <SectionTitle icon={<Activity size={18} />} title={t.sections.processState} />
          <pre className="terminal process-view">
            {status?.process_error
              ? t.empty.processUnavailable(status.process_error)
              : status?.processes.length
              ? status.processes.join("\n")
              : t.empty.noCpuminer}
          </pre>
        </section>
      </section>
    </main>
  );
}
