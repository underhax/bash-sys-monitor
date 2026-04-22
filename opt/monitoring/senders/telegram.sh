#!/usr/bin/env bash

tg_send_message() {
  local text="$1"
  local token="${2:-${BOT_TOKEN}}"
  local chat_id="${3:-${CHAT_ID}}"

  local encoded
  encoded=$(jq -rn --arg t "${text}" '$t | @uri')

  local http_code
  http_code=$(curl -fsSL \
    --max-time 15 \
    --retry 3 \
    --retry-delay 2 \
    --retry-all-errors \
    -w "%{http_code}" \
    -o /dev/null \
    "https://api.telegram.org/bot${token}/sendMessage?chat_id=${chat_id}&text=${encoded}&parse_mode=Markdown")

  [[ ${http_code} == "200" ]] || {
    printf "ERROR [telegram]: sendMessage returned HTTP %s\n" "${http_code}" >&2
    return 1
  }
  return 0
}

tg_send_file() {
  local file_path="$1"
  local token="${2:-${BOT_TOKEN}}"
  local chat_id="${3:-${CHAT_ID}}"

  [[ -f ${file_path} ]] || {
    printf "ERROR [telegram]: File not found: %s\n" "${file_path}" >&2
    return 1
  }

  local http_code
  http_code=$(curl -fsSL \
    --max-time 30 \
    --retry 3 \
    --retry-delay 2 \
    --retry-all-errors \
    -w "%{http_code}" \
    -o /dev/null \
    -F "chat_id=${chat_id}" \
    -F "document=@${file_path};filename=$(basename "${file_path}")" \
    "https://api.telegram.org/bot${token}/sendDocument")

  [[ ${http_code} == "200" ]] || {
    printf "ERROR [telegram]: sendDocument returned HTTP %s\n" "${http_code}" >&2
    return 1
  }
  return 0
}
