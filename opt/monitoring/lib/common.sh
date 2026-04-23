#!/usr/bin/env bash

die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

info() {
  printf "INFO:  %s\n" "$*" >&2
}

debug() {
  [[ ${VERBOSE:-0} -eq 1 ]] && printf "DEBUG: %s\n" "$*" >&2 || true
}

check_deps() {
  local missing=()
  for cmd in "$@"; do
    command -v "${cmd}" &>/dev/null || missing+=("${cmd}")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing required commands: ${missing[*]}"
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

load_senders() {
  # shellcheck disable=SC2154
  # Rationale: SENDERS_DIR is defined in the main script and imported via source
  [[ -d ${SENDERS_DIR} ]] || {
    debug "Senders directory not found: ${SENDERS_DIR}"
    return 0
  }
  for sender in "${SENDERS_DIR}"/*.sh; do
    [[ -f ${sender} ]] || continue
    # shellcheck source=/dev/null
    # Rationale: Dynamic sourcing of sender modules from senders/ directory
    source "${sender}"
  done
}

load_messages() {
  local prefix="${1:-}"
  # shellcheck disable=SC2154
  # Rationale: MESSAGES_DIR is defined in the main script and imported via source
  [[ -d ${MESSAGES_DIR} ]] || {
    debug "Messages directory not found: ${MESSAGES_DIR}"
    return 0
  }
  for msg in "${MESSAGES_DIR}"/"${prefix}"*.sh; do
    [[ -f ${msg} ]] || continue
    # shellcheck source=/dev/null
    # Rationale: Dynamic sourcing of message modules from messages/ directory
    source "${msg}"
  done
}

get_available_notifiers() {
  local prefix="${1:-}"
  local -a available=()
  # shellcheck disable=SC2154
  # Rationale: MESSAGES_DIR is defined in the main script and imported via source
  for msg in "${MESSAGES_DIR}"/"${prefix}"*.sh; do
    [[ -f ${msg} ]] || continue
    local name
    name=$(basename "${msg}" .sh)
    name=${name#"${prefix}"}
    available+=("${name}")
  done
  printf '%s\n' "${available[@]}"
}

get_configured_notifiers() {
  local -a configured=()
  [[ -n ${BOT_TOKEN:-} ]] || [[ -n ${CHAT_ID:-} ]] && configured+=("telegram")
  [[ -n ${MATRIX_URL:-} ]] || [[ -n ${MATRIX_ROOM_ID:-} ]] || [[ -n ${MATRIX_ACCESS_TOKEN:-} ]] && configured+=("matrix")
  [[ -n ${NTFY_URL:-} ]] || [[ -n ${NTFY_TOPIC:-} ]] && configured+=("ntfy")
  printf '%s\n' "${configured[@]}"
}
