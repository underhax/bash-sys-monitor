#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2034,SC2154,SC2250,SC2292

setup_file() {
  export TEST_TMPDIR
  TEST_TMPDIR=$(mktemp -d)
}

teardown_file() {
  [[ -n ${TEST_TMPDIR:-} ]] && rm -rf "${TEST_TMPDIR}"
}

setup() {
  source "$BATS_TEST_DIRNAME/../opt/monitoring/high-load.sh"
}

@test "parse_args sets variables correctly" {
  parse_args --threshold 5.0 --notifiers telegram
  [ "$THRESHOLD" = "5.0" ]
  [ "$REQUESTED_NOTIFIERS" = "telegram" ]
}

@test "should_alert respects threshold (load < threshold)" {
  THRESHOLD="5.0"
  LOAD_1="4.0"
  PSI_AVAILABLE=0
  run should_alert
  [ "$status" -eq 1 ]
}

@test "should_alert returns true when load > threshold and no PSI" {
  THRESHOLD="4.0"
  LOAD_1="5.0"
  PSI_AVAILABLE=0
  run should_alert
  [ "$status" -eq 0 ]
}

@test "should_alert suppresses false positive when PSI is low (10s is high but 60s is 0)" {
  THRESHOLD="4.0"
  LOAD_1="5.0"
  PSI_AVAILABLE=1
  PSI_CPU_SOME_AVG10="25.50"
  PSI_CPU_SOME_AVG60="0.00"
  PSI_IO_SOME_AVG10="0.00"
  PSI_IO_SOME_AVG60="0.00"
  PSI_MEM_SOME_AVG10="0.00"
  PSI_MEM_SOME_AVG60="0.00"
  run should_alert
  [ "$status" -eq 1 ]
}

@test "should_alert returns true when PSI confirms load (both 10s and 60s high)" {
  THRESHOLD="4.0"
  LOAD_1="5.0"
  PSI_AVAILABLE=1
  PSI_CPU_SOME_AVG10="25.50"
  PSI_CPU_SOME_AVG60="6.00"
  PSI_IO_SOME_AVG10="0.00"
  PSI_IO_SOME_AVG60="0.00"
  PSI_MEM_SOME_AVG10="0.00"
  PSI_MEM_SOME_AVG60="0.00"
  run should_alert
  [ "$status" -eq 0 ]
}

@test "get_available_notifiers returns notifier names from messages directory" {
  run get_available_notifiers
  [ "$status" -eq 0 ]
  [[ "$output" == *"telegram"* ]]
  [[ "$output" == *"matrix"* ]]
  [[ "$output" == *"ntfy"* ]]
}

@test "get_configured_notifiers returns telegram when BOT_TOKEN set" {
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  run get_configured_notifiers
  [ "$status" -eq 0 ]
  [[ "$output" == *"telegram"* ]]
}

@test "get_configured_notifiers returns matrix when MATRIX_URL set" {
  MATRIX_URL="https://matrix.example.com"
  run get_configured_notifiers
  [ "$status" -eq 0 ]
  [[ "$output" == *"matrix"* ]]
}

@test "get_configured_notifiers returns ntfy when NTFY_URL set" {
  NTFY_URL="https://ntfy.sh"
  NTFY_TOPIC="test-topic"
  run get_configured_notifiers
  [ "$status" -eq 0 ]
  [[ "$output" == *"ntfy"* ]]
}

@test "get_configured_notifiers returns empty when no notifiers configured" {
  unset BOT_TOKEN CHAT_ID MATRIX_URL MATRIX_ROOM_ID MATRIX_ACCESS_TOKEN NTFY_URL NTFY_TOPIC
  set +u
  run get_configured_notifiers
  set -u
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dispatch_notifications fails when no notifiers available" {
  get_available_notifiers() { true; }
  REQUESTED_NOTIFIERS=""
  run dispatch_notifications
  [ "$status" -ne 0 ]
}

@test "dispatch_notifications fails on invalid notifier name" {
  REQUESTED_NOTIFIERS="invalid_notifier"
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  run dispatch_notifications
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"Available:"* ]]
}

@test "dispatch_notifications fails when notifier not configured" {
  REQUESTED_NOTIFIERS="telegram"
  unset BOT_TOKEN CHAT_ID
  set +u
  run dispatch_notifications
  set -u
  [ "$status" -ne 0 ]
  [[ "$output" == *"not configured"* ]] || [[ "$output" == *"Configured:"* ]]
}

@test "dispatch_notifications succeeds with valid configured notifier" {
  REQUESTED_NOTIFIERS="telegram"
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  CHAT_ID="-123456789"
  TOP_PROCS_FILE="${TEST_TMPDIR}/top_procs.txt"
  echo "test" > "${TOP_PROCS_FILE}"

  load_senders
  load_messages

  tg_send_message() { echo "mock tg_send_message: $1"; }
  tg_send_file() { echo "mock tg_send_file: $1"; }

  run dispatch_notifications
  [ "$status" -eq 0 ]
}

@test "parse_args fails without threshold" {
  run parse_args --notifiers telegram
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR:"* ]]
}

@test "parse_args fails with invalid threshold" {
  run parse_args --threshold abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR:"* ]]
}

@test "check_deps succeeds when all commands exist" {
  command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
  }
  run check_deps
  [ "$status" -eq 0 ]
}

@test "check_deps fails when commands are missing" {
  command() {
    if [[ "$1" == "-v" && "$2" == "awk" ]]; then return 1; fi
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
  }
  run check_deps awk curl jq ps file stat
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required commands: awk"* ]]
}

@test "collect_disk_space parses df output" {
  df() {
    echo "Filesystem 1M-blocks Used Available Use% Mounted on"
    echo "/dev/root 100000 50000 50000 50% /"
  }
  collect_disk_space
  [ "$ROOT_FS_FREE_GB" = "48.83" ]
  [ "$ROOT_FS_PCT" = "50%" ]
}

@test "collect_memory parses meminfo correctly" {
  grep() {
    if [[ "$1" == "-E" && "$3" == "/proc/meminfo" ]]; then
      echo "MemTotal: 8388608 kB"
      echo "MemFree: 4194304 kB"
      echo "Buffers: 1048576 kB"
      echo "Cached: 1048576 kB"
      echo "SReclaimable: 0 kB"
      echo "SwapTotal: 2097152 kB"
      echo "SwapFree: 2097152 kB"
    else
      command grep "$@"
    fi
  }
  collect_memory
  [ "$MEMORY_TOTAL" = "8.00" ]
  [ "$MEMORY_ACTIVE_USED" = "2.00" ]
  [ "$MEMORY_USAGE_PCT" = "25.0" ]
}

@test "collect_failed_services gets failed systemctl units" {
  command() {
    if [[ "$1" == "-v" && "$2" == "systemctl" ]]; then return 0; fi
    builtin command "$@"
  }
  systemctl() {
    echo "nginx.service loaded failed failed Nginx Web Server"
    echo "mysql.service loaded failed failed MySQL Database"
  }
  collect_failed_services
  [ "$FAILED_SERVICES" = "nginx.service, mysql.service" ]
}

@test "usage contains required sections" {
  run usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: high-load.sh"* ]]
  [[ "$output" == *"Options:"* ]]
  [[ "$output" == *"--threshold"* ]]
  [[ "$output" == *"--notifiers"* ]]
  [[ "$output" == *"Example:"* ]]
}

@test "collect_psi sets PSI_AVAILABLE to 0 or 1" {
  collect_psi
  [[ "$PSI_AVAILABLE" =~ ^[01]$ ]]
}

@test "collect_psi initializes all PSI variables" {
  set +u
  collect_psi
  [[ -v PSI_CPU_SOME_AVG10 ]]
  [[ -v PSI_IO_SOME_AVG10 ]]
  [[ -v PSI_MEM_SOME_AVG10 ]]
  set -u
}

@test "collect_top_procs creates temp file with process data" {
  mktemp() { command mktemp "${TEST_TMPDIR}/high-load-top-XXXXXX.txt"; }
  ps() {
    echo "USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND"
    echo "root         1  0.1  0.0  12345  6789 ?        Ss   00:00   0:01 /sbin/init"
    echo "www-data   100 95.0  2.5 987654 65432 ?        R    00:01   5:30 /usr/sbin/apache2"
  }
  head() { command head "$@"; }

  collect_top_procs
  [ -f "${TOP_PROCS_FILE}" ]
  [[ $(cat "${TOP_PROCS_FILE}") == *"apache2"* ]]
  rm -f "${TOP_PROCS_FILE}"
}

@test "collect_failed_services returns empty when systemctl unavailable" {
  command() {
    if [[ "$1" == "-v" && "$2" == "systemctl" ]]; then return 1; fi
    builtin command "$@"
  }
  collect_failed_services
  [ -z "$FAILED_SERVICES" ]
}

@test "collect_failed_services returns empty when no failures" {
  command() {
    if [[ "$1" == "-v" && "$2" == "systemctl" ]]; then return 0; fi
    builtin command "$@"
  }
  systemctl() { true; }
  collect_failed_services
  [ -z "$FAILED_SERVICES" ]
}

@test "main calls check_deps with awk curl jq ps file stat" {
  check_deps() { printf "DEPS_CALLED:%s\n" "$*"; }

  run main --threshold 5.0
  [[ "$output" == *"DEPS_CALLED:awk curl jq ps file stat"* ]]
}

@test "main fails when check_deps reports missing commands" {
  check_deps() { die "Missing required commands: jq"; }

  run main --threshold 5.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required commands: jq"* ]]
}

@test "main fails without --threshold" {
  run main
  [ "$status" -eq 1 ]
  [[ "$output" == *"--threshold is required"* ]]
}
