#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2034,SC2154

setup_file() {
  export TEST_TMPDIR
  TEST_TMPDIR=$(mktemp -d)
}

teardown_file() {
  [[ -n ${TEST_TMPDIR:-} ]] && rm -rf "${TEST_TMPDIR}"
}

setup() {
  export SCRIPT_DIR="${BATS_TEST_DIRNAME}/../opt/monitoring"
  export SENDERS_DIR="${SCRIPT_DIR}/senders"
  export MESSAGES_DIR="${SCRIPT_DIR}/messages"
  source "${SCRIPT_DIR}/lib/common.sh"

  unset BOT_TOKEN CHAT_ID MATRIX_URL MATRIX_ROOM_ID MATRIX_ACCESS_TOKEN NTFY_URL NTFY_TOPIC NTFY_TOKEN VERBOSE 2>/dev/null || true
}

@test "common: die prints ERROR to stderr and exits 1" {
  run die "something broke"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: something broke"* ]]
}

@test "common: die handles multiple arguments" {
  run die "disk full" "on /dev/sda1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: disk full on /dev/sda1"* ]]
}

@test "common: die handles empty message" {
  run die
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR:"* ]]
}

@test "common: info prints INFO to stderr" {
  run info "startup complete"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO:  startup complete"* ]]
}

@test "common: info handles multiple arguments" {
  run info "loaded" "5 modules"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO:  loaded 5 modules"* ]]
}

@test "common: debug is silent when VERBOSE=0" {
  VERBOSE=0
  run debug "trace message"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common: debug is silent when VERBOSE is unset" {
  unset VERBOSE
  set +u
  run debug "trace message"
  set -u
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common: debug prints DEBUG when VERBOSE=1" {
  VERBOSE=1
  run debug "trace message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEBUG: trace message"* ]]
}

@test "common: check_deps succeeds with no arguments" {
  run check_deps
  [ "$status" -eq 0 ]
}

@test "common: check_deps succeeds when all commands exist" {
  command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
  }
  run check_deps bash cat ls
  [ "$status" -eq 0 ]
}

@test "common: check_deps fails with single missing command" {
  command() {
    if [[ "$1" == "-v" && "$2" == "nonexistent_cmd" ]]; then return 1; fi
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
  }
  run check_deps bash nonexistent_cmd
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required commands: nonexistent_cmd"* ]]
}

@test "common: check_deps reports multiple missing commands" {
  command() {
    if [[ "$1" == "-v" && ("$2" == "foo" || "$2" == "bar") ]]; then return 1; fi
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
  }
  run check_deps foo bar
  [ "$status" -eq 1 ]
  [[ "$output" == *"foo"* ]]
  [[ "$output" == *"bar"* ]]
}

@test "common: load_senders sources sender modules" {
  load_senders
  declare -f tg_send_message >/dev/null
  declare -f mx_send_message >/dev/null
  declare -f ntfy_send >/dev/null
}

@test "common: load_senders handles missing directory gracefully" {
  SENDERS_DIR="${TEST_TMPDIR}/nonexistent_senders"
  run load_senders
  [ "$status" -eq 0 ]
}

@test "common: load_senders handles empty directory" {
  SENDERS_DIR="${TEST_TMPDIR}/empty_senders"
  mkdir -p "${SENDERS_DIR}"
  run load_senders
  [ "$status" -eq 0 ]
}

@test "common: load_messages sources all message modules without prefix" {
  load_messages
  declare -f login_message_telegram >/dev/null
  declare -f high_load_message_telegram >/dev/null
}

@test "common: load_messages with login- prefix loads only login templates" {
  load_messages "login-"
  declare -f login_message_telegram >/dev/null
  declare -f login_message_ntfy >/dev/null
  ! declare -f high_load_message_telegram >/dev/null 2>&1
}

@test "common: load_messages with high-load- prefix loads only high-load templates" {
  load_messages "high-load-"
  declare -f high_load_message_telegram >/dev/null
  ! declare -f login_message_telegram >/dev/null 2>&1
}

@test "common: load_messages handles missing directory gracefully" {
  MESSAGES_DIR="${TEST_TMPDIR}/nonexistent_messages"
  run load_messages
  [ "$status" -eq 0 ]
}

@test "common: load_messages handles nonexistent prefix" {
  run load_messages "nonexistent-prefix-"
  [ "$status" -eq 0 ]
}

@test "common: get_available_notifiers without prefix returns all notifiers" {
  run get_available_notifiers
  [ "$status" -eq 0 ]
  [[ "$output" == *"telegram"* ]]
  [[ "$output" == *"matrix"* ]]
  [[ "$output" == *"ntfy"* ]]
}

@test "common: get_available_notifiers with login- prefix returns login notifiers" {
  run get_available_notifiers "login-"
  [ "$status" -eq 0 ]
  [[ "$output" == *"telegram"* ]]
  [[ "$output" == *"matrix"* ]]
  [[ "$output" == *"ntfy"* ]]
}

@test "common: get_available_notifiers with high-load- prefix returns high-load notifiers" {
  run get_available_notifiers "high-load-"
  [ "$status" -eq 0 ]
  [[ "$output" == *"telegram"* ]]
  [[ "$output" == *"matrix"* ]]
  [[ "$output" == *"ntfy"* ]]
}

@test "common: get_available_notifiers with nonexistent prefix returns empty" {
  run get_available_notifiers "nonexistent-"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "common: get_configured_notifiers returns telegram when BOT_TOKEN set" {
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  run get_configured_notifiers
  [[ "$output" == *"telegram"* ]]
}

@test "common: get_configured_notifiers returns matrix when MATRIX_URL set" {
  MATRIX_URL="https://matrix.example.com"
  run get_configured_notifiers
  [[ "$output" == *"matrix"* ]]
}

@test "common: get_configured_notifiers returns ntfy when NTFY_URL set" {
  NTFY_URL="https://ntfy.sh"
  NTFY_TOPIC="test"
  run get_configured_notifiers
  [[ "$output" == *"ntfy"* ]]
}

@test "common: get_configured_notifiers returns all when all configured" {
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  MATRIX_URL="https://matrix.example.com"
  NTFY_URL="https://ntfy.sh"
  NTFY_TOPIC="test"
  run get_configured_notifiers
  [[ "$output" == *"telegram"* ]]
  [[ "$output" == *"matrix"* ]]
  [[ "$output" == *"ntfy"* ]]
}

@test "common: get_configured_notifiers returns empty when nothing set" {
  unset BOT_TOKEN CHAT_ID MATRIX_URL MATRIX_ROOM_ID MATRIX_ACCESS_TOKEN NTFY_URL NTFY_TOPIC
  set +u
  run get_configured_notifiers
  set -u
  [ -z "$output" ]
}
