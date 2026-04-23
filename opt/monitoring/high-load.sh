#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck disable=SC2034
# Rationale: Path variables are declared for consistent structure and exported for dynamic plugin loaded context.
readonly LIB_DIR="${SCRIPT_DIR}/lib"
# shellcheck disable=SC2034
readonly SENDERS_DIR="${SCRIPT_DIR}/senders"
readonly MESSAGES_DIR="${SCRIPT_DIR}/messages"
readonly CONFIG_CACHE="/run/bash-sys-monitor/config"
readonly TOP_PROCS_COUNT=20

THRESHOLD=""
REQUESTED_NOTIFIERS=""
VERBOSE=0

# shellcheck source=/dev/null
# Rationale: Common library functions are sourced dynamically at runtime
source "${LIB_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage: high-load.sh [options]

Collects system metrics (load average, PSI, memory, CPU) and dispatches
alerts via configured notifiers when thresholds are crossed.

Options:
  -t, --threshold FLOAT   Required: load-average alert threshold (e.g. 4.0)
  -n, --notifiers LIST    Optional: comma-separated notifiers to use
                          Default: all available from messages/ directory
                          Available: telegram, matrix, ntfy
  -v, --verbose           Optional: print collected metrics to stdout
  -h, --help              Show this help message

Example:
  high-load.sh --threshold 4.0 --notifiers telegram,matrix

Note: PSI availability requires Linux kernel >= 4.20 and CONFIG_PSI=y.
      Falls back to load-average-only mode if /proc/pressure/* is absent.
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -t | --threshold)
      THRESHOLD="${2:?'--threshold requires a value'}"
      shift 2
      ;;
    -n | --notifiers)
      REQUESTED_NOTIFIERS="${2:?'--notifiers requires a value'}"
      shift 2
      ;;
    -v | --verbose)
      VERBOSE=1
      shift
      ;;
    -h | --help) usage ;;
    *) die "Unknown argument: $1" ;;
    esac
  done

  [[ -n ${THRESHOLD} ]] || die "--threshold is required"

  [[ ${THRESHOLD} =~ ^[0-9]+(\.[0-9]+)?$ ]] ||
    die "--threshold must be a positive number, got: ${THRESHOLD}"
}

collect_loadavg() {
  local raw
  raw=$(</proc/loadavg) || die "Cannot read /proc/loadavg"
  read -r LOAD_1 LOAD_5 LOAD_15 _ <<<"${raw}"
  debug "Load average: ${LOAD_1} ${LOAD_5} ${LOAD_15}"
}

collect_psi() {
  PSI_CPU_SOME_AVG10=""
  PSI_CPU_SOME_AVG60=""
  PSI_IO_SOME_AVG10=""
  PSI_IO_SOME_AVG60=""
  PSI_IO_FULL_AVG10=""
  PSI_IO_FULL_AVG60=""
  PSI_MEM_SOME_AVG10=""
  PSI_MEM_SOME_AVG60=""
  PSI_MEM_FULL_AVG10=""
  PSI_MEM_FULL_AVG60=""
  PSI_AVAILABLE=0

  [[ -d /proc/pressure ]] || {
    debug "PSI not available on this kernel"
    return 0
  }

  if [[ -r /proc/pressure/cpu ]]; then
    local cpu_some _ avg10 avg60
    cpu_some=$(grep '^some' /proc/pressure/cpu) || true
    read -r _ avg10 avg60 _ <<<"${cpu_some}"
    PSI_CPU_SOME_AVG10="${avg10#*=}"
    PSI_CPU_SOME_AVG60="${avg60#*=}"
  fi

  if [[ -r /proc/pressure/io ]]; then
    local io_some io_full _ avg10 avg60
    io_some=$(grep '^some' /proc/pressure/io) || true
    io_full=$(grep '^full' /proc/pressure/io) || true

    read -r _ avg10 avg60 _ <<<"${io_some}"
    PSI_IO_SOME_AVG10="${avg10#*=}"
    PSI_IO_SOME_AVG60="${avg60#*=}"

    read -r _ avg10 avg60 _ <<<"${io_full}"
    # shellcheck disable=SC2034
    # Rationale: Variables are populated here but consumed dynamically by loaded message templates.
    PSI_IO_FULL_AVG10="${avg10#*=}"
    # shellcheck disable=SC2034
    PSI_IO_FULL_AVG60="${avg60#*=}"
  fi

  if [[ -r /proc/pressure/memory ]]; then
    local mem_some mem_full _ avg10 avg60
    mem_some=$(grep '^some' /proc/pressure/memory) || true
    mem_full=$(grep '^full' /proc/pressure/memory) || true

    read -r _ avg10 avg60 _ <<<"${mem_some}"
    PSI_MEM_SOME_AVG10="${avg10#*=}"
    PSI_MEM_SOME_AVG60="${avg60#*=}"

    read -r _ avg10 avg60 _ <<<"${mem_full}"
    # shellcheck disable=SC2034
    # Rationale: Variables are populated here but consumed dynamically by loaded message templates.
    PSI_MEM_FULL_AVG10="${avg10#*=}"
    # shellcheck disable=SC2034
    PSI_MEM_FULL_AVG60="${avg60#*=}"
  fi

  PSI_AVAILABLE=1
  debug "PSI cpu_some_10=${PSI_CPU_SOME_AVG10} io_some_10=${PSI_IO_SOME_AVG10} mem_some_10=${PSI_MEM_SOME_AVG10}"
}

collect_memory() {
  local meminfo
  meminfo=$(grep -E "^(MemTotal|MemFree|Buffers|Cached|SReclaimable|SwapTotal|SwapFree):" /proc/meminfo) ||
    die "Cannot read /proc/meminfo"

  local total=0 free=0 buffers=0 cached=0 sreclaimable=0 stotal=0 sfree=0
  while read -r key val _; do
    case "${key}" in
    MemTotal:) total="${val}" ;;
    MemFree:) free="${val}" ;;
    Buffers:) buffers="${val}" ;;
    Cached:) cached="${val}" ;;
    SReclaimable:) sreclaimable="${val}" ;;
    SwapTotal:) stotal="${val}" ;;
    SwapFree:) sfree="${val}" ;;
    *) ;;
    esac
  done <<<"${meminfo}"

  MEMORY_TOTAL=$(awk -v t="${total}" 'BEGIN {printf "%.2f", t/1024/1024}')
  MEMORY_ACTIVE_USED=$(awk -v t="${total}" -v f="${free}" -v b="${buffers}" \
    -v c="${cached}" -v s="${sreclaimable}" \
    'BEGIN {printf "%.2f", (t - f - b - c - s)/1024/1024}')
  MEMORY_USAGE_PCT=$(awk -v t="${total}" -v f="${free}" -v b="${buffers}" \
    -v c="${cached}" -v s="${sreclaimable}" \
    'BEGIN {printf "%.1f", ((t - f - b - c - s)/t)*100}')

  SWAP_TOTAL=$(awk -v t="${stotal:-0}" 'BEGIN {printf "%.2f", t/1024/1024}')
  SWAP_USED=$(awk -v t="${stotal:-0}" -v f="${sfree:-0}" 'BEGIN {printf "%.2f", (t-f)/1024/1024}')
  SWAP_USAGE_PCT=$(awk -v t="${stotal:-0}" -v f="${sfree:-0}" 'BEGIN {printf "%.1f", (t > 0) ? ((t-f)/t)*100 : 0}')

  debug "Memory: ${MEMORY_ACTIVE_USED} / ${MEMORY_TOTAL} GB (${MEMORY_USAGE_PCT}%) | Swap: ${SWAP_USED} / ${SWAP_TOTAL} GB (${SWAP_USAGE_PCT}%)"
}

collect_disk_space() {
  local root_df
  root_df=$(df -m / | tail -n 1) || true

  local total free pct
  read -r _ total _ free pct _ <<<"${root_df}"

  ROOT_FS_FREE_GB=$(awk -v f="${free:-0}" 'BEGIN {printf "%.2f", f/1024}')
  ROOT_FS_PCT="${pct:-unknown}"

  debug "Root FS: ${ROOT_FS_FREE_GB} GB free (${ROOT_FS_PCT} used)"
}

collect_activity() {
  local stat1 stat2 idle1 total1 idle2 total2 disk1 disk2 net1 net2

  stat1=$(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)
  disk1=$(awk '{r+=$6; w+=$10} END {print r, w}' /proc/diskstats 2>/dev/null || echo "0 0")
  net1=$(awk '/:/ {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev 2>/dev/null || echo "0 0")

  read -r u1 n1 s1 i1 w1 irq1 sirq1 <<<"${stat1}"
  total1=$((u1 + n1 + s1 + i1 + w1 + irq1 + sirq1))
  idle1=${i1}

  sleep 1

  stat2=$(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)
  disk2=$(awk '{r+=$6; w+=$10} END {print r, w}' /proc/diskstats 2>/dev/null || echo "0 0")
  net2=$(awk '/:/ {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev 2>/dev/null || echo "0 0")

  read -r u2 n2 s2 i2 w2 irq2 sirq2 <<<"${stat2}"
  total2=$((u2 + n2 + s2 + i2 + w2 + irq2 + sirq2))
  idle2=${i2}

  PROCS_RUNNING=$(awk '/^procs_running/ {print $2}' /proc/stat 2>/dev/null || echo "0")
  PROCS_BLOCKED=$(awk '/^procs_blocked/ {print $2}' /proc/stat 2>/dev/null || echo "0")

  local delta_total=$((total2 - total1))
  local delta_idle=$((idle2 - idle1))

  CPU_USAGE=$(awk -v dt="${delta_total}" -v di="${delta_idle}" \
    'BEGIN {printf "%.1f", (dt > 0) ? (1 - di/dt)*100 : 0}')

  local disk_r1 disk_w1 disk_r2 disk_w2
  read -r disk_r1 disk_w1 <<<"${disk1}"
  read -r disk_r2 disk_w2 <<<"${disk2}"
  DISK_READ_MB=$(awk -v r1="${disk_r1}" -v r2="${disk_r2}" 'BEGIN {printf "%.2f", (r2-r1)*512/1024/1024}')
  DISK_WRITE_MB=$(awk -v w1="${disk_w1}" -v w2="${disk_w2}" 'BEGIN {printf "%.2f", (w2-w1)*512/1024/1024}')

  local net_rx1 net_tx1 net_rx2 net_tx2
  read -r net_rx1 net_tx1 <<<"${net1}"
  read -r net_rx2 net_tx2 <<<"${net2}"
  NET_RX_MBPS=$(awk -v rx1="${net_rx1}" -v rx2="${net_rx2}" 'BEGIN {printf "%.2f", (rx2-rx1)*8/1000/1000}')
  NET_TX_MBPS=$(awk -v tx1="${net_tx1}" -v tx2="${net_tx2}" 'BEGIN {printf "%.2f", (tx2-tx1)*8/1000/1000}')

  debug "CPU: ${CPU_USAGE}% | Disk: ${DISK_READ_MB}/${DISK_WRITE_MB} MB/s | Net: ${NET_RX_MBPS}/${NET_TX_MBPS} Mbps | Procs: ${PROCS_RUNNING}R/${PROCS_BLOCKED}B"
}

collect_failed_services() {
  FAILED_SERVICES=""
  if command -v systemctl &>/dev/null; then
    local failed
    failed=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}' | grep '\.' | tr '\n' ',' | sed 's/,$//; s/,/, /g' || true)
    [[ -n ${failed} ]] && FAILED_SERVICES="${failed}"
  fi
  debug "Failed services: ${FAILED_SERVICES:-none}"
}

collect_top_procs() {
  TOP_PROCS_FILE=$(mktemp /run/bash-sys-monitor/high-load-top-XXXXXX.txt)
  trap 'rm -f "${TOP_PROCS_FILE}"' EXIT

  LC_ALL=C ps aux --sort=-%cpu | head -n $((TOP_PROCS_COUNT + 1)) >"${TOP_PROCS_FILE}"
  debug "Top processes written to ${TOP_PROCS_FILE}"
}

should_alert() {
  local load_exceeded
  load_exceeded=$(awk -v l="${LOAD_1}" -v t="${THRESHOLD}" 'BEGIN {print (l > t) ? 1 : 0}')
  [[ ${load_exceeded} -eq 1 ]] || return 1

  if [[ ${PSI_AVAILABLE} -eq 1 ]]; then
    local c10=${PSI_CPU_SOME_AVG10:-0}
    local c60=${PSI_CPU_SOME_AVG60:-0}
    local i10=${PSI_IO_SOME_AVG10:-0}
    local i60=${PSI_IO_SOME_AVG60:-0}
    local m10=${PSI_MEM_SOME_AVG10:-0}
    local m60=${PSI_MEM_SOME_AVG60:-0}

    local any_pressure
    any_pressure=$(awk -v c10="${c10}" -v c60="${c60}" \
      -v i10="${i10}" -v i60="${i60}" \
      -v m10="${m10}" -v m60="${m60}" \
      'BEGIN {
        p10 = (c10 >= 20.0 || i10 >= 15.0 || m10 >= 10.0) ? 1 : 0;
        p60 = (c60 >= 5.0  || i60 >= 5.0  || m60 >= 5.0)  ? 1 : 0;
        print (p10 && p60) ? 1 : 0
      }')
    if [[ ${any_pressure} -eq 0 ]]; then
      debug "Load ${LOAD_1} > ${THRESHOLD} but PSI is too low (10s CPU:${c10}% IO:${i10}% Mem:${m10}% | 60s CPU:${c60}% IO:${i60}% Mem:${m60}%)"
      return 1
    fi
    debug "PSI confirms real pressure"
  fi

  return 0
}

dispatch_notifications() {
  local -a requested=()
  local -a available=()
  local -a configured=()

  # shellcheck disable=SC2310
  # Rationale: Function is intentionally invoked in a conditional context.
  while IFS= read -r name; do
    [[ -n ${name} ]] && available+=("${name}")
  done < <(get_available_notifiers "high-load-") || true

  # shellcheck disable=SC2310
  # Rationale: Function is intentionally invoked in a conditional context.
  while IFS= read -r name; do
    [[ -n ${name} ]] && configured+=("${name}")
  done < <(get_configured_notifiers) || true

  if [[ -n ${REQUESTED_NOTIFIERS} ]]; then
    IFS=',' read -ra requested <<<"${REQUESTED_NOTIFIERS}"
  else
    requested=("${available[@]}")
  fi

  [[ ${#requested[@]} -eq 0 ]] && die "No notifiers available. Add message files to ${MESSAGES_DIR}"

  local notifier
  for notifier in "${requested[@]}"; do
    local is_available=0 is_configured=0
    local avail cfg

    for avail in "${available[@]}"; do
      [[ ${avail} == "${notifier}" ]] && {
        is_available=1
        break
      }
    done

    for cfg in "${configured[@]}"; do
      [[ ${cfg} == "${notifier}" ]] && {
        is_configured=1
        break
      }
    done

    if [[ ${is_available} -eq 0 ]]; then
      local avail_list
      avail_list=$(printf '%s, ' "${available[@]}")
      avail_list=${avail_list%, }
      [[ -z ${avail_list} ]] && avail_list="none"
      die "Requested notifier '${notifier}' not found in ${MESSAGES_DIR}. Available: ${avail_list}"
    fi

    if [[ ${is_configured} -eq 0 ]]; then
      local cfg_list
      cfg_list=$(printf '%s, ' "${configured[@]}")
      cfg_list=${cfg_list%, }
      [[ -z ${cfg_list} ]] && cfg_list="none"
      die "Notifier '${notifier}' requested but not configured. Configured: ${cfg_list}"
    fi
  done

  for notifier in "${requested[@]}"; do
    debug "Dispatching to notifier: ${notifier}"
    (
      case "${notifier}" in
      telegram)
        local message
        message=$(high_load_message_telegram)
        tg_send_message "${message}" || printf "ERROR: telegram notification failed\n" >&2
        tg_send_file "${TOP_PROCS_FILE}" || printf "ERROR: telegram file send failed\n" >&2
        ;;
      matrix)
        local plain html
        plain=$(high_load_message_matrix_plain)
        html=$(high_load_message_matrix_html)
        mx_send_message "${plain}" "${html}" || printf "ERROR: matrix notification failed\n" >&2
        mx_send_file "${TOP_PROCS_FILE}" || printf "ERROR: matrix file send failed\n" >&2
        ;;
      ntfy)
        local message title
        message=$(high_load_message_ntfy)
        title=$(high_load_title_ntfy)
        # shellcheck disable=SC2154
        # Rationale: NTFY_TOKEN is populated from config file.
        ntfy_send "${message}" "${NTFY_URL}" "${NTFY_TOPIC}" "${NTFY_TOKEN}" "${title}" || printf "ERROR: ntfy notification failed\n" >&2
        ntfy_send_file "${TOP_PROCS_FILE}" "${NTFY_URL}" "${NTFY_TOPIC}" "${NTFY_TOKEN}" "${title}" || printf "ERROR: ntfy file send failed\n" >&2
        ;;
      *)
        printf "ERROR: Unknown notifier: %s\n" "${notifier}" >&2
        ;;
      esac
    ) &
  done

  wait
}

main() {
  parse_args "$@"
  check_deps awk curl jq ps file stat

  if [[ -z ${SERVER_NAME:-} ]] && [[ -f ${CONFIG_CACHE} ]]; then
    # shellcheck source=/dev/null
    # Rationale: Configuration is populated dynamically at runtime based on the cache.
    source "${CONFIG_CACHE}"
  fi

  load_senders
  load_messages "high-load-"

  local -a available_notifiers=()
  # shellcheck disable=SC2310
  # Rationale: Function is intentionally invoked in a conditional context.
  while IFS= read -r name; do
    [[ -n ${name} ]] && available_notifiers+=("${name}")
  done < <(get_available_notifiers "high-load-") || true

  local -a configured_notifiers=()
  # shellcheck disable=SC2310
  # Rationale: Function is intentionally invoked in a conditional context.
  while IFS= read -r name; do
    [[ -n ${name} ]] && configured_notifiers+=("${name}")
  done < <(get_configured_notifiers) || true

  [[ ${#available_notifiers[@]} -gt 0 ]] || die "No notifier message files found in ${MESSAGES_DIR}"
  [[ ${#configured_notifiers[@]} -gt 0 ]] || die "No notifiers configured in config. Set at least one: telegram (BOT_TOKEN, CHAT_ID), matrix (MATRIX_URL, MATRIX_ROOM_ID, MATRIX_ACCESS_TOKEN), or ntfy (NTFY_URL, NTFY_TOPIC)"

  collect_loadavg
  collect_psi

  local alert_needed=0
  # shellcheck disable=SC2310
  # Rationale: Boolean check; error handling is explicit.
  if should_alert; then
    alert_needed=1
  fi

  if [[ ${VERBOSE} -eq 1 ]] || [[ ${alert_needed} -eq 1 ]]; then
    collect_memory
    collect_disk_space
    collect_activity
    collect_failed_services

    export ALERT_TIME
    ALERT_TIME=$(date +'%Y-%m-%d %H:%M:%S')

    local msg="Alert condition met (load=${LOAD_1}, threshold=${THRESHOLD})"
    [[ ${VERBOSE} -eq 1 ]] && msg="Forced alert via --verbose (load=${LOAD_1}, threshold=${THRESHOLD})"
    info "${msg}"
    collect_top_procs
    dispatch_notifications
  else
    debug "No alert condition (load=${LOAD_1}, threshold=${THRESHOLD})"
  fi
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main "$@"
fi
