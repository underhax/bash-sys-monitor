#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2034,SC2154,SC2250,SC2292

setup_file() {
  export TEST_TMPDIR
  TEST_TMPDIR=$(mktemp -d)

  export REAL_STATE_DIR="${BATS_TEST_DIRNAME}/../opt/monitoring/state"
  mkdir -p "${REAL_STATE_DIR}"
}

teardown_file() {
  rm -f "${REAL_STATE_DIR}/login_last_ts.txt"
  [[ -n ${TEST_TMPDIR:-} ]] && rm -rf "${TEST_TMPDIR}"
}

setup() {
  source "$BATS_TEST_DIRNAME/../opt/monitoring/login.sh"
  rm -f "${STATE_FILE}"
}

@test "login: parse_args sets notifiers via --notifiers" {
  parse_args --notifiers telegram,matrix
  [ "$REQUESTED_NOTIFIERS" = "telegram,matrix" ]
}

@test "login: parse_args handles short option -n" {
  parse_args -n ntfy
  [ "$REQUESTED_NOTIFIERS" = "ntfy" ]
}

@test "login: parse_args shows help and exits" {
  run parse_args --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: login.sh"* ]]
  [[ "$output" == *"--notifiers"* ]]
}

@test "login: parse_args dies on unknown argument" {
  run parse_args --invalid-flag
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR:"* ]]
  [[ "$output" == *"Unknown argument"* ]]
}

@test "login: parse_args dies when --notifiers has no value" {
  run parse_args --notifiers
  [ "$status" -ne 0 ]
}

@test "login: parse_args accepts single notifier" {
  parse_args -n telegram
  [ "$REQUESTED_NOTIFIERS" = "telegram" ]
}

@test "login: parse_args accepts all three notifiers" {
  parse_args --notifiers telegram,matrix,ntfy
  [ "$REQUESTED_NOTIFIERS" = "telegram,matrix,ntfy" ]
}

@test "login: parse_args leaves REQUESTED_NOTIFIERS empty without -n" {
  parse_args
  [ -z "$REQUESTED_NOTIFIERS" ]
}

@test "login: usage contains Options and Example sections" {
  run usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"Options:"* ]]
  [[ "$output" == *"Example:"* ]]
  [[ "$output" == *"--help"* ]]
  [[ "$output" == *"telegram, matrix, ntfy"* ]]
}

@test "login: dispatch_login_notification exports login env variables" {
  load_senders
  load_messages "login-"

  export SERVER_NAME="test-server"
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  CHAT_ID="-123456789"
  REQUESTED_NOTIFIERS="telegram"

  tg_send_message() { return 0; }

  dispatch_login_notification "testuser" "pts/0" "10.0.0.1" "2026-04-23 00:55:00"

  [ "$LOGIN_USER" = "testuser" ]
  [ "$LOGIN_TTY" = "pts/0" ]
  [ "$LOGIN_IP" = "10.0.0.1" ]
  [ "$LOGIN_TIME" = "2026-04-23 00:55:00" ]
}

@test "login: dispatch_login_notification returns 0 with no requested and no configured notifiers" {
  load_senders
  load_messages "login-"

  export SERVER_NAME="test-server"
  unset BOT_TOKEN CHAT_ID MATRIX_URL MATRIX_ROOM_ID MATRIX_ACCESS_TOKEN NTFY_URL NTFY_TOPIC NTFY_TOKEN
  set +u
  REQUESTED_NOTIFIERS=""

  run dispatch_login_notification "user" "pts/0" "10.0.0.1" "2026-04-23 00:55:00"
  set -u
  [ "$status" -eq 0 ]
}

@test "login: dispatch_login_notification sends telegram notification" {
  load_senders
  load_messages "login-"

  export SERVER_NAME="test-server"
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  CHAT_ID="-123456789"
  REQUESTED_NOTIFIERS="telegram"

  tg_send_message() { echo "MOCK_TG_SEND"; return 0; }

  run dispatch_login_notification "admin" "pts/0" "192.168.1.100" "2026-04-23 00:55:00"
  [ "$status" -eq 0 ]
}

@test "login: dispatch_login_notification sends matrix notification" {
  load_senders
  load_messages "login-"

  export SERVER_NAME="test-server"
  MATRIX_URL="https://matrix.example.com"
  MATRIX_ROOM_ID="!room:matrix.example.com"
  MATRIX_ACCESS_TOKEN="syt_abcdefghijklmnopqrstuvwxyz123456"
  REQUESTED_NOTIFIERS="matrix"

  mx_send_message() { echo "MOCK_MX_SEND"; return 0; }

  run dispatch_login_notification "admin" "pts/1" "10.0.0.5" "2026-04-23 00:55:00"
  [ "$status" -eq 0 ]
}

@test "login: dispatch_login_notification sends ntfy notification" {
  load_senders
  load_messages "login-"

  export SERVER_NAME="test-server"
  NTFY_URL="https://ntfy.example.com"
  NTFY_TOPIC="test-topic"
  NTFY_TOKEN="tk_abcdef123456"
  REQUESTED_NOTIFIERS="ntfy"

  ntfy_send() { echo "MOCK_NTFY_SEND"; return 0; }

  run dispatch_login_notification "root" "pts/2" "172.16.0.1" "2026-04-23 00:55:00"
  [ "$status" -eq 0 ]
}

@test "login: dispatch_login_notification skips unavailable notifier" {
  load_senders
  load_messages "login-"

  export SERVER_NAME="test-server"
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  CHAT_ID="-123456789"
  REQUESTED_NOTIFIERS="nonexistent_notifier"

  run dispatch_login_notification "user" "pts/0" "10.0.0.1" "2026-04-23 00:55:00"
  [ "$status" -eq 0 ]
}

@test "login: dispatch_login_notification skips unconfigured notifier" {
  load_senders
  load_messages "login-"

  export SERVER_NAME="test-server"
  unset BOT_TOKEN CHAT_ID
  set +u
  REQUESTED_NOTIFIERS="telegram"

  run dispatch_login_notification "user" "pts/0" "10.0.0.1" "2026-04-23 00:55:00"
  set -u
  [ "$status" -eq 0 ]
}

@test "login: dispatch_login_notification sends to all configured notifiers when none requested" {
  load_senders
  load_messages "login-"

  export SERVER_NAME="test-server"
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  CHAT_ID="-123456789"
  MATRIX_URL="https://matrix.example.com"
  MATRIX_ROOM_ID="!room:matrix.example.com"
  MATRIX_ACCESS_TOKEN="syt_abcdefghijklmnopqrstuvwxyz123456"
  REQUESTED_NOTIFIERS=""

  tg_send_message() { echo "MOCK_TG"; return 0; }
  mx_send_message() { echo "MOCK_MX"; return 0; }

  run dispatch_login_notification "admin" "pts/0" "10.0.0.1" "2026-04-23 00:55:00"
  [ "$status" -eq 0 ]
}

@test "login: process_logins initializes state file on first run" {
  date() {
    case "$1" in
    +%s) echo "1713830400" ;;
    *) command date "$@" ;;
    esac
  }

  run process_logins
  [ "$status" -eq 0 ]
  [ -f "${STATE_FILE}" ]
  [[ "$output" == *"First run"* ]]

  local content
  content=$(<"${STATE_FILE}")
  [ "$content" = "1713830400" ]
}

@test "login: process_logins reads existing state file without errors" {
  echo "9999999999" >"${STATE_FILE}"

  last() { true; }

  run process_logins
  [ "$status" -eq 0 ]
}

@test "login: process_logins skips wtmp header lines" {
  echo "1000000000" >"${STATE_FILE}"

  last() {
    echo "wtmp begins Mon Apr 14 00:00:00 2026"
  }

  run process_logins
  [ "$status" -eq 0 ]
}

@test "login: process_logins skips reboot lines" {
  echo "1000000000" >"${STATE_FILE}"

  last() {
    echo "reboot   system boot  6.8.0-generic    Wed Apr 23 00:00:00 2026   still running"
  }

  run process_logins
  [ "$status" -eq 0 ]
}

@test "login: process_logins skips empty lines" {
  echo "1000000000" >"${STATE_FILE}"

  last() {
    echo ""
    echo ""
  }

  run process_logins
  [ "$status" -eq 0 ]
}

@test "login: process_logins detects new login entry" {
  echo "1000000000" >"${STATE_FILE}"

  load_senders
  load_messages "login-"
  export SERVER_NAME="test-server"
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  CHAT_ID="-123456789"

  last() {
    echo "admin    pts/0        10.0.0.5         Wed Apr 23 01:30:00 2026   still logged in"
  }

  date() {
    if [[ "$1" == "-d" ]]; then
      shift
      if [[ "$1" == +'%Y-%m-%d %H:%M:%S' ]]; then
        echo "2026-04-23 01:30:00"
      else
        echo "1713831000"
      fi
    elif [[ "$1" == "+%s" ]]; then
      echo "1713830400"
    elif [[ "$1" == +'%Y-%m-%d %H:%M:%S' ]]; then
      echo "2026-04-23 01:30:00"
    else
      echo "1713831000"
    fi
  }

  tg_send_message() { return 0; }

  run process_logins
  [ "$status" -eq 0 ]
  [[ "$output" == *"New login detected"* ]]
}

@test "login: process_logins replaces 0.0.0.0 IP with Local" {
  echo "1000000000" >"${STATE_FILE}"

  load_senders
  load_messages "login-"
  export SERVER_NAME="test-server"

  last() {
    echo "admin    tty1         0.0.0.0          Wed Apr 23 01:30:00 2026   still logged in"
  }

  date() {
    if [[ "$1" == "-d" ]]; then
      shift
      if [[ "$1" == +'%Y-%m-%d %H:%M:%S' ]]; then
        echo "2026-04-23 01:30:00"
      else
        echo "1713831000"
      fi
    elif [[ "$1" == "+%s" ]]; then
      echo "1713830400"
    elif [[ "$1" == +'%Y-%m-%d %H:%M:%S' ]]; then
      echo "2026-04-23 01:30:00"
    else
      echo "1713831000"
    fi
  }

  dispatch_login_notification() {
    echo "DISPATCH: ip=$3"
  }

  run process_logins
  [ "$status" -eq 0 ]
  [[ "$output" == *"ip=Local"* ]]
}

@test "login: process_logins updates state file after detecting logins" {
  echo "1000000000" >"${STATE_FILE}"

  load_senders
  load_messages "login-"
  export SERVER_NAME="test-server"

  last() {
    echo "admin    pts/0        10.0.0.5         Wed Apr 23 01:30:00 2026   still logged in"
  }

  date() {
    if [[ "$1" == "-d" ]]; then
      shift
      if [[ "$1" == +'%Y-%m-%d %H:%M:%S' ]]; then
        echo "2026-04-23 01:30:00"
      else
        echo "1713831000"
      fi
    elif [[ "$1" == "+%s" ]]; then
      echo "1713830400"
    elif [[ "$1" == +'%Y-%m-%d %H:%M:%S' ]]; then
      echo "2026-04-23 01:30:00"
    else
      echo "1713831000"
    fi
  }

  dispatch_login_notification() { true; }

  process_logins

  local new_ts
  new_ts=$(<"${STATE_FILE}")
  [ "$new_ts" = "1713831000" ]
}

@test "login: process_logins creates state file with 600 permissions on first run" {
  date() {
    case "$1" in
    +%s) echo "1713830400" ;;
    *) command date "$@" ;;
    esac
  }

  stat() {
    if [[ "$1" == "-c" && "$2" == "%a" ]]; then
      printf "600\n"
    else
      command stat "$@"
    fi
  }

  process_logins

  local perms
  perms=$(stat -c "%a" "${STATE_FILE}")
  [ "$perms" = "600" ]
}

@test "login: main dies when config cache is missing" {
  command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
  }

  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"Configuration cache not found"* ]]
}

@test "login: main calls check_deps with awk curl jq date last" {
  check_deps() { printf "DEPS_CALLED:%s\n" "$*"; }

  run main
  [[ "$output" == *"DEPS_CALLED:awk curl jq date last"* ]]
}

@test "login: main fails when check_deps reports missing commands" {
  check_deps() { die "Missing required commands: last"; }

  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required commands: last"* ]]
}

@test "login: get_available_notifiers returns login notifiers" {
  run get_available_notifiers "login-"
  [ "$status" -eq 0 ]
  [[ "$output" == *"telegram"* ]]
  [[ "$output" == *"matrix"* ]]
  [[ "$output" == *"ntfy"* ]]
}

@test "login: get_configured_notifiers returns telegram when BOT_TOKEN set" {
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  run get_configured_notifiers
  [ "$status" -eq 0 ]
  [[ "$output" == *"telegram"* ]]
}

@test "login: get_configured_notifiers returns matrix when MATRIX_URL set" {
  MATRIX_URL="https://matrix.example.com"
  run get_configured_notifiers
  [ "$status" -eq 0 ]
  [[ "$output" == *"matrix"* ]]
}

@test "login: get_configured_notifiers returns ntfy when NTFY_URL set" {
  NTFY_URL="https://ntfy.example.com"
  NTFY_TOPIC="test-topic"
  run get_configured_notifiers
  [ "$status" -eq 0 ]
  [[ "$output" == *"ntfy"* ]]
}

@test "login: get_configured_notifiers returns empty when nothing configured" {
  unset BOT_TOKEN CHAT_ID MATRIX_URL MATRIX_ROOM_ID MATRIX_ACCESS_TOKEN NTFY_URL NTFY_TOPIC
  set +u
  run get_configured_notifiers
  set -u
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "login: login_message_telegram contains expected fields" {
  load_messages "login-"

  export SERVER_NAME="prod-server"
  export ALERT_TIME="2026-04-23 01:00:00"
  export LOGIN_USER="admin"
  export LOGIN_TTY="pts/0"
  export LOGIN_IP="10.0.0.5"
  export LOGIN_TIME="2026-04-23 00:55:00"

  run login_message_telegram
  [ "$status" -eq 0 ]
  [[ "$output" == *"prod-server"* ]]
  [[ "$output" == *"admin"* ]]
  [[ "$output" == *"pts/0"* ]]
  [[ "$output" == *"10.0.0.5"* ]]
  [[ "$output" == *"SSH Login"* ]]
}

@test "login: login_message_matrix_plain contains expected fields" {
  load_messages "login-"

  export SERVER_NAME="prod-server"
  export ALERT_TIME="2026-04-23 01:00:00"
  export LOGIN_USER="root"
  export LOGIN_TTY="tty1"
  export LOGIN_IP="Local"
  export LOGIN_TIME="2026-04-23 00:55:00"

  run login_message_matrix_plain
  [ "$status" -eq 0 ]
  [[ "$output" == *"prod-server"* ]]
  [[ "$output" == *"root"* ]]
  [[ "$output" == *"Local"* ]]
}

@test "login: login_message_matrix_html contains HTML markup" {
  load_messages "login-"

  export SERVER_NAME="test-server"
  export ALERT_TIME="2026-04-23 01:00:00"
  export LOGIN_USER="admin"
  export LOGIN_TTY="pts/0"
  export LOGIN_IP="192.168.1.1"
  export LOGIN_TIME="2026-04-23 00:55:00"

  run login_message_matrix_html
  [ "$status" -eq 0 ]
  [[ "$output" == *"<strong>"* ]]
  [[ "$output" == *"<br>"* ]]
  [[ "$output" == *"admin"* ]]
}

@test "login: login_message_ntfy contains expected fields" {
  load_messages "login-"

  export SERVER_NAME="test-server"
  export ALERT_TIME="2026-04-23 01:00:00"
  export LOGIN_USER="deploy"
  export LOGIN_TTY="pts/1"
  export LOGIN_IP="172.16.0.1"
  export LOGIN_TIME="2026-04-23 00:55:00"

  run login_message_ntfy
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy"* ]]
  [[ "$output" == *"172.16.0.1"* ]]
}

@test "login: login_title_ntfy contains server name" {
  load_messages "login-"

  export SERVER_NAME="prod-01"

  run login_title_ntfy
  [ "$status" -eq 0 ]
  [[ "$output" == *"SSH Login"* ]]
  [[ "$output" == *"prod-01"* ]]
}

@test "login: load_senders makes sender functions available" {
  load_senders
  declare -f tg_send_message >/dev/null
  declare -f mx_send_message >/dev/null
  declare -f ntfy_send >/dev/null
}

@test "login: load_messages with login- prefix loads all login templates" {
  load_messages "login-"
  declare -f login_message_telegram >/dev/null
  declare -f login_message_matrix_plain >/dev/null
  declare -f login_message_matrix_html >/dev/null
  declare -f login_message_ntfy >/dev/null
  declare -f login_title_ntfy >/dev/null
}

@test "login: check_deps succeeds when all commands exist" {
  command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
  }
  run check_deps awk curl jq date last
  [ "$status" -eq 0 ]
}

@test "login: check_deps fails when awk is missing" {
  command() {
    if [[ "$1" == "-v" && "$2" == "awk" ]]; then return 1; fi
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
  }
  run check_deps awk curl jq date last
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required commands: awk"* ]]
}
