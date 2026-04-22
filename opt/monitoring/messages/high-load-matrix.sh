#!/usr/bin/env bash
# shellcheck disable=SC2154
# Rationale: Template variables (SERVER_NAME, LOAD_1, CPU_USAGE, etc.) are explicitly populated by the core script prior to dynamically sourcing this message template.

_mx_psi_html() {
  [[ ${PSI_AVAILABLE:-0} -eq 1 ]] || {
    printf '<em>PSI unavailable</em>'
    return
  }

  printf '<strong>PSI (10s / 60s avg):</strong><br>'
  printf 'CPU some: %s%% / %s%%<br>' "${PSI_CPU_SOME_AVG10:-n/a}" "${PSI_CPU_SOME_AVG60:-n/a}"
  printf 'IO some: %s%% / %s%%<br>' "${PSI_IO_SOME_AVG10:-n/a}" "${PSI_IO_SOME_AVG60:-n/a}"
  printf 'IO full: %s%% / %s%%<br>' "${PSI_IO_FULL_AVG10:-n/a}" "${PSI_IO_FULL_AVG60:-n/a}"
  printf 'Mem some: %s%% / %s%%<br>' "${PSI_MEM_SOME_AVG10:-n/a}" "${PSI_MEM_SOME_AVG60:-n/a}"
  printf 'Mem full: %s%% / %s%%' "${PSI_MEM_FULL_AVG10:-n/a}" "${PSI_MEM_FULL_AVG60:-n/a}"
}

_mx_psi_plain() {
  [[ ${PSI_AVAILABLE:-0} -eq 1 ]] || {
    printf 'PSI unavailable'
    return
  }

  printf 'PSI (10s / 60s avg):\n'
  printf 'CPU some: %s%% / %s%%\n' "${PSI_CPU_SOME_AVG10:-n/a}" "${PSI_CPU_SOME_AVG60:-n/a}"
  printf 'IO some: %s%% / %s%%\n' "${PSI_IO_SOME_AVG10:-n/a}" "${PSI_IO_SOME_AVG60:-n/a}"
  printf 'IO full: %s%% / %s%%\n' "${PSI_IO_FULL_AVG10:-n/a}" "${PSI_IO_FULL_AVG60:-n/a}"
  printf 'Mem some: %s%% / %s%%\n' "${PSI_MEM_SOME_AVG10:-n/a}" "${PSI_MEM_SOME_AVG60:-n/a}"
  printf 'Mem full: %s%% / %s%%' "${PSI_MEM_FULL_AVG10:-n/a}" "${PSI_MEM_FULL_AVG60:-n/a}"
}

high_load_message_matrix_plain() {
  local psi_plain
  psi_plain=$(_mx_psi_plain)

  local failed_block=""
  if [[ -n ${FAILED_SERVICES:-} ]]; then
    failed_block=$(printf '\nFailed Services: %s' "${FAILED_SERVICES}")
  fi

  printf '💥 High Load: %s

Time: %s
Load Avg: %s, %s, %s
Procs: %s running, %s blocked
CPU: %s%%
Memory: %s GB / %s GB (%s%%)
Swap: %s GB / %s GB (%s%%)
Disk I/O: Read %s MB/s, Write %s MB/s
Network: In %s Mbps, Out %s Mbps
Root FS: %s GB free (%s used)%s

%s' \
    "${SERVER_NAME}" \
    "${ALERT_TIME}" \
    "${LOAD_1}" "${LOAD_5}" "${LOAD_15}" \
    "${PROCS_RUNNING}" "${PROCS_BLOCKED}" \
    "${CPU_USAGE}" \
    "${MEMORY_ACTIVE_USED}" "${MEMORY_TOTAL}" "${MEMORY_USAGE_PCT}" \
    "${SWAP_USED}" "${SWAP_TOTAL}" "${SWAP_USAGE_PCT}" \
    "${DISK_READ_MB}" "${DISK_WRITE_MB}" \
    "${NET_RX_MBPS}" "${NET_TX_MBPS}" \
    "${ROOT_FS_FREE_GB}" "${ROOT_FS_PCT}" \
    "${failed_block}" \
    "${psi_plain}"
}

high_load_message_matrix_html() {
  local psi_html
  psi_html=$(_mx_psi_html)

  local failed_block=""
  if [[ -n ${FAILED_SERVICES:-} ]]; then
    failed_block=$(printf '<br><strong>Failed Services:</strong> %s' "${FAILED_SERVICES}")
  fi

  printf '<strong>💥 High Load: %s</strong><br><br>
<strong>Time:</strong> %s<br>
<strong>Load Avg:</strong> %s, %s, %s<br>
<strong>Procs:</strong> %s running, %s blocked<br>
<strong>CPU:</strong> %s%%<br>
<strong>Memory:</strong> %s GB / %s GB (%s%%)<br>
<strong>Swap:</strong> %s GB / %s GB (%s%%)<br>
<strong>Disk I/O:</strong> Read %s MB/s, Write %s MB/s<br>
<strong>Network:</strong> In %s Mbps, Out %s Mbps<br>
<strong>Root FS:</strong> %s GB free (%s used)%s<br><br>
%s' \
    "${SERVER_NAME}" \
    "${ALERT_TIME}" \
    "${LOAD_1}" "${LOAD_5}" "${LOAD_15}" \
    "${PROCS_RUNNING}" "${PROCS_BLOCKED}" \
    "${CPU_USAGE}" \
    "${MEMORY_ACTIVE_USED}" "${MEMORY_TOTAL}" "${MEMORY_USAGE_PCT}" \
    "${SWAP_USED}" "${SWAP_TOTAL}" "${SWAP_USAGE_PCT}" \
    "${DISK_READ_MB}" "${DISK_WRITE_MB}" \
    "${NET_RX_MBPS}" "${NET_TX_MBPS}" \
    "${ROOT_FS_FREE_GB}" "${ROOT_FS_PCT}" \
    "${failed_block}" \
    "${psi_html}"
}
