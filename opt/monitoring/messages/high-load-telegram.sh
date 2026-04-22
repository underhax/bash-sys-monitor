#!/usr/bin/env bash
# shellcheck disable=SC2154
# Rationale: Template variables (SERVER_NAME, LOAD_1, CPU_USAGE, etc.) are explicitly populated by the core script prior to dynamically sourcing this message template.

_tg_escape() {
  local text="$1"
  printf '%s' "${text}" | sed 's/[_*`\[]/\\&/g'
}

_tg_psi_section() {
  [[ ${PSI_AVAILABLE:-0} -eq 1 ]] || {
    printf '_(PSI unavailable)_'
    return
  }

  printf '*PSI (10s / 60s avg):*\n'
  printf 'CPU some: %s%% / %s%%\n' "${PSI_CPU_SOME_AVG10:-n/a}" "${PSI_CPU_SOME_AVG60:-n/a}"
  printf 'IO some: %s%% / %s%%\n' "${PSI_IO_SOME_AVG10:-n/a}" "${PSI_IO_SOME_AVG60:-n/a}"
  printf 'IO full: %s%% / %s%%\n' "${PSI_IO_FULL_AVG10:-n/a}" "${PSI_IO_FULL_AVG60:-n/a}"
  printf 'Mem some: %s%% / %s%%\n' "${PSI_MEM_SOME_AVG10:-n/a}" "${PSI_MEM_SOME_AVG60:-n/a}"
  printf 'Mem full: %s%% / %s%%' "${PSI_MEM_FULL_AVG10:-n/a}" "${PSI_MEM_FULL_AVG60:-n/a}"
}

high_load_message_telegram() {
  local server
  server=$(_tg_escape "${SERVER_NAME}")

  local psi_block
  psi_block=$(_tg_psi_section)

  local failed_block=""
  if [[ -n ${FAILED_SERVICES:-} ]]; then
    local escaped_failed
    escaped_failed=$(_tg_escape "${FAILED_SERVICES}")
    failed_block=$(printf '\n*Failed Services:* %s' "${escaped_failed}")
  fi

  printf '💥 *High Load: %s*

*Time:* %s
*Load Avg:* %s, %s, %s
*Procs:* %s running, %s blocked
*CPU:* %s%%
*Memory:* %s GB / %s GB (%s%%)
*Swap:* %s GB / %s GB (%s%%)
*Disk I/O:* Read %s MB/s, Write %s MB/s
*Network:* In %s Mbps, Out %s Mbps
*Root FS:* %s GB free (%s used)%s

%s' \
    "${server}" \
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
    "${psi_block}"
}
