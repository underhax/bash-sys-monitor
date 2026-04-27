#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2034,SC2154,SC2250,SC2292

setup_file() {
  export TEST_TMPDIR
  TEST_TMPDIR=$(mktemp -d)
  echo "test file content" >"${TEST_TMPDIR}/test_doc.txt"
}

teardown_file() {
  [[ -n ${TEST_TMPDIR:-} ]] && rm -rf "${TEST_TMPDIR}"
}

setup() {
  export SCRIPT_DIR="${BATS_TEST_DIRNAME}/../opt/monitoring"
  export SENDERS_DIR="${SCRIPT_DIR}/senders"
  source "${SCRIPT_DIR}/lib/common.sh"
  source "${SENDERS_DIR}/telegram.sh"
  source "${SENDERS_DIR}/matrix.sh"
  source "${SENDERS_DIR}/ntfy.sh"

  BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  CHAT_ID="-123456789"
  MATRIX_URL="https://matrix.example.com"
  MATRIX_ROOM_ID="!room:matrix.example.com"
  MATRIX_ACCESS_TOKEN="syt_abcdefghijklmnopqrstuvwxyz123456"
  NTFY_URL="https://ntfy.example.com"
  NTFY_TOPIC="test-topic"
  NTFY_TOKEN="tk_abcdef123456"

  export CURL_ARGS_FILE="${TEST_TMPDIR}/curl_args.log"
  export CURL_CALL_FILE="${TEST_TMPDIR}/curl_calls.log"
  rm -f "${CURL_ARGS_FILE}" "${CURL_CALL_FILE}"
}

@test "senders: tg_send_message succeeds on HTTP 200" {
  curl() { echo "200"; }
  run tg_send_message "hello world"
  [ "$status" -eq 0 ]
}

@test "senders: tg_send_message fails on HTTP 403" {
  curl() { echo "403"; }
  run tg_send_message "hello world"
  [ "$status" -eq 1 ]
  [[ $output == *"ERROR [telegram]"* ]]
  [[ $output == *"403"* ]]
}

@test "senders: tg_send_message uses provided token and chat_id" {
  curl() {
    printf '%s\n' "$*" >>"${CURL_ARGS_FILE}"
    echo "200"
  }
  tg_send_message "test" "CUSTOM_TOKEN" "CUSTOM_CHAT"
  local args
  args=$(<"${CURL_ARGS_FILE}")
  [[ $args == *"botCUSTOM_TOKEN"* ]]
  [[ $args == *"chat_id=CUSTOM_CHAT"* ]]
}

@test "senders: tg_send_file succeeds with valid file" {
  curl() { echo "200"; }
  run tg_send_file "${TEST_TMPDIR}/test_doc.txt"
  [ "$status" -eq 0 ]
}

@test "senders: tg_send_file fails when file not found" {
  run tg_send_file "/nonexistent/file.txt"
  [ "$status" -eq 1 ]
  [[ $output == *"File not found"* ]]
}

@test "senders: tg_send_file fails on HTTP error" {
  curl() { echo "500"; }
  run tg_send_file "${TEST_TMPDIR}/test_doc.txt"
  [ "$status" -eq 1 ]
  [[ $output == *"ERROR [telegram]"* ]]
}

@test "senders: mx_txn_id produces timestamp_random format" {
  run mx_txn_id
  [ "$status" -eq 0 ]
  [[ $output =~ ^[0-9]+_[0-9]+$ ]]
}

@test "senders: mx_txn_id generates unique values" {
  local id1 id2
  id1=$(mx_txn_id)
  id2=$(mx_txn_id)
  [[ $id1 != "$id2" ]]
}

@test "senders: mx_send_message succeeds on HTTP 200" {
  curl() { echo "200"; }
  run mx_send_message "plain text" "<b>html</b>"
  [ "$status" -eq 0 ]
}

@test "senders: mx_send_message fails on HTTP error" {
  curl() { echo "401"; }
  run mx_send_message "plain text" "<b>html</b>"
  [ "$status" -eq 1 ]
  [[ $output == *"ERROR [matrix]"* ]]
}

@test "senders: mx_send_message uses provided credentials" {
  curl() {
    printf '%s\n' "$*" >>"${CURL_ARGS_FILE}"
    echo "200"
  }
  mx_send_message "text" "html" "https://custom.matrix.org" "!custom:room" "custom_token"
  local args
  args=$(<"${CURL_ARGS_FILE}")
  [[ $args == *"custom.matrix.org"* ]]
  [[ $args == *"Bearer custom_token"* ]]
}

@test "senders: mx_upload_file fails when file not found" {
  run mx_upload_file "/nonexistent/file.txt"
  [ "$status" -eq 1 ]
  [[ $output == *"File not found"* ]]
}

@test "senders: mx_upload_file returns content_uri on success" {
  curl() { echo '{"content_uri": "mxc://example.com/abc123"}'; }
  run mx_upload_file "${TEST_TMPDIR}/test_doc.txt"
  [ "$status" -eq 0 ]
  [[ $output == *"mxc://example.com/abc123"* ]]
}

@test "senders: mx_upload_file fails on missing content_uri" {
  curl() { echo '{"error": "upload failed"}'; }
  run mx_upload_file "${TEST_TMPDIR}/test_doc.txt"
  [ "$status" -eq 1 ]
  [[ $output == *"missing content_uri"* ]]
}

@test "senders: mx_upload_file fails on curl error" {
  curl() { return 1; }
  run mx_upload_file "${TEST_TMPDIR}/test_doc.txt"
  [ "$status" -eq 1 ]
  [[ $output == *"curl failed"* ]]
}

@test "senders: mx_send_file fails when file not found" {
  run mx_send_file "/nonexistent/file.txt"
  [ "$status" -eq 1 ]
}

@test "senders: mx_send_file succeeds with mocked upload and send" {
  curl() {
    local call_num
    call_num=$(wc -l <"${CURL_CALL_FILE}" 2>/dev/null || echo 0)
    call_num=$((call_num + 1))
    echo "${call_num}" >>"${CURL_CALL_FILE}"
    case ${call_num} in
    1) echo '{"content_uri": "mxc://example.com/abc123"}' ;; # upload
    2) echo "200" ;;                                         # send
    esac
  }
  stat() {
    if [[ $1 == "-c%s" ]]; then
      echo "1024"
    else
      command stat "$@"
    fi
  }
  run mx_send_file "${TEST_TMPDIR}/test_doc.txt"
  [ "$status" -eq 0 ]
}

@test "senders: ntfy_send succeeds on HTTP 200" {
  curl() { echo "200"; }
  run ntfy_send "test message"
  [ "$status" -eq 0 ]
}

@test "senders: ntfy_send fails on HTTP error" {
  curl() { echo "429"; }
  run ntfy_send "test message"
  [ "$status" -eq 1 ]
  [[ $output == *"ERROR [ntfy]"* ]]
  [[ $output == *"429"* ]]
}

@test "senders: ntfy_send includes auth header when token provided" {
  curl() {
    printf '%s\n' "$*" >>"${CURL_ARGS_FILE}"
    echo "200"
  }
  ntfy_send "msg" "https://ntfy.sh" "topic" "tk_secret123"
  local args
  args=$(<"${CURL_ARGS_FILE}")
  [[ $args == *"Bearer tk_secret123"* ]]
}

@test "senders: ntfy_send includes title header when provided" {
  curl() {
    printf '%s\n' "$*" >>"${CURL_ARGS_FILE}"
    echo "200"
  }
  ntfy_send "msg" "https://ntfy.sh" "topic" "tk_secret123" "Alert Title"
  local args
  args=$(<"${CURL_ARGS_FILE}")
  [[ $args == *"Title: Alert Title"* ]]
}

@test "senders: ntfy_send omits auth header without token" {
  unset NTFY_TOKEN
  set +u
  curl() {
    printf '%s\n' "$*" >>"${CURL_ARGS_FILE}"
    echo "200"
  }
  ntfy_send "msg" "https://ntfy.sh" "topic" ""
  set -u
  local args
  args=$(<"${CURL_ARGS_FILE}")
  [[ $args != *"Bearer"* ]]
}

@test "senders: ntfy_send_file fails when file not found" {
  run ntfy_send_file "/nonexistent/file.txt"
  [ "$status" -eq 1 ]
  [[ $output == *"File not found"* ]]
}

@test "senders: ntfy_send_file succeeds with valid file" {
  curl() { echo "200"; }
  run ntfy_send_file "${TEST_TMPDIR}/test_doc.txt"
  [ "$status" -eq 0 ]
}

@test "senders: ntfy_send_file fails on HTTP error" {
  curl() { echo "500"; }
  run ntfy_send_file "${TEST_TMPDIR}/test_doc.txt"
  [ "$status" -eq 1 ]
  [[ $output == *"ERROR [ntfy]"* ]]
}

@test "senders: ntfy_send_file includes filename header" {
  curl() {
    printf '%s\n' "$*" >>"${CURL_ARGS_FILE}"
    echo "200"
  }
  ntfy_send_file "${TEST_TMPDIR}/test_doc.txt" "https://ntfy.sh" "topic" "" ""
  local args
  args=$(<"${CURL_ARGS_FILE}")
  [[ $args == *"Filename: test_doc.txt"* ]]
}
