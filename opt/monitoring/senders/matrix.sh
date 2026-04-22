#!/usr/bin/env bash

mx_txn_id() {
  local date_val
  date_val=$(date +%s%N)
  printf '%s_%s' "${date_val}" "${RANDOM}"
}

mx_send_message() {
  local body_plain="$1"
  local body_html="$2"
  local url="${3:-${MATRIX_URL}}"
  local room_id="${4:-${MATRIX_ROOM_ID}}"
  local access_token="${5:-${MATRIX_ACCESS_TOKEN}}"

  local txn_id
  txn_id=$(mx_txn_id)

  local endpoint="${url}/_matrix/client/v3/rooms/${room_id}/send/m.room.message/${txn_id}"

  local payload
  payload=$(jq -n \
    --arg plain "${body_plain}" \
    --arg html "${body_html}" \
    '{
      msgtype: "m.text",
      body: $plain,
      format: "org.matrix.custom.html",
      formatted_body: $html
    }')

  local http_code
  http_code=$(curl -fsSL \
    --max-time 15 \
    --retry 3 \
    --retry-delay 2 \
    --retry-all-errors \
    -w "%{http_code}" \
    -o /dev/null \
    -X PUT \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${endpoint}")

  [[ ${http_code} == "200" ]] || {
    printf "ERROR [matrix]: send message returned HTTP %s\n" "${http_code}" >&2
    return 1
  }
  return 0
}

mx_upload_file() {
  local file_path="$1"
  local url="${2:-${MATRIX_URL}}"
  local access_token="${3:-${MATRIX_ACCESS_TOKEN}}"

  [[ -f ${file_path} ]] || {
    printf "ERROR [matrix]: File not found: %s\n" "${file_path}" >&2
    return 1
  }

  local mime_type
  mime_type=$(file -b --mime-type "${file_path}")

  local filename
  filename=$(basename "${file_path}")

  local upload_response content_uri
  upload_response=$(curl -fsSL \
    --max-time 30 \
    --retry 3 \
    --retry-delay 2 \
    --retry-all-errors \
    -X POST \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: ${mime_type}" \
    --data-binary "@${file_path}" \
    "${url}/_matrix/media/v3/upload?filename=${filename}") || {
    printf "ERROR [matrix]: File upload curl failed\n" >&2
    return 1
  }

  content_uri=$(jq -re '.content_uri' <<<"${upload_response}") || {
    printf "ERROR [matrix]: Upload response missing content_uri: %s\n" "${upload_response}" >&2
    return 1
  }

  printf '%s' "${content_uri}"
}

mx_send_file() {
  local file_path="$1"
  local url="${2:-${MATRIX_URL}}"
  local room_id="${3:-${MATRIX_ROOM_ID}}"
  local access_token="${4:-${MATRIX_ACCESS_TOKEN}}"

  local content_uri
  content_uri=$(mx_upload_file "${file_path}" "${url}" "${access_token}") || return 1

  local file_size mime_type filename txn_id
  file_size=$(stat -c%s "${file_path}")
  mime_type=$(file -b --mime-type "${file_path}")
  filename=$(basename "${file_path}")
  txn_id=$(mx_txn_id)

  local endpoint="${url}/_matrix/client/v3/rooms/${room_id}/send/m.room.message/${txn_id}"

  local payload
  payload=$(jq -n \
    --arg fname "${filename}" \
    --arg mime "${mime_type}" \
    --argjson size "${file_size}" \
    --arg uri "${content_uri}" \
    '{
      msgtype: "m.file",
      body: $fname,
      filename: $fname,
      info: { size: $size, mimetype: $mime },
      url: $uri
    }')

  local http_code
  http_code=$(curl -fsSL \
    --max-time 15 \
    --retry 3 \
    --retry-delay 2 \
    --retry-all-errors \
    -w "%{http_code}" \
    -o /dev/null \
    -X PUT \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${endpoint}")

  [[ ${http_code} == "200" ]] || {
    printf "ERROR [matrix]: send file returned HTTP %s\n" "${http_code}" >&2
    return 1
  }
  return 0
}
