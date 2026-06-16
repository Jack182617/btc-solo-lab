export type Locale = "zh-CN" | "en-US";

export type Messages = {
  labels: {
    language: string;
    zhCn: string;
    enUs: string;
    mainnet: string;
    running: string;
    idle: string;
    stopped: string;
    none: string;
    noAddress: string;
    boundedRun: (seconds: number) => string;
    dutyCycle: (active: number, idle: number) => string;
    threadProfile: (threads: number, maxThreads: number) => string;
  };
  actions: {
    refresh: string;
    preflight: string;
    dryRun: string;
    start: string;
    stop: string;
    save: string;
    checkCkpool: string;
  };
  sections: {
    runControl: string;
    configuration: string;
    commandOutput: string;
    latestLog: string;
    processState: string;
  };
  metrics: {
    block: string;
    poolDifficulty: string;
    hashrate: string;
    accepted: string;
  };
  fields: {
    btcAddress: string;
    worker: string;
    timeLimit: string;
    activeSeconds: string;
    pausedSeconds: string;
    requireAcPower: string;
    advancedMining: string;
    threads: string;
    allowMultiThread: string;
  };
  empty: {
    commandOutput: string;
    loadingConfig: string;
    noRunLog: string;
    noCpuminer: string;
    processUnavailable: (detail: string) => string;
    previewLog: string;
    desktopRuntimeRequired: string;
  };
  command: {
    exit: string;
    signal: string;
    ok: string;
    failed: string;
  };
  titles: {
    refresh: string;
    preflight: string;
    dryRun: string;
    start: string;
    stop: string;
    save: string;
    checkCkpool: string;
  };
};

export const messages: Record<Locale, Messages> = {
  "zh-CN": {
    labels: {
      language: "语言",
      zhCn: "中文",
      enUs: "English",
      mainnet: "主网",
      running: "运行中",
      idle: "空闲",
      stopped: "已停止",
      none: "无",
      noAddress: "未配置地址",
      boundedRun: (seconds) => `限时运行 ${seconds}s`,
      dutyCycle: (active, idle) => `${active}s 运行 / ${idle}s 暂停`,
      threadProfile: (threads, maxThreads) => `${threads}/${maxThreads} 线程`
    },
    actions: {
      refresh: "刷新",
      preflight: "预检",
      dryRun: "预演命令",
      start: "开始",
      stop: "停止",
      save: "保存",
      checkCkpool: "查询 CKPool"
    },
    sections: {
      runControl: "运行控制",
      configuration: "配置",
      commandOutput: "命令输出",
      latestLog: "最近日志",
      processState: "进程状态"
    },
    metrics: {
      block: "区块",
      poolDifficulty: "池难度",
      hashrate: "算力",
      accepted: "已接受"
    },
    fields: {
      btcAddress: "BTC 地址",
      worker: "Worker 名",
      timeLimit: "运行时长（秒）",
      activeSeconds: "运行秒数",
      pausedSeconds: "暂停秒数",
      requireAcPower: "要求接入电源",
      advancedMining: "高级算力",
      threads: "线程数",
      allowMultiThread: "允许多线程"
    },
    empty: {
      commandOutput: "暂无命令输出。",
      loadingConfig: "正在读取配置",
      noRunLog: "暂无运行日志。",
      noCpuminer: "未发现 cpuminer 进程。",
      processUnavailable: (detail) => `无法读取进程列表：${detail}`,
      previewLog: "浏览器预览没有 Tauri 后端；打包后的桌面 App 会使用 Rust 命令层。",
      desktopRuntimeRequired: "此操作需要在 Tauri 桌面 App 中运行。"
    },
    command: {
      exit: "退出码",
      signal: "信号",
      ok: "成功",
      failed: "失败"
    },
    titles: {
      refresh: "刷新状态",
      preflight: "运行启动前检查",
      dryRun: "预演真实运行命令，不启动矿工",
      start: "开始一次限时运行",
      stop: "停止矿工",
      save: "保存配置",
      checkCkpool: "查询 CKPool 用户统计"
    }
  },
  "en-US": {
    labels: {
      language: "Language",
      zhCn: "中文",
      enUs: "English",
      mainnet: "mainnet",
      running: "running",
      idle: "idle",
      stopped: "stopped",
      none: "none",
      noAddress: "no address",
      boundedRun: (seconds) => `${seconds}s bounded run`,
      dutyCycle: (active, idle) => `${active}s active / ${idle}s paused`,
      threadProfile: (threads, maxThreads) => `${threads}/${maxThreads} threads`
    },
    actions: {
      refresh: "Refresh",
      preflight: "Preflight",
      dryRun: "Dry Run",
      start: "Start",
      stop: "Stop",
      save: "Save",
      checkCkpool: "Check CKPool"
    },
    sections: {
      runControl: "Run Control",
      configuration: "Configuration",
      commandOutput: "Command Output",
      latestLog: "Latest Log",
      processState: "Process State"
    },
    metrics: {
      block: "Block",
      poolDifficulty: "Pool difficulty",
      hashrate: "Hashrate",
      accepted: "Accepted"
    },
    fields: {
      btcAddress: "BTC address",
      worker: "Worker",
      timeLimit: "Time limit (seconds)",
      activeSeconds: "Active seconds",
      pausedSeconds: "Paused seconds",
      requireAcPower: "Require AC power",
      advancedMining: "Advanced mining",
      threads: "Threads",
      allowMultiThread: "Allow multi-thread"
    },
    empty: {
      commandOutput: "No command output yet.",
      loadingConfig: "Loading config",
      noRunLog: "No run log yet.",
      noCpuminer: "No cpuminer process found.",
      processUnavailable: (detail) => `Process list unavailable: ${detail}`,
      previewLog: "The browser preview has no Tauri backend. The packaged desktop app uses the Rust command layer.",
      desktopRuntimeRequired: "This action requires the Tauri desktop app."
    },
    command: {
      exit: "exit code",
      signal: "signal",
      ok: "ok",
      failed: "failed"
    },
    titles: {
      refresh: "Refresh status",
      preflight: "Run preflight",
      dryRun: "Dry run without starting the miner",
      start: "Start a bounded run",
      stop: "Stop miner",
      save: "Save config",
      checkCkpool: "Check CKPool"
    }
  }
};

export function readInitialLocale(): Locale {
  if (typeof window === "undefined") return "zh-CN";
  const stored = window.localStorage.getItem("btc-solo-lab-locale");
  return stored === "en-US" || stored === "zh-CN" ? stored : "zh-CN";
}
