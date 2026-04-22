#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

readonly LIB_DIR="${SCRIPT_DIR}/lib"
# shellcheck disable=SC2034
# Rationale: Exported for use by dynamically sourced modules in lib/ and messages/
readonly SENDERS_DIR="${SCRIPT_DIR}/senders"
# shellcheck disable=SC2034
# Rationale: Exported for use by dynamically sourced modules in lib/ and messages/
readonly MESSAGES_DIR="${SCRIPT_DIR}/messages"
readonly STATE_DIR="${SCRIPT_DIR}/state"
readonly STATE_FILE="${STATE_DIR}/login_last_ts.txt"
readonly CONFIG_CACHE="/run/bash-sys-monitor/config"

REQUESTED_NOTIFIERS=""

# shellcheck source=/dev/null
# Rationale: Common library functions are sourced dynamically at runtime
source "${LIB_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage: login.sh [options]

Monitors /var/log/wtmp for new logins and dispatches
alerts via configured notifiers.

Options:
  -n, --notifiers LIST    Optional: comma-separated notifiers to use
                          Default: all configured
                          Available: telegram, matrix, ntfy
  -h, --help              Show this help message

Example:
  login.sh --notifiers telegram,matrix
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -n | --notifiers)
      REQUESTED_NOTIFIERS="${2:?'--notifiers requires a value'}"
      shift 2
      ;;
    -h | --help) usage ;;
    *) die "Unknown argument: $1" ;;
    esac
  done
}

dispatch_login_notification() {
  local user="$1"
  local tty="$2"
  local ip="$3"
  local login_time="$4"

  export LOGIN_USER="${user}"
  export LOGIN_TTY="${tty}"
  export LOGIN_IP="${ip}"
  export LOGIN_TIME="${login_time}"
  export ALERT_TIME
  ALERT_TIME=$(date +'%Y-%m-%d %H:%M:%S')

  local -a requested=()
  local -a available=()
  local -a configured=()

  # shellcheck disable=SC2310
  # Rationale: Function is intentionally invoked in a conditional context
  while IFS= read -r name; do
    [[ -n ${name} ]] && available+=("${name}")
  done < <(get_available_notifiers "login-") || true

  # shellcheck disable=SC2310
  # Rationale: Function is intentionally invoked in a conditional context
  while IFS= read -r name; do
    [[ -n ${name} ]] && configured+=("${name}")
  done < <(get_configured_notifiers) || true

  if [[ -n ${REQUESTED_NOTIFIERS} ]]; then
    IFS=',' read -ra requested <<<"${REQUESTED_NOTIFIERS}"
  else
    requested=("${available[@]}")
  fi

  [[ ${#requested[@]} -eq 0 ]] && return 0

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

    if [[ ${is_available} -eq 0 ]] || [[ ${is_configured} -eq 0 ]]; then
      continue
    fi

    debug "Dispatching to notifier: ${notifier}"
    (
      case "${notifier}" in
      telegram)
        local message
        message=$(login_message_telegram)
        tg_send_message "${message}" || echo "ERROR: telegram notification failed" >&2
        ;;
      matrix)
        local plain html
        plain=$(login_message_matrix_plain)
        html=$(login_message_matrix_html)
        mx_send_message "${plain}" "${html}" || echo "ERROR: matrix notification failed" >&2
        ;;
      ntfy)
        local message title
        message=$(login_message_ntfy)
        title=$(login_title_ntfy)
        # shellcheck disable=SC2154
        # Rationale: NTFY_* variables are populated from config file at runtime
        ntfy_send "${message}" "${NTFY_URL}" "${NTFY_TOPIC}" "${NTFY_TOKEN}" "${title}" || echo "ERROR: ntfy notification failed" >&2
        ;;
      *)
        echo "ERROR: Unknown notifier: ${notifier}" >&2
        ;;
      esac
    ) &
  done

  wait
}

process_logins() {
  local last_ts=0
  if [[ -f ${STATE_FILE} ]]; then
    last_ts=$(cat "${STATE_FILE}")
  else
    last_ts=$(date +%s)
    echo "${last_ts}" >"${STATE_FILE}"
    chmod 600 "${STATE_FILE}"
    info "First run, initialized state to current timestamp."
    return 0
  fi

  local new_last_ts=${last_ts}
  local -a new_logins=()

  while IFS= read -r line; do
    [[ -z ${line} || ${line} == wtmp* || ${line} == reboot* ]] && continue

    if [[ ${line} =~ ([A-Z][a-z]{2}[[:space:]]+[A-Z][a-z]{2}[[:space:]]+[0-9]+[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+[0-9]{4}) ]]; then
      local date_str="${BASH_REMATCH[1]}"
      local login_ts
      login_ts=$(date -d "${date_str}" +%s 2>/dev/null || echo 0)

      if ((login_ts > last_ts)); then
        local prefix="${line%%"${date_str}"*}"
        local user tty ip
        # shellcheck disable=SC2034
        # Rationale: Variables are used in the array element construction on the next line
        read -r user tty ip <<<"${prefix}"

        [[ -z ${ip} || ${ip} == "0.0.0.0" ]] && ip="Local"

        new_logins+=("${user}|${tty}|${ip}|${date_str}|${login_ts}")

        if ((login_ts > new_last_ts)); then
          new_last_ts=${login_ts}
        fi
      else
        break
      fi
    fi
  done < <(last -F -i || true)

  if [[ ${#new_logins[@]} -gt 0 ]]; then
    local login_data
    for login_data in "${new_logins[@]}"; do
      local user tty ip login_time_raw login_time
      IFS='|' read -r user tty ip login_time_raw _ <<<"${login_data}"
      login_time=$(date -d "${login_time_raw}" +'%Y-%m-%d %H:%M:%S')

      info "New login detected: ${user} from ${ip} on ${tty}"
      dispatch_login_notification "${user}" "${tty}" "${ip}" "${login_time}"
    done

    echo "${new_last_ts}" >"${STATE_FILE}"
  fi
}

main() {
  parse_args "$@"
  check_deps awk curl jq date last

  if [[ -f ${CONFIG_CACHE} ]]; then
    # shellcheck source=/dev/null
    # Rationale: Configuration is populated dynamically at runtime based on the cache
    source "${CONFIG_CACHE}"
  else
    die "Configuration cache not found. Please ensure validation service has run."
  fi

  load_senders
  load_messages "login-"

  process_logins
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main "$@"
fi
