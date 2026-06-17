#!/usr/bin/env bash

MINER_ENV_KEYS=(
  BTC_ADDRESS
  WORKER_NAME
  POOL_HOST
  POOL_PORT
  POOL_PASSWORD
  ALGO
  THREADS
  CPULIMIT_PERCENT
  CPULIMIT_INCLUDE_CHILDREN
  NICE_LEVEL
  REQUIRE_AC_POWER
  REQUIRE_PREFLIGHT
  ALLOW_UNLIMITED_RUN
  ALLOW_MULTI_THREAD
  THROTTLE_MODE
  DUTY_ACTIVE_SECONDS
  DUTY_IDLE_SECONDS
  TIME_LIMIT_SECONDS
  LOG_DIR
  LOG_RETENTION
  LOG_FILE
  DRY_RUN
  MINER_BIN
  CPUMINER_REF
  MINER_DIR
  CPUMINER_REPO
  BUILD_JOBS
)

miner_env_is_allowed_key() {
  local needle="$1"
  local key
  for key in "${MINER_ENV_KEYS[@]}"; do
    [[ "$key" == "$needle" ]] && return 0
  done
  return 1
}

load_miner_env() {
  local env_file="$1"
  shift
  local config_keys=("$@")
  local saved_had=()
  local saved_values=()
  local key line value index

  for key in "${config_keys[@]}"; do
    if [[ -n "${!key+x}" ]]; then
      saved_had+=(1)
      saved_values+=("${!key}")
    else
      saved_had+=(0)
      saved_values+=("")
    fi
  done

  [[ -f "$env_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == export\ * ]] && line="${line#export }"

    if [[ "$line" != *=* ]]; then
      echo "Invalid config line in $env_file: $line" >&2
      return 1
    fi

    key="${line%%=*}"
    value="${line#*=}"
    if ! [[ "$key" =~ ^[A-Z0-9_]+$ ]]; then
      echo "Invalid config key in $env_file: $key" >&2
      return 1
    fi
    if ! miner_env_is_allowed_key "$key"; then
      echo "Unknown config key in $env_file: $key" >&2
      return 1
    fi

    printf -v "$key" '%s' "$value"
    export "$key"
  done < "$env_file"

  for index in "${!config_keys[@]}"; do
    key="${config_keys[$index]}"
    if [[ "${saved_had[$index]}" == "1" ]]; then
      printf -v "$key" '%s' "${saved_values[$index]}"
      export "$key"
    fi
  done
}

miner_harden_env_permissions() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0
  [[ "$(basename "$env_file")" == "miner.env.example" ]] && return 0

  if ! chmod go-rwx "$env_file" 2>/dev/null; then
    echo "WARN could not restrict config permissions: $env_file" >&2
  fi
}

miner_abs_path() {
  local path="$1"
  local base_dir="$2"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$base_dir/$path"
  fi
}

miner_real_dir() {
  local path="$1"
  local dir
  dir="$(dirname "$path")"
  if [[ -d "$dir" ]]; then
    (cd "$dir" && pwd -P)
  else
    return 1
  fi
}

miner_real_path() {
  local path="$1"
  local dir target
  while [[ -L "$path" ]]; do
    dir="$(dirname "$path")"
    target="$(readlink "$path")" || return 1
    if [[ "$target" == /* ]]; then
      path="$target"
    else
      path="$dir/$target"
    fi
  done
  [[ -e "$path" ]] || return 1
  dir="$(dirname "$path")"
  (cd "$dir" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$path")")
}

miner_require_path_under_root() {
  local label="$1"
  local path="$2"
  local root_dir="$3"
  local real_root real_dir
  real_root="$(cd "$root_dir" && pwd -P)" || return 1
  real_dir="$(miner_real_dir "$path")" || {
    echo "$label parent directory does not exist: $(dirname "$path")" >&2
    return 1
  }
  case "$real_dir" in
    "$real_root"|"$real_root"/*)
      return 0
      ;;
    *)
      echo "$label must stay inside project root: $path" >&2
      return 1
      ;;
  esac
}

miner_require_file_under_root() {
  local label="$1"
  local path="$2"
  local root_dir="$3"
  local real_root real_path
  real_root="$(cd "$root_dir" && pwd -P)" || return 1
  real_path="$(miner_real_path "$path")" || {
    echo "$label does not exist: $path" >&2
    return 1
  }
  case "$real_path" in
    "$real_root"|"$real_root"/*)
      return 0
      ;;
    *)
      echo "$label must stay inside project root: $path" >&2
      return 1
      ;;
  esac
}

miner_require_log_file_under_dir() {
  local log_file="$1"
  local log_dir="$2"
  local real_log_dir real_file_dir
  mkdir -p "$log_dir" || return 1
  real_log_dir="$(cd "$log_dir" && pwd -P)" || return 1
  real_file_dir="$(miner_real_dir "$log_file")" || {
    echo "LOG_FILE parent directory does not exist: $(dirname "$log_file")" >&2
    return 1
  }
  case "$real_file_dir" in
    "$real_log_dir"|"$real_log_dir"/*)
      return 0
      ;;
    *)
      echo "LOG_FILE must stay inside LOG_DIR: $log_file" >&2
      return 1
      ;;
  esac
}

miner_validate_btc_address() {
  local address="$1"
  local lower
  [[ -n "$address" ]] || {
    echo "BTC_ADDRESS is empty" >&2
    return 1
  }
  if [[ "$address" == *[[:space:]=]* ]]; then
    echo "BTC_ADDRESS contains invalid characters" >&2
    return 1
  fi
  lower="$(printf '%s' "$address" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    tb1*|bcrt*|m*|n*)
      echo "BTC_ADDRESS looks like testnet/regtest" >&2
      return 1
      ;;
    bc1*)
      miner_validate_bech32_address "$address"
      ;;
    1*|3*)
      miner_validate_base58check_address "$address"
      ;;
    *)
      echo "BTC_ADDRESS does not look like a Bitcoin mainnet address" >&2
      return 1
      ;;
  esac
}

miner_bech32_value() {
  local char="$1"
  case "$char" in
    q) printf '0\n' ;;
    p) printf '1\n' ;;
    z) printf '2\n' ;;
    r) printf '3\n' ;;
    y) printf '4\n' ;;
    9) printf '5\n' ;;
    x) printf '6\n' ;;
    8) printf '7\n' ;;
    g) printf '8\n' ;;
    f) printf '9\n' ;;
    2) printf '10\n' ;;
    t) printf '11\n' ;;
    v) printf '12\n' ;;
    d) printf '13\n' ;;
    w) printf '14\n' ;;
    0) printf '15\n' ;;
    s) printf '16\n' ;;
    3) printf '17\n' ;;
    j) printf '18\n' ;;
    n) printf '19\n' ;;
    5) printf '20\n' ;;
    4) printf '21\n' ;;
    k) printf '22\n' ;;
    h) printf '23\n' ;;
    c) printf '24\n' ;;
    e) printf '25\n' ;;
    6) printf '26\n' ;;
    m) printf '27\n' ;;
    u) printf '28\n' ;;
    a) printf '29\n' ;;
    7) printf '30\n' ;;
    l) printf '31\n' ;;
    *) return 1 ;;
  esac
}

miner_bech32_polymod() {
  local chk=1
  local value top i
  local generators=(996825010 642813549 513874426 1027748829 705979059)
  for value in "$@"; do
    top=$(( chk >> 25 ))
    chk=$(( ((chk & 33554431) << 5) ^ value ))
    for i in 0 1 2 3 4; do
      if (( ((top >> i) & 1) == 1 )); then
        chk=$(( chk ^ generators[i] ))
      fi
    done
  done
  printf '%s\n' "$chk"
}

miner_bech32_program_length() {
  local acc=0
  local bits=0
  local count=0
  local value
  for value in "$@"; do
    (( value >= 0 && value < 32 )) || return 1
    acc=$(( ((acc << 5) | value) & 4095 ))
    bits=$(( bits + 5 ))
    while (( bits >= 8 )); do
      bits=$(( bits - 8 ))
      count=$(( count + 1 ))
    done
  done
  (( bits < 5 )) || return 1
  (( ((acc << (8 - bits)) & 255) == 0 )) || return 1
  printf '%s\n' "$count"
}

miner_validate_bech32_address() {
  local address="$1"
  local lower upper length separator=-1 i char hrp value checksum spec version payload_end program_length
  local data=()
  local values=(3 3 0 2 3)

  lower="$(printf '%s' "$address" | tr '[:upper:]' '[:lower:]')"
  upper="$(printf '%s' "$address" | tr '[:lower:]' '[:upper:]')"
  if [[ "$address" != "$lower" && "$address" != "$upper" ]]; then
    echo "BTC_ADDRESS has mixed-case Bech32" >&2
    return 1
  fi

  length="${#lower}"
  for (( i = 0; i < length; i++ )); do
    [[ "${lower:i:1}" == "1" ]] && separator="$i"
  done
  if (( separator < 1 || separator + 7 > length || length > 90 )); then
    echo "BTC_ADDRESS has invalid Bech32 structure" >&2
    return 1
  fi
  hrp="${lower:0:separator}"
  if [[ "$hrp" != "bc" ]]; then
    echo "BTC_ADDRESS is not Bitcoin mainnet Bech32" >&2
    return 1
  fi

  for (( i = separator + 1; i < length; i++ )); do
    char="${lower:i:1}"
    value="$(miner_bech32_value "$char")" || {
      echo "BTC_ADDRESS has invalid Bech32 characters" >&2
      return 1
    }
    data+=("$value")
    values+=("$value")
  done

  checksum="$(miner_bech32_polymod "${values[@]}")"
  if [[ "$checksum" == "1" ]]; then
    spec="bech32"
  elif [[ "$checksum" == "734539939" ]]; then
    spec="bech32m"
  else
    echo "BTC_ADDRESS checksum is invalid" >&2
    return 1
  fi

  version="${data[0]:-}"
  if [[ -z "$version" ]] || (( version < 0 || version > 16 )); then
    echo "BTC_ADDRESS witness version is invalid" >&2
    return 1
  fi
  payload_end=$(( ${#data[@]} - 6 ))
  if (( payload_end <= 1 )); then
    echo "BTC_ADDRESS witness program is missing" >&2
    return 1
  fi
  program_length="$(miner_bech32_program_length "${data[@]:1:payload_end-1}")" || {
    echo "BTC_ADDRESS witness program is invalid" >&2
    return 1
  }
  if (( program_length < 2 || program_length > 40 )); then
    echo "BTC_ADDRESS witness program length is invalid" >&2
    return 1
  fi
  if (( version == 0 )); then
    if [[ "$spec" != "bech32" ]] || (( program_length != 20 && program_length != 32 )); then
      echo "BTC_ADDRESS v0 witness program is invalid" >&2
      return 1
    fi
  elif [[ "$spec" != "bech32m" ]]; then
    echo "BTC_ADDRESS v1+ must use Bech32m" >&2
    return 1
  fi
}

miner_base58_value() {
  local char="$1"
  local alphabet="123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  local prefix
  case "$alphabet" in
    *"$char"*)
      prefix="${alphabet%%"$char"*}"
      printf '%s\n' "${#prefix}"
      ;;
    *)
      return 1
      ;;
  esac
}

miner_base58_decode_hex() {
  local address="$1"
  local length="${#address}"
  local decoded=()
  local pos char value carry i leading_zeroes=0 hex=""

  for (( pos = 0; pos < length; pos++ )); do
    char="${address:pos:1}"
    value="$(miner_base58_value "$char")" || return 1
    carry="$value"
    for (( i = 0; i < ${#decoded[@]}; i++ )); do
      carry=$(( decoded[i] * 58 + carry ))
      decoded[i]=$(( carry & 255 ))
      carry=$(( carry >> 8 ))
    done
    while (( carry > 0 )); do
      decoded+=("$(( carry & 255 ))")
      carry=$(( carry >> 8 ))
    done
  done

  while (( leading_zeroes < length )) && [[ "${address:leading_zeroes:1}" == "1" ]]; do
    hex="${hex}00"
    leading_zeroes=$(( leading_zeroes + 1 ))
  done
  for (( i = ${#decoded[@]} - 1; i >= 0; i-- )); do
    hex="${hex}$(printf '%02x' "${decoded[i]}")"
  done
  printf '%s\n' "$hex"
}

miner_sha256d_checksum8() {
  local payload_hex="$1"
  command -v perl >/dev/null 2>&1 || {
    echo "perl is required to validate Base58Check BTC_ADDRESS checksum" >&2
    return 1
  }
  perl -MDigest::SHA=sha256 -e '
    my $hex = shift;
    die "invalid hex\n" unless $hex =~ /\A[0-9a-fA-F]*\z/ && length($hex) % 2 == 0;
    my $bytes = pack("H*", $hex);
    print substr(unpack("H*", sha256(sha256($bytes))), 0, 8), "\n";
  ' "$payload_hex"
}

miner_validate_base58check_address() {
  local address="$1"
  local hex version payload checksum expected
  hex="$(miner_base58_decode_hex "$address")" || {
    echo "BTC_ADDRESS contains invalid Base58 characters" >&2
    return 1
  }
  if (( ${#hex} != 50 )); then
    echo "BTC_ADDRESS Base58Check length is invalid" >&2
    return 1
  fi
  version="${hex:0:2}"
  case "$address" in
    1*)
      [[ "$version" == "00" ]] || {
        echo "BTC_ADDRESS Base58 version is not Bitcoin mainnet" >&2
        return 1
      }
      ;;
    3*)
      [[ "$version" == "05" ]] || {
        echo "BTC_ADDRESS Base58 version is not Bitcoin mainnet" >&2
        return 1
      }
      ;;
    *)
      echo "BTC_ADDRESS is not a supported Bitcoin mainnet Base58 address" >&2
      return 1
      ;;
  esac

  payload="${hex:0:42}"
  checksum="${hex:42:8}"
  expected="$(miner_sha256d_checksum8 "$payload")" || return 1
  if [[ "$checksum" != "$expected" ]]; then
    echo "BTC_ADDRESS Base58Check checksum is invalid" >&2
    return 1
  fi
}

miner_preview_btc_address() {
  local address="$1"
  local length="${#address}"
  if (( length <= 14 )); then
    printf '%s\n' "$address"
  else
    printf '%s...%s\n' "${address:0:8}" "${address:length-6:6}"
  fi
}

miner_looks_like_btc_address() {
  local address="$1"
  local lower
  lower="$(printf '%s' "$address" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == bc1* ]]; then
    (( ${#address} >= 14 && ${#address} <= 90 )) || return 1
    [[ "$lower" =~ ^bc1[ac-hj-np-z02-9]+$ ]]
    return
  fi
  [[ "$address" =~ ^[13][123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]{25,61}$ ]]
}

miner_redact_pool_username() {
  local value="$1"
  local address worker redacted
  if [[ "$value" == *.* ]]; then
    address="${value%%.*}"
    worker="${value#*.}"
  else
    address="$value"
    worker=""
  fi

  if miner_looks_like_btc_address "$address"; then
    redacted="$(miner_preview_btc_address "$address")"
    if [[ -n "$worker" ]]; then
      printf '%s.%s\n' "$redacted" "$worker"
    else
      printf '%s\n' "$redacted"
    fi
  else
    printf '%s\n' "$value"
  fi
}

miner_print_redacted_command() {
  local args=("$@")
  local redacted=()
  local arg key i
  for (( i = 0; i < ${#args[@]}; i++ )); do
    arg="${args[i]}"
    case "$arg" in
      -p|--pass|--password)
        redacted+=("$arg")
        if (( i + 1 < ${#args[@]} )); then
          i=$(( i + 1 ))
          redacted+=("REDACTED")
        fi
        ;;
      -p?*)
        redacted+=("-pREDACTED")
        ;;
      --pass=*|--password=*)
        key="${arg%%=*}"
        redacted+=("$key=REDACTED")
        ;;
      -u|--user|--username)
        redacted+=("$arg")
        if (( i + 1 < ${#args[@]} )); then
          i=$(( i + 1 ))
          redacted+=("$(miner_redact_pool_username "${args[i]}")")
        fi
        ;;
      -u?*)
        redacted+=("-u$(miner_redact_pool_username "${arg#-u}")")
        ;;
      --user=*|--username=*)
        key="${arg%%=*}"
        redacted+=("$key=$(miner_redact_pool_username "${arg#*=}")")
        ;;
      *)
        redacted+=("$(miner_redact_pool_username "$arg")")
        ;;
    esac
  done
  printf "Command:"
  printf " %q" "${redacted[@]}"
  printf "\n"
}

miner_redact_sensitive_args() {
  awk '
    function looks_like_btc_address(value, lower) {
      lower = tolower(value)
      if (lower ~ /^bc1[ac-hj-np-z02-9]{11,87}$/) {
        return 1
      }
      return value ~ /^[13][123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]{25,61}$/
    }
    function preview_btc_address(value, length_value) {
      length_value = length(value)
      if (length_value <= 14) {
        return value
      }
      return substr(value, 1, 8) "..." substr(value, length_value - 5, 6)
    }
    function redact_pool_username(value, dot, address, worker) {
      dot = index(value, ".")
      if (dot > 0) {
        address = substr(value, 1, dot - 1)
        worker = substr(value, dot + 1)
      } else {
        address = value
        worker = ""
      }
      if (looks_like_btc_address(address)) {
        if (worker != "") {
          return preview_btc_address(address) "." worker
        }
        return preview_btc_address(address)
      }
      return value
    }
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "-p" || $i == "--pass" || $i == "--password") {
          if (i + 1 <= NF) {
            $(i + 1) = "REDACTED"
            i++
          }
        } else if ($i ~ /^-p.+/) {
          $i = "-pREDACTED"
        } else if ($i ~ /^--(pass|password)=/) {
          sub(/=.*/, "=REDACTED", $i)
        } else if ($i == "-u" || $i == "--user" || $i == "--username") {
          if (i + 1 <= NF) {
            $(i + 1) = redact_pool_username($(i + 1))
            i++
          }
        } else if ($i ~ /^-u.+/) {
          $i = "-u" redact_pool_username(substr($i, 3))
        } else if ($i ~ /^--(user|username)=/) {
          split($i, parts, "=")
          $i = parts[1] "=" redact_pool_username(substr($i, length(parts[1]) + 2))
        } else {
          $i = redact_pool_username($i)
        }
      }
      print
    }
  '
}
