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
  [[ $output == *"telegram"* ]]
  [[ $output == *"matrix"* ]]
  [[ $output == *"ntfy"* ]]
}

@test "get_configured_notifiers returns telegram when BOT_TOKEN set" {
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  run get_configured_notifiers
  [ "$status" -eq 0 ]
  [[ $output == *"telegram"* ]]
}

@test "get_configured_notifiers returns matrix when MATRIX_URL set" {
  MATRIX_URL="https://matrix.example.com"
  run get_configured_notifiers
  [ "$status" -eq 0 ]
  [[ $output == *"matrix"* ]]
}

@test "get_configured_notifiers returns ntfy when NTFY_URL set" {
  NTFY_URL="https://ntfy.sh"
  NTFY_TOPIC="test-topic"
  run get_configured_notifiers
  [ "$status" -eq 0 ]
  [[ $output == *"ntfy"* ]]
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
  [[ $output == *"not found"* ]] || [[ $output == *"Available:"* ]]
}

@test "dispatch_notifications fails when notifier not configured" {
  REQUESTED_NOTIFIERS="telegram"
  unset BOT_TOKEN CHAT_ID
  set +u
  run dispatch_notifications
  set -u
  [ "$status" -ne 0 ]
  [[ $output == *"not configured"* ]] || [[ $output == *"Configured:"* ]]
}

@test "dispatch_notifications succeeds with valid configured notifier" {
  REQUESTED_NOTIFIERS="telegram"
  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  CHAT_ID="-123456789"
  TOP_PROCS_FILE="${TEST_TMPDIR}/top_procs.txt"
  echo "test" >"${TOP_PROCS_FILE}"

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
  [[ $output == *"ERROR:"* ]]
}

@test "parse_args fails with invalid threshold" {
  run parse_args --threshold abc
  [ "$status" -eq 1 ]
  [[ $output == *"ERROR:"* ]]
}

@test "check_deps succeeds when all commands exist" {
  command() {
    if [[ $1 == "-v" ]]; then return 0; fi
    builtin command "$@"
  }
  run check_deps
  [ "$status" -eq 0 ]
}

@test "check_deps fails when commands are missing" {
  command() {
    if [[ $1 == "-v" && $2 == "awk" ]]; then return 1; fi
    if [[ $1 == "-v" ]]; then return 0; fi
    builtin command "$@"
  }
  run check_deps awk curl jq ps file stat
  [ "$status" -eq 1 ]
  [[ $output == *"Missing required commands: awk"* ]]
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
    if [[ $1 == "-E" && $3 == "/proc/meminfo" ]]; then
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
    if [[ $1 == "-v" && $2 == "systemctl" ]]; then return 0; fi
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
  [[ $output == *"Usage: high-load.sh"* ]]
  [[ $output == *"Options:"* ]]
  [[ $output == *"--threshold"* ]]
  [[ $output == *"--notifiers"* ]]
  [[ $output == *"Example:"* ]]
}

@test "collect_psi sets PSI_AVAILABLE to 0 or 1" {
  collect_psi
  [[ $PSI_AVAILABLE =~ ^[01]$ ]]
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
  local mock_top_file="${TEST_TMPDIR}/mock_top_procs.txt"
  local mock_raw_file="${TEST_TMPDIR}/mock_top_raw.txt"

  mktemp() {
    case "$1" in
    *raw*) printf '%s' "${mock_raw_file}" ;;
    *) printf '%s' "${mock_top_file}" ;;
    esac
  }

  top() {
    printf '%s\n' \
      'top - 12:00:00 up 1 day,  1:00,  0 users,  load average: 4.50, 4.00, 3.50' \
      'Tasks: 100 total,   1 running,  99 sleeping,   0 stopped,   0 zombie' \
      '%Cpu(s): 50.0 us, 10.0 sy,  0.0 ni, 40.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st' \
      'MiB Mem :   8192.0 total,   2048.0 free,   4096.0 used,   2048.0 buff/cache' \
      'MiB Swap:   2048.0 total,   2048.0 free,      0.0 used.   6000.0 avail Mem' \
      '' \
      'PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND' \
      '  1 root      20   0   25132  14760   9156 S   0.0   0.1  20:30.11 /sbin/init' \
      '100 www-data  20   0  987654  65432  12345 R  95.0   2.5   5:30.00 /usr/sbin/apache2' \
      '' \
      'top - 12:00:01 up 1 day,  1:01,  0 users,  load average: 4.45, 4.00, 3.50' \
      'Tasks: 100 total,   1 running,  99 sleeping,   0 stopped,   0 zombie' \
      '%Cpu(s): 50.0 us, 10.0 sy,  0.0 ni, 40.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st' \
      'MiB Mem :   8192.0 total,   2048.0 free,   4096.0 used,   2048.0 buff/cache' \
      'MiB Swap:   2048.0 total,   2048.0 free,      0.0 used.   6000.0 avail Mem' \
      '' \
      'PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND' \
      '  1 root      20   0   25132  14760   9156 S   0.0   0.1  20:30.11 /sbin/init' \
      '100 www-data  20   0  987654  65432  12345 R  95.0   2.5   5:30.00 /usr/sbin/apache2'
  }

  collect_top_procs
  [ -f "${TOP_PROCS_FILE}" ]
  [[ $(cat "${TOP_PROCS_FILE}") == *"apache2"* ]]
  rm -f "${TOP_PROCS_FILE}"
}

@test "collect_failed_services returns empty when systemctl unavailable" {
  command() {
    if [[ $1 == "-v" && $2 == "systemctl" ]]; then return 1; fi
    builtin command "$@"
  }
  collect_failed_services
  [ -z "$FAILED_SERVICES" ]
}

@test "collect_failed_services returns empty when no failures" {
  command() {
    if [[ $1 == "-v" && $2 == "systemctl" ]]; then return 0; fi
    builtin command "$@"
  }
  systemctl() { true; }
  collect_failed_services
  [ -z "$FAILED_SERVICES" ]
}

@test "main calls check_deps with awk curl jq ps file stat" {
  check_deps() { printf "DEPS_CALLED:%s\n" "$*"; }

  run main --threshold 5.0
  [[ $output == *"DEPS_CALLED:awk curl jq ps file stat"* ]]
}

@test "main fails when check_deps reports missing commands" {
  check_deps() { die "Missing required commands: jq"; }

  run main --threshold 5.0
  [ "$status" -eq 1 ]
  [[ $output == *"Missing required commands: jq"* ]]
}

@test "main fails without --threshold" {
  run main
  [ "$status" -eq 1 ]
  [[ $output == *"--threshold is required"* ]]
}
