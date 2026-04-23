#!/usr/bin/env bash
set -euo pipefail

die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

validate_bot_config() {
  local config_file="${1:-}"
  local config_cache="${2:-/run/bash-sys-monitor/config}"

  if [[ -z ${config_file} ]]; then
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    config_file="${script_dir}/../bot.conf"
  fi

  # shellcheck disable=SC2310
  # Rationale: Function intentionally returns error code for parent script to handle.
  validate_secure_config "${config_file}" || return 1

  # shellcheck source=/dev/null
  # Rationale: Configuration file path is resolved dynamically at runtime.
  source "${config_file}"

  # shellcheck disable=SC2310
  # Rationale: Function intentionally returns error code for parent script to handle.
  validate_server_name "${SERVER_NAME:-}" || return 1

  local has_telegram=0
  local has_matrix=0
  local has_ntfy=0

  [[ -n ${BOT_TOKEN:-} ]] && has_telegram=1
  [[ -n ${CHAT_ID:-} ]] && has_telegram=1

  [[ -n ${MATRIX_URL:-} ]] && has_matrix=1
  [[ -n ${MATRIX_ROOM_ID:-} ]] && has_matrix=1
  [[ -n ${MATRIX_ACCESS_TOKEN:-} ]] && has_matrix=1

  [[ -n ${NTFY_URL:-} ]] && has_ntfy=1
  [[ -n ${NTFY_TOPIC:-} ]] && has_ntfy=1

  if [[ ${has_telegram} -eq 1 ]]; then
    # shellcheck disable=SC2310
    # Rationale: Function intentionally returns error code for parent script to handle.
    validate_bot_token "${BOT_TOKEN:-}" || return 1
    # shellcheck disable=SC2310
    validate_chat_id "${CHAT_ID:-}" || return 1
  fi

  if [[ ${has_matrix} -eq 1 ]]; then
    # shellcheck disable=SC2310
    # Rationale: Function intentionally returns error code for parent script to handle.
    validate_url "${MATRIX_URL:-}" || return 1
    # shellcheck disable=SC2310
    validate_matrix_room_id "${MATRIX_ROOM_ID:-}" || return 1
    # shellcheck disable=SC2310
    validate_matrix_access_token "${MATRIX_ACCESS_TOKEN:-}" || return 1
  fi

  if [[ ${has_ntfy} -eq 1 ]]; then
    # shellcheck disable=SC2310
    # Rationale: Function intentionally returns error code for parent script to handle.
    validate_url "${NTFY_URL:-}" || return 1
    # shellcheck disable=SC2310
    validate_ntfy_topic "${NTFY_TOPIC:-}" || return 1
    # shellcheck disable=SC2310
    validate_ntfy_token "${NTFY_TOKEN:-}" || return 1
  fi

  local cache_dir
  cache_dir=$(dirname "${config_cache}")
  mkdir -p "${cache_dir}"
  chmod 700 "${cache_dir}"

  cp "${config_file}" "${config_cache}"
  chmod 400 "${config_cache}"

  return 0
}

validate_secure_config() {
  local config_file="$1"

  [[ -f ${config_file} ]] || {
    printf "Config file not found: %s\n" "${config_file}" >&2
    return 1
  }
  [[ -r ${config_file} ]] || {
    printf "Config file not readable: %s\n" "${config_file}" >&2
    return 1
  }

  local owner
  owner=$(stat -c "%u" "${config_file}")
  [[ ${owner} -eq ${EUID} ]] || {
    printf "Config file %s must be owned by EUID: %s\n" "${config_file}" "${EUID}" >&2
    return 1
  }

  local perms
  perms=$(stat -c "%a" "${config_file}")
  [[ ${perms} =~ ^(400|600)$ ]] || {
    printf "Config file %s must have secure permissions 400 or 600 (current: %s)\n" "${config_file}" "${perms}" >&2
    return 1
  }

  if grep -qP '^\s*[^#=\s].*\(|`|\$\(' "${config_file}" 2>/dev/null; then
    printf "Config file %s contains potentially unsafe subshells or logic\n" "${config_file}" >&2
    return 1
  fi

  return 0
}

urlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for ((pos = 0; pos < strlen; pos++)); do
    c=${string:pos:1}
    case "${c}" in
    [-_.~a-zA-Z0-9]) o="${c}" ;;
    *) printf -v o '%%%02x' "'${c}" ;;
    esac
    encoded+="${o}"
  done
  printf '%s' "${encoded}"
}

validate_ipv4() {
  local ip="$1"
  [[ ${ip} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  local IFS=.
  local -a octets
  read -ra octets <<<"${ip}"
  for octet in "${octets[@]}"; do
    [[ ${octet} -le 255 ]] || return 1
    [[ ${octet} =~ ^0[0-9]+$ ]] && return 1
  done
  return 0
}

validate_ipv6() {
  local ip="$1"
  ip="${ip#\[}"
  ip="${ip%\]}"

  [[ ${ip} =~ ^[a-fA-F0-9:]+$ ]] || return 1
  [[ ${ip} == *:::* ]] && return 1
  [[ ${ip} =~ ^:[^:] ]] && return 1
  [[ ${ip} =~ [^:]:$ ]] && return 1

  local dc="${ip#*::}"
  if [[ ${dc} != "${ip}" ]]; then
    local dc2="${dc#*::}"
    [[ ${dc2} != "${dc}" ]] && return 1
  fi

  local IFS=:
  local -a hextets
  read -ra hextets <<<"${ip}"

  if [[ ${dc} == "${ip}" ]] && [[ ${#hextets[@]} -ne 8 ]]; then
    return 1
  fi
  if [[ ${#hextets[@]} -gt 8 ]]; then
    return 1
  fi

  for hextet in "${hextets[@]}"; do
    [[ ${#hextet} -le 4 ]] || return 1
  done
  return 0
}

validate_domain() {
  local domain="$1"
  [[ ${domain} =~ ^[a-zA-Z0-9.-]+$ ]] || return 1
  [[ ${domain} =~ ^[-.] ]] && return 1
  [[ ${domain} =~ [-.]$ ]] && return 1
  [[ ${domain} == *..* ]] && return 1
  return 0
}

validate_domain_ip() {
  local val="$1"
  [[ -z ${val} ]] && return 0

  if [[ ${val} == *:* ]]; then
    # shellcheck disable=SC2310
    # Rationale: Function intentionally returns error code for parent script to handle.
    validate_ipv6 "${val}" || {
      printf "Invalid IPv6 structure\n" >&2
      return 1
    }
  elif [[ ${val} =~ [^0-9.] ]]; then
    # shellcheck disable=SC2310
    # Rationale: Function intentionally returns error code for parent script to handle.
    validate_domain "${val}" || {
      printf "Invalid domain structure\n" >&2
      return 1
    }
  else
    # shellcheck disable=SC2310
    # Rationale: Function intentionally returns error code for parent script to handle.
    validate_ipv4 "${val}" || {
      printf "Invalid IPv4 structure\n" >&2
      return 1
    }
  fi
  return 0
}

validate_port() {
  local val="$1"
  [[ -z ${val} ]] && return 0

  [[ ${val} =~ ^[0-9]+$ ]] || {
    printf "Port contains non-numeric characters\n" >&2
    return 1
  }

  if ((10#${val} < 1 || 10#${val} > 65535)); then
    printf "Port must be between 1 and 65535\n" >&2
    return 1
  fi
  return 0
}

validate_domain_port() {
  local val="$1"
  [[ -z ${val} ]] && return 0

  local host="" port=""

  case "${val}" in
  \[*\]:*)
    host="${val%%]:*}]"
    port="${val##*:}"
    ;;
  \[*\])
    host="${val}"
    ;;
  *:*:*)
    host="${val}"
    ;;
  *:*)
    host="${val%%:*}"
    port="${val##*:}"
    ;;
  *)
    host="${val}"
    ;;
  esac

  local err
  # shellcheck disable=SC2310
  # Rationale: Function intentionally returns error code for parent script to handle.
  err=$(validate_domain_ip "${host}" 2>&1) || {
    printf "%s\n" "${err}" >&2
    return 1
  }

  if [[ -n ${port} ]]; then
    # shellcheck disable=SC2310
    # Rationale: Function intentionally returns error code for parent script to handle.
    err=$(validate_port "${port}" 2>&1) || {
      printf "%s\n" "${err}" >&2
      return 1
    }
  fi

  return 0
}

validate_url() {
  local url="$1"

  [[ ${url} =~ ^https?://(.+)$ ]] || {
    printf "URL must start with http:// or https://\n" >&2
    return 1
  }

  local rest="${BASH_REMATCH[1]}"
  local host_port="${rest%%/*}"

  local err
  # shellcheck disable=SC2310
  # Rationale: Function intentionally returns error code for parent script to handle.
  err=$(validate_domain_port "${host_port}" 2>&1) || {
    printf "URL host/port error: %s\n" "${err}" >&2
    return 1
  }
  return 0
}

validate_matrix_room_id() {
  local val="$1"
  [[ -z ${val} ]] && {
    printf "Room ID is empty\n" >&2
    return 1
  }

  [[ ${val} == !* ]] || {
    printf "Room ID must start with '!'\n" >&2
    return 1
  }

  local body="${val#!}"

  if [[ ${body} == *:* ]]; then
    local localpart="${body%%:*}"
    local serverpart="${body#*:}"

    [[ -z ${localpart} ]] && {
      printf "Room ID has empty localpart\n" >&2
      return 1
    }
    [[ -z ${serverpart} ]] && {
      printf "Room ID has empty domain\n" >&2
      return 1
    }

    [[ ${localpart} =~ ^[a-zA-Z0-9._=/-]+$ ]] || {
      printf "Room ID localpart contains invalid characters\n" >&2
      return 1
    }

    local err
    # shellcheck disable=SC2310
    # Rationale: Function intentionally returns error code for parent script to handle.
    err=$(validate_domain_port "${serverpart}" 2>&1) || {
      printf "Room ID domain error: %s\n" "${err}" >&2
      return 1
    }
  else
    [[ ${body} =~ ^[a-zA-Z0-9._=/-]+$ ]] || {
      printf "Room ID contains invalid characters\n" >&2
      return 1
    }
  fi

  return 0
}

validate_server_name() {
  local val="$1"
  [[ -n ${val} ]] || {
    printf "SERVER_NAME is not set\n" >&2
    return 1
  }
  [[ ${val} =~ ^[a-zA-Z0-9\ ._-]+$ ]] || {
    printf "SERVER_NAME format is invalid (allowed: a-z, A-Z, 0-9, space, ., _, -)\n" >&2
    return 1
  }
  return 0
}

validate_bot_token() {
  local val="$1"
  [[ -n ${val} ]] || {
    printf "BOT_TOKEN is not set\n" >&2
    return 1
  }
  [[ ${val} =~ ^[0-9]+:[A-Za-z0-9_-]{35,}$ ]] || {
    printf "BOT_TOKEN format is invalid\n" >&2
    return 1
  }
  return 0
}

validate_chat_id() {
  local val="$1"
  [[ -n ${val} ]] || {
    printf "CHAT_ID is not set\n" >&2
    return 1
  }
  [[ ${val} =~ ^-?[0-9]+$ ]] || {
    printf "CHAT_ID format is invalid\n" >&2
    return 1
  }
  return 0
}

validate_ntfy_topic() {
  local val="$1"
  [[ -n ${val} ]] || {
    printf "NTFY_TOPIC is not set\n" >&2
    return 1
  }
  [[ ${val} =~ ^[a-zA-Z0-9_-]+$ ]] || {
    printf "NTFY_TOPIC format is invalid (allowed: a-z, A-Z, 0-9, _, -)\n" >&2
    return 1
  }
  return 0
}

validate_ntfy_token() {
  local val="$1"
  [[ -z ${val} ]] && return 0
  [[ ${val} =~ ^tk_[a-z0-9]+$ ]] || {
    printf "NTFY_TOKEN format is invalid\n" >&2
    return 1
  }
  return 0
}

validate_matrix_access_token() {
  local val="$1"
  [[ -n ${val} ]] || {
    printf "MATRIX_ACCESS_TOKEN is not set\n" >&2
    return 1
  }
  [[ ${val} =~ ^syt_[a-zA-Z0-9_]+$ ]] || {
    printf "MATRIX_ACCESS_TOKEN format is invalid\n" >&2
    return 1
  }
  return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  validate_bot_config "$@"
fi
