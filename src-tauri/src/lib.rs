use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, VecDeque},
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{Mutex, OnceLock},
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::Manager;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

struct ManagedRun {
    child: Child,
    log_file: PathBuf,
    started_at: u64,
}

impl Drop for ManagedRun {
    fn drop(&mut self) {
        terminate_child(&mut self.child);
    }
}

#[derive(Default)]
struct AppState {
    run: Mutex<Option<ManagedRun>>,
}

#[derive(Clone)]
struct RuntimePaths {
    root: PathBuf,
}

static RUNTIME_PATHS: OnceLock<RuntimePaths> = OnceLock::new();

const MINER_ENV_KEYS: &[&str] = &[
    "BTC_ADDRESS",
    "WORKER_NAME",
    "POOL_HOST",
    "POOL_PORT",
    "POOL_PASSWORD",
    "ALGO",
    "THREADS",
    "CPULIMIT_PERCENT",
    "CPULIMIT_INCLUDE_CHILDREN",
    "NICE_LEVEL",
    "REQUIRE_AC_POWER",
    "REQUIRE_PREFLIGHT",
    "ALLOW_UNLIMITED_RUN",
    "ALLOW_MULTI_THREAD",
    "THROTTLE_MODE",
    "DUTY_ACTIVE_SECONDS",
    "DUTY_IDLE_SECONDS",
    "TIME_LIMIT_SECONDS",
    "LOG_DIR",
    "LOG_RETENTION",
    "LOG_FILE",
    "DRY_RUN",
    "MINER_BIN",
    "CPUMINER_REF",
    "MINER_DIR",
    "CPUMINER_REPO",
    "BUILD_JOBS",
];

const PACKAGED_RUNTIME_SCRIPTS: &[&str] = &[
    "check-ckpool-user.sh",
    "preflight.sh",
    "run-solo-miner.sh",
    "smoke-start.sh",
    "status.sh",
];

#[derive(Debug, Clone, Serialize)]
struct ConfigView {
    btc_address: String,
    address_preview: String,
    worker_name: String,
    pool_host: String,
    pool_port: String,
    algo: String,
    threads: u32,
    max_threads: u32,
    throttle_mode: String,
    duty_active_seconds: u64,
    duty_idle_seconds: u64,
    time_limit_seconds: Option<u64>,
    require_ac_power: bool,
    allow_unlimited_run: bool,
    allow_multi_thread: bool,
    cpuminer_ref: String,
    miner_bin: String,
    config_path: String,
}

#[derive(Debug, Clone, Deserialize)]
struct ConfigUpdate {
    btc_address: String,
    worker_name: String,
    threads: u32,
    throttle_mode: String,
    duty_active_seconds: u64,
    duty_idle_seconds: u64,
    time_limit_seconds: Option<u64>,
    require_ac_power: bool,
    allow_multi_thread: bool,
}

#[derive(Debug, Clone, Serialize)]
struct CommandResult {
    ok: bool,
    code: Option<i32>,
    stdout: String,
    stderr: String,
}

#[derive(Debug, Clone, Serialize)]
struct StartResult {
    running: bool,
    pid: u32,
    log_file: String,
    started_at: u64,
}

#[derive(Debug, Clone, Serialize)]
struct MinerStatus {
    running: bool,
    pid: Option<u32>,
    started_at: Option<u64>,
    log_file: Option<String>,
    processes: Vec<String>,
    process_error: Option<String>,
    latest_log_file: Option<String>,
    latest_log_tail: String,
}

#[derive(Debug, Clone, Serialize)]
struct Dashboard {
    config: ConfigView,
    status: MinerStatus,
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn now_unix_nanos() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
}

fn source_project_root() -> Result<PathBuf, String> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .map(Path::to_path_buf)
        .ok_or_else(|| "cannot resolve project root".to_string())
}

fn runtime_paths() -> Result<RuntimePaths, String> {
    if let Some(paths) = RUNTIME_PATHS.get() {
        return Ok(paths.clone());
    }
    Ok(RuntimePaths {
        root: source_project_root()?,
    })
}

fn project_root() -> Result<PathBuf, String> {
    Ok(runtime_paths()?.root)
}

fn config_path() -> Result<PathBuf, String> {
    Ok(project_root()?.join("configs/miner.env"))
}

fn copy_runtime_file(source: &Path, destination: &Path) -> Result<(), String> {
    let parent = destination
        .parent()
        .ok_or_else(|| format!("runtime file has no parent: {}", destination.display()))?;
    fs::create_dir_all(parent).map_err(|err| format!("failed to create runtime dir: {err}"))?;
    fs::copy(source, destination).map_err(|err| {
        format!(
            "failed to copy runtime file {} -> {}: {err}",
            source.display(),
            destination.display()
        )
    })?;
    Ok(())
}

fn copy_runtime_dir(source: &Path, destination: &Path) -> Result<(), String> {
    fs::create_dir_all(destination)
        .map_err(|err| format!("failed to create runtime dir: {err}"))?;
    for entry in
        fs::read_dir(source).map_err(|err| format!("failed to read runtime resource: {err}"))?
    {
        let entry = entry.map_err(|err| format!("failed to read runtime resource: {err}"))?;
        let source_path = entry.path();
        let destination_path = destination.join(entry.file_name());
        if source_path.is_dir() {
            copy_runtime_dir(&source_path, &destination_path)?;
        } else {
            copy_runtime_file(&source_path, &destination_path)?;
        }
    }
    Ok(())
}

fn replace_runtime_dir(source: &Path, destination: &Path) -> Result<(), String> {
    if destination.exists() {
        fs::remove_dir_all(destination)
            .map_err(|err| format!("failed to remove stale runtime dir: {err}"))?;
    }
    copy_runtime_dir(source, destination)
}

#[cfg(unix)]
fn set_executable(path: &Path) -> Result<(), String> {
    fs::set_permissions(path, fs::Permissions::from_mode(0o755))
        .map_err(|err| format!("failed to set executable bit on {}: {err}", path.display()))
}

#[cfg(not(unix))]
fn set_executable(_path: &Path) -> Result<(), String> {
    Ok(())
}

fn seed_packaged_runtime(resource_dir: &Path, app_data_dir: &Path) -> Result<RuntimePaths, String> {
    let resource_runtime = resource_dir.join("runtime");
    if !resource_runtime.exists() {
        return Ok(RuntimePaths {
            root: source_project_root()?,
        });
    }

    fs::create_dir_all(app_data_dir)
        .map_err(|err| format!("failed to create app data dir: {err}"))?;
    replace_runtime_dir(
        &resource_runtime.join("scripts"),
        &app_data_dir.join("scripts"),
    )?;
    copy_runtime_file(
        &resource_runtime.join("configs/miner.env.example"),
        &app_data_dir.join("configs/miner.env.example"),
    )?;
    copy_runtime_file(
        &resource_runtime.join("vendor/cpuminer-multi/cpuminer"),
        &app_data_dir.join("vendor/cpuminer-multi/cpuminer"),
    )?;

    for script in PACKAGED_RUNTIME_SCRIPTS {
        set_executable(&app_data_dir.join("scripts").join(script))?;
    }
    set_executable(&app_data_dir.join("vendor/cpuminer-multi/cpuminer"))?;

    let config_path = app_data_dir.join("configs/miner.env");
    if !config_path.exists() {
        copy_runtime_file(
            &resource_runtime.join("configs/miner.env.example"),
            &config_path,
        )?;
        #[cfg(unix)]
        fs::set_permissions(&config_path, fs::Permissions::from_mode(0o600))
            .map_err(|err| format!("failed to set config permissions: {err}"))?;
    }

    Ok(RuntimePaths {
        root: app_data_dir.to_path_buf(),
    })
}

fn script_path(name: &str) -> Result<PathBuf, String> {
    let allowed = [
        "preflight.sh",
        "run-solo-miner.sh",
        "check-ckpool-user.sh",
        "status.sh",
    ];
    if !allowed.contains(&name) {
        return Err("script is not allowed".to_string());
    }
    Ok(project_root()?.join("scripts").join(name))
}

fn safe_script_path() -> &'static str {
    "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}

fn script_command(name: &str) -> Result<Command, String> {
    let root = project_root()?;
    let script = script_path(name)?;
    let mut command = Command::new("/bin/bash");
    command
        .arg(script)
        .current_dir(root)
        .env_clear()
        .env("PATH", safe_script_path())
        .env("ENV_FILE", config_path()?);
    if let Some(home) = std::env::var_os("HOME") {
        command.env("HOME", home);
    }
    if let Some(tmpdir) = std::env::var_os("TMPDIR") {
        command.env("TMPDIR", tmpdir);
    }
    Ok(command)
}

fn resolve_project_path(path: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(path);
    if path.is_absolute() {
        Ok(path)
    } else {
        Ok(project_root()?.join(path))
    }
}

fn require_path_under_project_root(label: &str, path: &Path) -> Result<(), String> {
    let root = project_root()?
        .canonicalize()
        .map_err(|err| format!("failed to resolve project root: {err}"))?;
    let mut probe = if path.exists() {
        path.to_path_buf()
    } else {
        path.parent()
            .map(Path::to_path_buf)
            .ok_or_else(|| format!("{label} has no parent directory: {}", path.display()))?
    };
    while !probe.exists() {
        probe = probe.parent().map(Path::to_path_buf).ok_or_else(|| {
            format!(
                "{label} parent directory does not exist: {}",
                path.display()
            )
        })?;
    }
    let resolved = probe
        .canonicalize()
        .map_err(|err| format!("failed to resolve {label}: {err}"))?;
    if resolved == root || resolved.starts_with(&root) {
        Ok(())
    } else {
        Err(format!(
            "{label} must stay inside project root: {}",
            path.display()
        ))
    }
}

fn configured_logs_dir_from_map(map: &BTreeMap<String, String>) -> Result<PathBuf, String> {
    let dir = resolve_project_path(map.get("LOG_DIR").map(String::as_str).unwrap_or("logs"))?;
    require_path_under_project_root("LOG_DIR", &dir)?;
    Ok(dir)
}

fn configured_logs_dir() -> Result<PathBuf, String> {
    let path = config_path()?;
    let map = read_env_file(&path)?;
    configured_logs_dir_from_map(&map)
}

fn configured_miner_bin_from_map(map: &BTreeMap<String, String>) -> Result<PathBuf, String> {
    let miner_bin = resolve_project_path(
        map.get("MINER_BIN")
            .map(String::as_str)
            .unwrap_or("vendor/cpuminer-multi/cpuminer"),
    )?;
    require_path_under_project_root("MINER_BIN", &miner_bin)?;
    Ok(miner_bin)
}

fn read_env_file(path: &Path) -> Result<BTreeMap<String, String>, String> {
    let content =
        fs::read_to_string(path).map_err(|err| format!("failed to read config: {err}"))?;
    let mut map = BTreeMap::new();
    for line in content.lines() {
        let mut trimmed = line.trim().trim_end_matches('\r');
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(exported) = trimmed.strip_prefix("export ") {
            trimmed = exported.trim_start();
        }
        let Some((key, value)) = trimmed.split_once('=') else {
            return Err(format!(
                "invalid config line in {}: {trimmed}",
                path.display()
            ));
        };
        let key = key.trim();
        if key.is_empty()
            || !key
                .chars()
                .all(|ch| ch.is_ascii_uppercase() || ch.is_ascii_digit() || ch == '_')
        {
            return Err(format!("invalid config key in {}: {key}", path.display()));
        }
        if !MINER_ENV_KEYS.contains(&key) {
            return Err(format!("unknown config key in {}: {key}", path.display()));
        }
        map.insert(key.to_string(), value.trim().to_string());
    }
    Ok(map)
}

fn env_bool(map: &BTreeMap<String, String>, key: &str, default: bool) -> bool {
    map.get(key)
        .map(|value| value == "1" || value.eq_ignore_ascii_case("true"))
        .unwrap_or(default)
}

fn env_u64(map: &BTreeMap<String, String>, key: &str, default: u64) -> u64 {
    map.get(key)
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(default)
}

fn env_u32(map: &BTreeMap<String, String>, key: &str, default: u32) -> u32 {
    map.get(key)
        .and_then(|value| value.parse::<u32>().ok())
        .unwrap_or(default)
}

fn address_preview(address: &str) -> String {
    let chars = address.chars().collect::<Vec<_>>();
    if chars.len() <= 14 {
        return address.to_string();
    }
    let start = chars.iter().take(8).collect::<String>();
    let end = chars
        .iter()
        .rev()
        .take(6)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect::<String>();
    format!("{start}...{end}")
}

fn bech32_polymod(values: impl IntoIterator<Item = u8>) -> u32 {
    let mut chk = 1u32;
    let generators = [
        0x3b6a57b2u32,
        0x26508e6du32,
        0x1ea119fau32,
        0x3d4233ddu32,
        0x2a1462b3u32,
    ];
    for value in values {
        let top = chk >> 25;
        chk = ((chk & 0x1ff_ffff) << 5) ^ u32::from(value);
        for (index, generator) in generators.iter().enumerate() {
            if ((top >> index) & 1) == 1 {
                chk ^= generator;
            }
        }
    }
    chk
}

fn bech32_hrp_expand(hrp: &str) -> Vec<u8> {
    let mut expanded = Vec::with_capacity(hrp.len() * 2 + 1);
    expanded.extend(hrp.bytes().map(|byte| byte >> 5));
    expanded.push(0);
    expanded.extend(hrp.bytes().map(|byte| byte & 31));
    expanded
}

fn convert_bits(data: &[u8], from_bits: u32, to_bits: u32, pad: bool) -> Option<Vec<u8>> {
    let mut acc = 0u32;
    let mut bits = 0u32;
    let max_value = (1u32 << to_bits) - 1;
    let max_acc = (1u32 << (from_bits + to_bits - 1)) - 1;
    let mut converted = Vec::new();

    for value in data {
        let value = u32::from(*value);
        if value >> from_bits != 0 {
            return None;
        }
        acc = ((acc << from_bits) | value) & max_acc;
        bits += from_bits;
        while bits >= to_bits {
            bits -= to_bits;
            converted.push(((acc >> bits) & max_value) as u8);
        }
    }

    if pad {
        if bits > 0 {
            converted.push(((acc << (to_bits - bits)) & max_value) as u8);
        }
    } else if bits >= from_bits || ((acc << (to_bits - bits)) & max_value) != 0 {
        return None;
    }

    Some(converted)
}

fn decode_base58(value: &str) -> Result<Vec<u8>, String> {
    let alphabet = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    let mut decoded = Vec::<u8>::new();

    for byte in value.bytes() {
        let Some(index) = alphabet.iter().position(|candidate| *candidate == byte) else {
            return Err("Base58 address contains invalid characters".to_string());
        };
        let mut carry = index as u32;
        for decoded_byte in &mut decoded {
            carry += u32::from(*decoded_byte) * 58;
            *decoded_byte = (carry & 0xff) as u8;
            carry >>= 8;
        }
        while carry > 0 {
            decoded.push((carry & 0xff) as u8);
            carry >>= 8;
        }
    }

    let leading_zeroes = value.bytes().take_while(|byte| *byte == b'1').count();
    let mut result = vec![0u8; leading_zeroes];
    result.extend(decoded.into_iter().rev());
    Ok(result)
}

fn validate_base58check_address(address: &str) -> Result<(), String> {
    let decoded = decode_base58(address)?;
    if decoded.len() != 25 {
        return Err("Base58Check address has invalid length".to_string());
    }
    match decoded[0] {
        0x00 if address.starts_with('1') => {}
        0x05 if address.starts_with('3') => {}
        _ => return Err("Base58Check address is not Bitcoin mainnet".to_string()),
    }

    let payload = &decoded[..21];
    let expected = &decoded[21..];
    let first = Sha256::digest(payload);
    let second = Sha256::digest(first);
    if &second[..4] != expected {
        return Err("Base58Check address checksum is invalid".to_string());
    }
    Ok(())
}

fn validate_bech32_address(address: &str) -> Result<(), String> {
    if address != address.to_ascii_lowercase() && address != address.to_ascii_uppercase() {
        return Err("Bech32 address must not use mixed case".to_string());
    }

    let lower = address.to_ascii_lowercase();
    let separator = lower
        .rfind('1')
        .ok_or_else(|| "Bech32 address is missing separator".to_string())?;
    if separator < 1 || separator + 7 > lower.len() || lower.len() > 90 {
        return Err("Bech32 address has invalid structure".to_string());
    }

    let hrp = &lower[..separator];
    if hrp != "bc" {
        return Err("Bech32 address must be Bitcoin mainnet".to_string());
    }

    let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    let data = lower[separator + 1..]
        .chars()
        .map(|ch| {
            charset
                .find(ch)
                .map(|index| index as u8)
                .ok_or_else(|| "Bech32 address contains invalid characters".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;

    let mut checksum_input = bech32_hrp_expand(hrp);
    checksum_input.extend(data.iter().copied());
    let checksum = bech32_polymod(checksum_input);
    let is_bech32 = checksum == 1;
    let is_bech32m = checksum == 0x2bc830a3;
    if !is_bech32 && !is_bech32m {
        return Err("Bech32 address checksum is invalid".to_string());
    }

    let Some((&version, payload_with_checksum)) = data.split_first() else {
        return Err("Bech32 address has no witness version".to_string());
    };
    if version > 16 {
        return Err("Bech32 witness version is invalid".to_string());
    }
    let payload_len = payload_with_checksum
        .len()
        .checked_sub(6)
        .ok_or_else(|| "Bech32 address payload is too short".to_string())?;
    let program = convert_bits(&payload_with_checksum[..payload_len], 5, 8, false)
        .ok_or_else(|| "Bech32 witness program is invalid".to_string())?;
    if !(2..=40).contains(&program.len()) {
        return Err("Bech32 witness program length is invalid".to_string());
    }
    if version == 0 {
        if !is_bech32 || !(program.len() == 20 || program.len() == 32) {
            return Err("Bech32 v0 witness program is invalid".to_string());
        }
    } else if !is_bech32m {
        return Err("Bech32 v1+ address must use Bech32m".to_string());
    }

    Ok(())
}

fn validate_address_syntax(address: &str) -> Result<(), String> {
    if !address.is_ascii()
        || address
            .bytes()
            .any(|byte| byte.is_ascii_whitespace() || byte == b'=')
    {
        return Err("address contains invalid characters".to_string());
    }
    if address.starts_with("bc1") {
        return validate_bech32_address(address);
    }
    if address.starts_with('1') || address.starts_with('3') {
        return validate_base58check_address(address);
    }
    Err("address must look like a Bitcoin mainnet address".to_string())
}

fn max_miner_threads() -> u32 {
    thread::available_parallelism()
        .map(|threads| threads.get().min(32) as u32)
        .unwrap_or(1)
        .max(1)
}

fn get_config_internal() -> Result<ConfigView, String> {
    let path = config_path()?;
    let map = read_env_file(&path)?;
    let btc_address = map.get("BTC_ADDRESS").cloned().unwrap_or_default();
    let time_limit = map.get("TIME_LIMIT_SECONDS").and_then(|value| {
        if value.is_empty() {
            None
        } else {
            value.parse::<u64>().ok()
        }
    });

    Ok(ConfigView {
        address_preview: address_preview(&btc_address),
        btc_address,
        worker_name: map
            .get("WORKER_NAME")
            .cloned()
            .unwrap_or_else(|| "mac-cpu".to_string()),
        pool_host: map
            .get("POOL_HOST")
            .cloned()
            .unwrap_or_else(|| "solo.ckpool.org".to_string()),
        pool_port: map
            .get("POOL_PORT")
            .cloned()
            .unwrap_or_else(|| "3333".to_string()),
        algo: map
            .get("ALGO")
            .cloned()
            .unwrap_or_else(|| "sha256d".to_string()),
        threads: env_u32(&map, "THREADS", 1),
        max_threads: max_miner_threads(),
        throttle_mode: map
            .get("THROTTLE_MODE")
            .cloned()
            .unwrap_or_else(|| "duty-cycle".to_string()),
        duty_active_seconds: env_u64(&map, "DUTY_ACTIVE_SECONDS", 1),
        duty_idle_seconds: env_u64(&map, "DUTY_IDLE_SECONDS", 9),
        time_limit_seconds: time_limit,
        require_ac_power: env_bool(&map, "REQUIRE_AC_POWER", true),
        allow_unlimited_run: env_bool(&map, "ALLOW_UNLIMITED_RUN", false),
        allow_multi_thread: env_bool(&map, "ALLOW_MULTI_THREAD", false),
        cpuminer_ref: map.get("CPUMINER_REF").cloned().unwrap_or_default(),
        miner_bin: map
            .get("MINER_BIN")
            .cloned()
            .unwrap_or_else(|| "vendor/cpuminer-multi/cpuminer".to_string()),
        config_path: path.display().to_string(),
    })
}

fn validate_update(update: &ConfigUpdate) -> Result<(), String> {
    if update.btc_address.trim().is_empty() {
        return Err("BTC address is required".to_string());
    }
    let address = update.btc_address.trim();
    if address.starts_with("tb1") || address.starts_with("bcrt") {
        return Err("testnet/regtest address is not allowed".to_string());
    }
    validate_address_syntax(address)?;
    if update.worker_name.is_empty()
        || update.worker_name.len() > 32
        || !update
            .worker_name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-')
    {
        return Err("worker name must be 1-32 anonymous safe characters".to_string());
    }
    if update.throttle_mode != "duty-cycle" {
        return Err("desktop app only allows duty-cycle mode for this profile".to_string());
    }
    let max_threads = max_miner_threads();
    if update.threads == 0 || update.threads > max_threads {
        return Err(format!("threads must be 1..{max_threads} on this Mac"));
    }
    if update.threads != 1 && !update.allow_multi_thread {
        return Err("multi-thread mining must be explicitly enabled".to_string());
    }
    if update.duty_active_seconds == 0 {
        return Err("active seconds must be positive".to_string());
    }
    if update.duty_idle_seconds > 60 {
        return Err("idle seconds must be 0..60".to_string());
    }
    if let Some(seconds) = update.time_limit_seconds {
        if seconds == 0 || seconds > 3600 {
            return Err("time limit must be 1..3600 seconds".to_string());
        }
    } else {
        return Err("desktop app requires a bounded time limit".to_string());
    }
    Ok(())
}

fn write_config(update: ConfigUpdate) -> Result<ConfigView, String> {
    validate_update(&update)?;
    let path = config_path()?;
    let time_limit = update.time_limit_seconds.unwrap_or(300);
    let content = format!(
        "BTC_ADDRESS={}\n\
WORKER_NAME={}\n\n\
POOL_HOST=solo.ckpool.org\n\
POOL_PORT=3333\n\
POOL_PASSWORD=x\n\
ALGO=sha256d\n\n\
THREADS={}\n\
CPULIMIT_PERCENT=10\n\
CPULIMIT_INCLUDE_CHILDREN=1\n\
NICE_LEVEL=20\n\
REQUIRE_AC_POWER={}\n\
REQUIRE_PREFLIGHT=1\n\
ALLOW_UNLIMITED_RUN=0\n\
ALLOW_MULTI_THREAD={}\n\
THROTTLE_MODE=duty-cycle\n\
DUTY_ACTIVE_SECONDS={}\n\
DUTY_IDLE_SECONDS={}\n\
TIME_LIMIT_SECONDS={}\n\
LOG_DIR=logs\n\
LOG_RETENTION=100\n\n\
MINER_BIN=vendor/cpuminer-multi/cpuminer\n\
CPUMINER_REF=d2927ed23b1d0eacd067c320fce64e6610737adb\n",
        update.btc_address.trim(),
        update.worker_name.trim(),
        update.threads,
        if update.require_ac_power { "1" } else { "0" },
        if update.allow_multi_thread { "1" } else { "0" },
        update.duty_active_seconds,
        update.duty_idle_seconds,
        time_limit
    );
    write_file_atomic(&path, &content)?;
    get_config_internal()
}

fn write_file_atomic(path: &Path, content: &str) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("config path has no parent: {}", path.display()))?;
    fs::create_dir_all(parent).map_err(|err| format!("failed to create config dir: {err}"))?;

    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| format!("config path has invalid file name: {}", path.display()))?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let tmp_path = parent.join(format!(".{file_name}.{}.{}.tmp", std::process::id(), nonce));

    let write_result = (|| -> Result<(), String> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&tmp_path)
            .map_err(|err| format!("failed to create temp config: {err}"))?;

        #[cfg(unix)]
        fs::set_permissions(&tmp_path, fs::Permissions::from_mode(0o600))
            .map_err(|err| format!("failed to set config permissions: {err}"))?;

        file.write_all(content.as_bytes())
            .map_err(|err| format!("failed to write temp config: {err}"))?;
        file.sync_all()
            .map_err(|err| format!("failed to sync temp config: {err}"))?;
        drop(file);

        fs::rename(&tmp_path, path).map_err(|err| format!("failed to replace config: {err}"))?;
        if let Ok(parent_dir) = fs::File::open(parent) {
            let _ = parent_dir.sync_all();
        }
        Ok(())
    })();

    if write_result.is_err() {
        let _ = fs::remove_file(&tmp_path);
    }
    write_result
}

fn terminate_child(child: &mut Child) {
    if child.try_wait().ok().flatten().is_some() {
        return;
    }

    let pid = child.id().to_string();
    let _ = Command::new("/bin/kill").arg("-TERM").arg(&pid).status();
    for _ in 0..20 {
        if child.try_wait().ok().flatten().is_some() {
            return;
        }
        thread::sleep(Duration::from_millis(100));
    }
    let _ = child.kill();
    let _ = child.wait();
}

fn run_script_capture(name: &str, extra_env: &[(&str, String)]) -> Result<CommandResult, String> {
    let mut command = script_command(name)?;
    for (key, value) in extra_env {
        command.env(key, value);
    }
    let output = command
        .output()
        .map_err(|err| format!("failed to run {name}: {err}"))?;
    Ok(CommandResult {
        ok: output.status.success(),
        code: output.status.code(),
        stdout: redact_sensitive_text(&String::from_utf8_lossy(&output.stdout)),
        stderr: redact_sensitive_text(&String::from_utf8_lossy(&output.stderr)),
    })
}

fn latest_log_path() -> Result<Option<PathBuf>, String> {
    let dir = configured_logs_dir()?;
    let mut entries: Vec<(SystemTime, PathBuf)> = Vec::new();
    if !dir.exists() {
        return Ok(None);
    }
    for entry in fs::read_dir(dir).map_err(|err| format!("failed to read logs: {err}"))? {
        let entry = entry.map_err(|err| format!("failed to read log entry: {err}"))?;
        let path = entry.path();
        if path
            .file_name()
            .and_then(|name| name.to_str())
            .map(|name| name.starts_with("miner-") && name.ends_with(".log"))
            .unwrap_or(false)
        {
            let modified = entry
                .metadata()
                .and_then(|metadata| metadata.modified())
                .unwrap_or(UNIX_EPOCH);
            entries.push((modified, path));
        }
    }
    entries.sort_by(|(left_time, left_path), (right_time, right_path)| {
        left_time
            .cmp(right_time)
            .then_with(|| left_path.cmp(right_path))
    });
    Ok(entries.pop().map(|(_, path)| path))
}

fn read_tail(path: &Path, max_lines: usize) -> Result<String, String> {
    if !path.exists() {
        return Ok(String::new());
    }
    let file = fs::File::open(path).map_err(|err| format!("failed to open log: {err}"))?;
    let reader = BufReader::new(file);
    let mut lines = VecDeque::new();
    for line in reader.lines() {
        lines.push_back(line.map_err(|err| format!("failed to read log: {err}"))?);
        if lines.len() > max_lines {
            lines.pop_front();
        }
    }
    Ok(redact_sensitive_text(
        &lines.into_iter().collect::<Vec<_>>().join("\n"),
    ))
}

fn redact_sensitive_args(line: &str) -> String {
    let parts = line.split_whitespace().collect::<Vec<_>>();
    let mut redacted = Vec::with_capacity(parts.len());
    let mut index = 0usize;
    while index < parts.len() {
        let part = parts[index];
        if matches!(part, "-p" | "--pass" | "--password") {
            redacted.push(part.to_string());
            if index + 1 < parts.len() {
                redacted.push("REDACTED".to_string());
                index += 2;
                continue;
            }
        } else if part.starts_with("-p") && part.len() > 2 {
            redacted.push("-pREDACTED".to_string());
            index += 1;
            continue;
        } else if let Some((key, _value)) = part.split_once('=')
            && matches!(key, "--pass" | "--password")
        {
            redacted.push(format!("{key}=REDACTED"));
            index += 1;
            continue;
        }
        redacted.push(part.to_string());
        index += 1;
    }
    redacted.join(" ")
}

fn redact_sensitive_text(text: &str) -> String {
    text.lines()
        .map(redact_sensitive_args)
        .collect::<Vec<_>>()
        .join("\n")
}

fn process_lines(miner_bin: &str) -> Result<Vec<String>, String> {
    let output = Command::new("/bin/ps")
        .args(["-ax", "-o", "pid,stat,comm,%cpu,%mem,rss,args"])
        .output()
        .map_err(|err| format!("failed to inspect process list: {err}"))?;
    if !output.status.success() {
        return Err(format!("process list command failed: {}", output.status));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(stdout
        .lines()
        .filter(|line| line.contains(miner_bin))
        .map(redact_sensitive_args)
        .collect())
}

fn get_status_internal(state: &AppState) -> Result<MinerStatus, String> {
    let mut guard = state
        .run
        .lock()
        .map_err(|_| "failed to lock run state".to_string())?;
    let mut running = false;
    let mut pid = None;
    let mut started_at = None;
    let mut log_file = None;

    if let Some(run) = guard.as_mut() {
        match run.child.try_wait() {
            Ok(Some(_status)) => {
                *guard = None;
            }
            Ok(None) => {
                running = true;
                pid = Some(run.child.id());
                started_at = Some(run.started_at);
                log_file = Some(run.log_file.display().to_string());
            }
            Err(_) => {
                *guard = None;
            }
        }
    }

    let latest = if let Some(path) = log_file.as_ref() {
        Some(PathBuf::from(path))
    } else {
        latest_log_path()?
    };
    let latest_log_tail = latest
        .as_ref()
        .map(|path| read_tail(path, 120))
        .transpose()?
        .unwrap_or_default();

    let miner_bin = config_path()
        .and_then(|path| read_env_file(&path))
        .and_then(|map| configured_miner_bin_from_map(&map))
        .ok()
        .unwrap_or_else(|| {
            project_root()
                .unwrap_or_else(|_| PathBuf::from("."))
                .join("vendor/cpuminer-multi/cpuminer")
        });
    let miner_bin = miner_bin.display().to_string();
    let (processes, process_error) = match process_lines(&miner_bin) {
        Ok(lines) => (lines, None),
        Err(err) => (Vec::new(), Some(err)),
    };

    Ok(MinerStatus {
        running,
        pid,
        started_at,
        log_file,
        processes,
        process_error,
        latest_log_file: latest.map(|path| path.display().to_string()),
        latest_log_tail,
    })
}

#[tauri::command]
fn get_dashboard(state: tauri::State<AppState>) -> Result<Dashboard, String> {
    Ok(Dashboard {
        config: get_config_internal()?,
        status: get_status_internal(&state)?,
    })
}

#[tauri::command]
fn get_config() -> Result<ConfigView, String> {
    get_config_internal()
}

#[tauri::command]
fn save_config(update: ConfigUpdate) -> Result<ConfigView, String> {
    write_config(update)
}

#[tauri::command]
fn run_preflight() -> Result<CommandResult, String> {
    run_script_capture("preflight.sh", &[])
}

#[tauri::command]
fn dry_run() -> Result<CommandResult, String> {
    run_script_capture("run-solo-miner.sh", &[("DRY_RUN", "1".to_string())])
}

#[tauri::command]
fn check_ckpool() -> Result<CommandResult, String> {
    run_script_capture("check-ckpool-user.sh", &[])
}

#[tauri::command]
fn get_status(state: tauri::State<AppState>) -> Result<MinerStatus, String> {
    get_status_internal(&state)
}

#[tauri::command]
fn read_latest_log(max_lines: Option<usize>) -> Result<String, String> {
    let Some(path) = latest_log_path()? else {
        return Ok(String::new());
    };
    read_tail(&path, max_lines.unwrap_or(160).min(500))
}

#[tauri::command]
fn start_mining(
    state: tauri::State<AppState>,
    time_limit_seconds: Option<u64>,
) -> Result<StartResult, String> {
    let mut guard = state
        .run
        .lock()
        .map_err(|_| "failed to lock run state".to_string())?;
    if let Some(run) = guard.as_mut() {
        if run.child.try_wait().ok().flatten().is_none() {
            return Err("miner is already running".to_string());
        }
        *guard = None;
    }

    let config = get_config_internal()?;
    let time_limit = time_limit_seconds
        .or(config.time_limit_seconds)
        .unwrap_or(300);
    if time_limit == 0 || time_limit > 3600 {
        return Err("time limit must be 1..3600 seconds".to_string());
    }

    let log_dir = configured_logs_dir()?;
    fs::create_dir_all(&log_dir).map_err(|err| format!("failed to create log directory: {err}"))?;
    require_path_under_project_root("LOG_DIR", &log_dir)?;
    let log_file = log_dir.join(format!("miner-app-{}.log", now_unix_nanos()));
    fs::create_dir_all(log_file.parent().unwrap_or_else(|| Path::new(".")))
        .map_err(|err| format!("failed to create log directory: {err}"))?;

    let mut child = script_command("run-solo-miner.sh")?
        .env("TIME_LIMIT_SECONDS", time_limit.to_string())
        .env("LOG_FILE", &log_file)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|err| format!("failed to start miner: {err}"))?;

    thread::sleep(Duration::from_millis(250));
    if let Some(status) = child
        .try_wait()
        .map_err(|err| format!("failed to inspect miner startup: {err}"))?
    {
        let log_tail = read_tail(&log_file, 80).unwrap_or_default();
        let detail = if log_tail.trim().is_empty() {
            "no startup log was written".to_string()
        } else {
            log_tail
        };
        return Err(format!("miner exited during startup ({status}):\n{detail}"));
    }

    let pid = child.id();
    let started_at = now_unix();
    *guard = Some(ManagedRun {
        child,
        log_file: log_file.clone(),
        started_at,
    });

    Ok(StartResult {
        running: true,
        pid,
        log_file: log_file.display().to_string(),
        started_at,
    })
}

#[tauri::command]
fn stop_mining(state: tauri::State<AppState>) -> Result<MinerStatus, String> {
    {
        let mut guard = state
            .run
            .lock()
            .map_err(|_| "failed to lock run state".to_string())?;
        if let Some(mut run) = guard.take() {
            terminate_child(&mut run.child);
        }
    }
    get_status_internal(&state)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let paths =
                seed_packaged_runtime(&app.path().resource_dir()?, &app.path().app_data_dir()?)
                    .map_err(|err| {
                        Box::<dyn std::error::Error>::from(std::io::Error::other(err))
                    })?;
            let _ = RUNTIME_PATHS.set(paths);
            Ok(())
        })
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            get_dashboard,
            get_config,
            save_config,
            run_preflight,
            dry_run,
            check_ckpool,
            get_status,
            read_latest_log,
            start_mining,
            stop_mining
        ])
        .run(tauri::generate_context!())
        .expect("error while running BTC Solo Lab");
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_update() -> ConfigUpdate {
        ConfigUpdate {
            btc_address: "bc1q9clzaht7mrl2vaa0e2u53v59n5l2dgj0842uuz".to_string(),
            worker_name: "mac-cpu".to_string(),
            threads: 1,
            throttle_mode: "duty-cycle".to_string(),
            duty_active_seconds: 1,
            duty_idle_seconds: 9,
            time_limit_seconds: Some(300),
            require_ac_power: true,
            allow_multi_thread: false,
        }
    }

    #[test]
    fn preview_masks_long_addresses() {
        assert_eq!(
            address_preview("bc1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"),
            "bc1qqqqq...qqqqqq"
        );
    }

    #[test]
    fn config_update_accepts_safe_mainnet_profile() {
        assert!(validate_update(&valid_update()).is_ok());
    }

    #[test]
    fn config_update_rejects_testnet_address() {
        let mut update = valid_update();
        update.btc_address = "tb1q9clzaht7mrl2vaa0e2u53v59n5l2dgj0842uuz".to_string();
        assert!(validate_update(&update).is_err());
    }

    #[test]
    fn config_update_rejects_bad_bech32_checksum() {
        let mut update = valid_update();
        update.btc_address = "bc1q9clzaht7mrl2vaa0e2u53v59n5l2dgj0842uuq".to_string();
        assert!(validate_update(&update).is_err());
    }

    #[test]
    fn config_update_accepts_valid_base58check_addresses() {
        let mut update = valid_update();
        update.btc_address = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa".to_string();
        assert!(validate_update(&update).is_ok());

        update.btc_address = "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy".to_string();
        assert!(validate_update(&update).is_ok());
    }

    #[test]
    fn config_update_rejects_bad_base58check_checksum() {
        let mut update = valid_update();
        update.btc_address = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb".to_string();
        assert!(validate_update(&update).is_err());
    }

    #[test]
    fn redacts_pool_password_from_process_lines() {
        assert_eq!(
            redact_sensitive_args("123 S cpuminer 1 2 3 /miner -a sha256d -p secret -t 1"),
            "123 S cpuminer 1 2 3 /miner -a sha256d -p REDACTED -t 1"
        );
        assert_eq!(
            redact_sensitive_args("/miner --password=secret --pass other -px"),
            "/miner --password=REDACTED --pass REDACTED -pREDACTED"
        );
    }

    #[test]
    fn redacts_pool_password_from_log_text() {
        let text = "Command: /miner -a sha256d -p supersecret -t 1\nerror --password=other";
        let redacted = redact_sensitive_text(text);
        assert!(!redacted.contains("supersecret"));
        assert!(!redacted.contains("other"));
        assert!(redacted.contains("-p REDACTED"));
        assert!(redacted.contains("--password=REDACTED"));
    }

    #[test]
    fn config_update_rejects_address_injection() {
        let mut update = valid_update();
        update.btc_address =
            "bc1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq\nPOOL_HOST=bad".to_string();
        assert!(validate_update(&update).is_err());
    }

    #[test]
    fn config_update_requires_bounded_run() {
        let mut update = valid_update();
        update.time_limit_seconds = None;
        assert!(validate_update(&update).is_err());
    }

    #[test]
    fn config_update_requires_explicit_multi_thread_opt_in() {
        let mut update = valid_update();
        update.threads = 2.min(max_miner_threads());
        if max_miner_threads() > 1 {
            assert!(validate_update(&update).is_err());
            update.allow_multi_thread = true;
            assert!(validate_update(&update).is_ok());
        }
    }

    #[test]
    fn config_update_rejects_threads_above_host_capacity() {
        let mut update = valid_update();
        update.allow_multi_thread = true;
        update.threads = max_miner_threads() + 1;
        assert!(validate_update(&update).is_err());
    }

    #[test]
    fn config_update_rejects_unsafe_worker_name() {
        let mut update = valid_update();
        update.worker_name = "real name".to_string();
        assert!(validate_update(&update).is_err());
    }

    #[test]
    fn env_parser_rejects_unknown_keys() {
        let path = std::env::temp_dir().join(format!("btc-solo-lab-unknown-{}.env", now_unix()));
        fs::write(
            &path,
            "BTC_ADDRESS=bc1q9clzaht7mrl2vaa0e2u53v59n5l2dgj0842uuz\nBAD=1\n",
        )
        .unwrap();
        let result = read_env_file(&path);
        let _ = fs::remove_file(&path);
        assert!(result.is_err());
    }

    #[test]
    fn env_parser_accepts_export_prefix() {
        let path = std::env::temp_dir().join(format!("btc-solo-lab-export-{}.env", now_unix()));
        fs::write(&path, "export WORKER_NAME=mac-cpu\n").unwrap();
        let result = read_env_file(&path);
        let _ = fs::remove_file(&path);
        assert_eq!(
            result.unwrap().get("WORKER_NAME"),
            Some(&"mac-cpu".to_string())
        );
    }

    #[test]
    fn env_parser_accepts_log_retention() {
        let path = std::env::temp_dir().join(format!("btc-solo-lab-retention-{}.env", now_unix()));
        fs::write(&path, "LOG_RETENTION=100\n").unwrap();
        let result = read_env_file(&path);
        let _ = fs::remove_file(&path);
        assert_eq!(
            result.unwrap().get("LOG_RETENTION"),
            Some(&"100".to_string())
        );
    }

    #[test]
    fn project_path_guard_rejects_escape() {
        let escaped = project_root().unwrap().join("../btc-solo-lab-outside");
        assert!(require_path_under_project_root("LOG_DIR", &escaped).is_err());
    }

    #[test]
    fn packaged_runtime_seed_copies_clean_resources() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let temp_root = std::env::temp_dir().join(format!("btc-solo-lab-runtime-{nonce}"));
        let resource_root = temp_root.join("resources");
        let runtime_root = resource_root.join("runtime");
        let app_data_dir = temp_root.join("app-data");

        fs::create_dir_all(runtime_root.join("scripts/lib")).unwrap();
        fs::create_dir_all(app_data_dir.join("scripts")).unwrap();
        fs::write(
            app_data_dir.join("scripts/package-macos.sh"),
            "#!/usr/bin/env bash\n",
        )
        .unwrap();
        for script in PACKAGED_RUNTIME_SCRIPTS {
            fs::write(
                runtime_root.join("scripts").join(script),
                "#!/usr/bin/env bash\n",
            )
            .unwrap();
        }
        fs::write(
            runtime_root.join("scripts/lib/miner-env.sh"),
            "#!/usr/bin/env bash\n",
        )
        .unwrap();
        fs::create_dir_all(runtime_root.join("configs")).unwrap();
        fs::write(
            runtime_root.join("configs/miner.env.example"),
            "BTC_ADDRESS=\nLOG_RETENTION=100\n",
        )
        .unwrap();
        fs::create_dir_all(runtime_root.join("vendor/cpuminer-multi")).unwrap();
        fs::write(runtime_root.join("vendor/cpuminer-multi/cpuminer"), "miner").unwrap();

        let paths = seed_packaged_runtime(&resource_root, &app_data_dir).unwrap();

        assert_eq!(paths.root, app_data_dir);
        assert!(paths.root.join("scripts/run-solo-miner.sh").exists());
        assert!(!paths.root.join("scripts/package-macos.sh").exists());
        assert!(paths.root.join("vendor/cpuminer-multi/cpuminer").exists());
        assert_eq!(
            fs::read_to_string(paths.root.join("configs/miner.env")).unwrap(),
            "BTC_ADDRESS=\nLOG_RETENTION=100\n"
        );
        assert!(!resource_root.join("runtime/configs/miner.env").exists());

        let _ = fs::remove_dir_all(temp_root);
    }
}
