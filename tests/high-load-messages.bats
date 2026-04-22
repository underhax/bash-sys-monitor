#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2034,SC2154,SC2250,SC2292

setup() {
  source "$BATS_TEST_DIRNAME/../opt/monitoring/high-load.sh"
  load_messages "high-load-"

  export SERVER_NAME="prod-server-01"
  export ALERT_TIME="2026-04-23 01:00:00"
  export LOAD_1="12.50" LOAD_5="8.30" LOAD_15="5.10"
  export PROCS_RUNNING="15" PROCS_BLOCKED="3"
  export CPU_USAGE="92.5"
  export MEMORY_ACTIVE_USED="14.20" MEMORY_TOTAL="16.00" MEMORY_USAGE_PCT="88.8"
  export SWAP_USED="1.50" SWAP_TOTAL="4.00" SWAP_USAGE_PCT="37.5"
  export DISK_READ_MB="25.30" DISK_WRITE_MB="12.40"
  export NET_RX_MBPS="150.20" NET_TX_MBPS="45.60"
  export ROOT_FS_FREE_GB="18.50" ROOT_FS_PCT="62%"
  export FAILED_SERVICES=""

  export PSI_AVAILABLE=1
  export PSI_CPU_SOME_AVG10="25.50" PSI_CPU_SOME_AVG60="6.00"
  export PSI_IO_SOME_AVG10="10.20" PSI_IO_SOME_AVG60="3.50"
  export PSI_IO_FULL_AVG10="5.10" PSI_IO_FULL_AVG60="1.20"
  export PSI_MEM_SOME_AVG10="8.30" PSI_MEM_SOME_AVG60="2.10"
  export PSI_MEM_FULL_AVG10="3.40" PSI_MEM_FULL_AVG60="0.50"
}

@test "high-load-messages: _tg_escape escapes underscores" {
  run _tg_escape "my_server_name"
  [ "$status" -eq 0 ]
  [[ "$output" == *"my\_server\_name"* ]]
}

@test "high-load-messages: _tg_escape escapes asterisks and backticks" {
  run _tg_escape "test*bold*and\`code\`"
  [ "$status" -eq 0 ]
  [[ "$output" != *'*bold*'* ]] || [[ "$output" == *'\*'* ]]
}

@test "high-load-messages: _tg_escape preserves plain text" {
  run _tg_escape "simple text 123"
  [ "$status" -eq 0 ]
  [ "$output" = "simple text 123" ]
}

@test "high-load-messages: _tg_psi_section shows PSI data when available" {
  PSI_AVAILABLE=1
  run _tg_psi_section
  [ "$status" -eq 0 ]
  [[ "$output" == *"PSI"* ]]
  [[ "$output" == *"CPU some"* ]]
  [[ "$output" == *"IO some"* ]]
  [[ "$output" == *"Mem some"* ]]
  [[ "$output" == *"25.50"* ]]
}

@test "high-load-messages: _tg_psi_section shows unavailable when PSI off" {
  PSI_AVAILABLE=0
  run _tg_psi_section
  [ "$status" -eq 0 ]
  [[ "$output" == *"unavailable"* ]]
}

@test "high-load-messages: telegram message contains all metric fields" {
  run high_load_message_telegram
  [ "$status" -eq 0 ]
  [[ "$output" == *"High Load"* ]]
  [[ "$output" == *"12.50"* ]]
  [[ "$output" == *"92.5"* ]]
  [[ "$output" == *"14.20"* ]]
  [[ "$output" == *"16.00"* ]]
  [[ "$output" == *"25.30"* ]]
  [[ "$output" == *"150.20"* ]]
  [[ "$output" == *"18.50"* ]]
}

@test "high-load-messages: telegram message includes failed services when set" {
  FAILED_SERVICES="nginx.service, mysql.service"
  run high_load_message_telegram
  [ "$status" -eq 0 ]
  [[ "$output" == *"Failed Services"* ]]
  [[ "$output" == *"nginx"* ]]
}

@test "high-load-messages: telegram message omits failed services when empty" {
  FAILED_SERVICES=""
  run high_load_message_telegram
  [ "$status" -eq 0 ]
  [[ "$output" != *"Failed Services"* ]]
}

@test "high-load-messages: _mx_psi_html contains HTML tags when PSI available" {
  PSI_AVAILABLE=1
  run _mx_psi_html
  [ "$status" -eq 0 ]
  [[ "$output" == *"<strong>"* ]]
  [[ "$output" == *"<br>"* ]]
  [[ "$output" == *"CPU some"* ]]
}

@test "high-load-messages: _mx_psi_html shows unavailable when PSI off" {
  PSI_AVAILABLE=0
  run _mx_psi_html
  [ "$status" -eq 0 ]
  [[ "$output" == *"<em>"* ]]
  [[ "$output" == *"unavailable"* ]]
}

@test "high-load-messages: _mx_psi_plain shows plain text when PSI available" {
  PSI_AVAILABLE=1
  run _mx_psi_plain
  [ "$status" -eq 0 ]
  [[ "$output" == *"CPU some"* ]]
  [[ "$output" == *"IO full"* ]]
  [[ "$output" == *"Mem full"* ]]
}

@test "high-load-messages: _mx_psi_plain shows unavailable when PSI off" {
  PSI_AVAILABLE=0
  run _mx_psi_plain
  [ "$status" -eq 0 ]
  [[ "$output" == *"unavailable"* ]]
}

@test "high-load-messages: matrix plain contains all fields" {
  run high_load_message_matrix_plain
  [ "$status" -eq 0 ]
  [[ "$output" == *"prod-server-01"* ]]
  [[ "$output" == *"12.50"* ]]
  [[ "$output" == *"92.5"* ]]
  [[ "$output" == *"Root FS"* ]]
}

@test "high-load-messages: matrix html contains HTML markup" {
  run high_load_message_matrix_html
  [ "$status" -eq 0 ]
  [[ "$output" == *"<strong>"* ]]
  [[ "$output" == *"<br>"* ]]
  [[ "$output" == *"prod-server-01"* ]]
  [[ "$output" == *"CPU"* ]]
}

@test "high-load-messages: matrix plain includes failed services when set" {
  FAILED_SERVICES="redis.service"
  run high_load_message_matrix_plain
  [[ "$output" == *"Failed Services"* ]]
  [[ "$output" == *"redis"* ]]
}

@test "high-load-messages: _ntfy_psi_section shows data when PSI available" {
  PSI_AVAILABLE=1
  run _ntfy_psi_section
  [ "$status" -eq 0 ]
  [[ "$output" == *"CPU some"* ]]
  [[ "$output" == *"IO full"* ]]
}

@test "high-load-messages: _ntfy_psi_section shows unavailable when PSI off" {
  PSI_AVAILABLE=0
  run _ntfy_psi_section
  [ "$status" -eq 0 ]
  [[ "$output" == *"unavailable"* ]]
}

@test "high-load-messages: ntfy message contains all fields" {
  run high_load_message_ntfy
  [ "$status" -eq 0 ]
  [[ "$output" == *"12.50"* ]]
  [[ "$output" == *"92.5"* ]]
  [[ "$output" == *"14.20"* ]]
  [[ "$output" == *"Root FS"* ]]
}

@test "high-load-messages: ntfy title contains server name" {
  run high_load_title_ntfy
  [ "$status" -eq 0 ]
  [[ "$output" == *"High Load"* ]]
  [[ "$output" == *"prod-server-01"* ]]
}

@test "high-load-messages: ntfy message includes failed services" {
  FAILED_SERVICES="postgres.service"
  run high_load_message_ntfy
  [[ "$output" == *"Failed Services"* ]]
  [[ "$output" == *"postgres"* ]]
}
