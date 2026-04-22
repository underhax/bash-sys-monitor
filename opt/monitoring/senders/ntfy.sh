#!/usr/bin/env bash

ntfy_send() {
  local message="$1"
  local url="${2:-${NTFY_URL}}"
  local topic="${3:-${NTFY_TOPIC}}"
  local token="${4:-${NTFY_TOKEN}}"
  local title="${5:-}"

  local endpoint="${url}/${topic}"

  local curl_args=(
    -fsSL
    --max-time 30
    --retry 3
    --retry-delay 2
    --retry-all-errors
    -w "%{http_code}"
    -o /dev/null
  )

  if [[ -n ${token} ]]; then
    curl_args+=(-H "Authorization: Bearer ${token}")
  fi

  if [[ -n ${title} ]]; then
    curl_args+=(-H "Title: ${title}")
  fi

  local http_code
  http_code=$(curl "${curl_args[@]}" -d "${message}" "${endpoint}")

  [[ ${http_code} == "200" ]] || {
    printf "ERROR [ntfy]: message returned HTTP %s\n" "${http_code}" >&2
    return 1
  }
  return 0
}

ntfy_send_file() {
  local file_path="$1"
  local url="${2:-${NTFY_URL}}"
  local topic="${3:-${NTFY_TOPIC}}"
  local token="${4:-${NTFY_TOKEN}}"
  local title="${5:-}"

  [[ -f ${file_path} ]] || {
    printf "ERROR [ntfy]: File not found: %s\n" "${file_path}" >&2
    return 1
  }

  local endpoint="${url}/${topic}"
  local filename
  filename=$(basename "${file_path}")

  local curl_args=(
    -fsSL
    --max-time 30
    --retry 3
    --retry-delay 2
    --retry-all-errors
    -w "%{http_code}"
    -o /dev/null
  )

  if [[ -n ${token} ]]; then
    curl_args+=(-H "Authorization: Bearer ${token}")
  fi

  if [[ -n ${title} ]]; then
    curl_args+=(-H "Title: ${title}")
  fi

  curl_args+=(-H "Filename: ${filename}")

  local http_code
  http_code=$(curl "${curl_args[@]}" -T "${file_path}" "${endpoint}")

  [[ ${http_code} == "200" ]] || {
    printf "ERROR [ntfy]: file upload returned HTTP %s\n" "${http_code}" >&2
    return 1
  }
  return 0
}
