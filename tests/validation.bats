#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2034,SC2154

setup() {
  source "$BATS_TEST_DIRNAME/../opt/monitoring/lib/validation.sh"

  stat() {
    if [[ $1 == "-c" && $2 == "%u" ]]; then
      echo "${EUID:-$(id -u)}"
    elif [[ $1 == "-c" && $2 == "%a" ]]; then
      if [[ $3 == *"invalid_perms"* ]]; then
        echo "644"
      else
        echo "600"
      fi
    else
      command stat "$@"
    fi
  }

  grep() {
    if [[ $1 == "-qP" ]]; then
      command grep -qE "$2" "$3"
    else
      command grep "$@"
    fi
  }
}

setup_file() {
  export TEST_TMPDIR
  TEST_TMPDIR=$(mktemp -d)

  export VALID_CONFIG="${TEST_TMPDIR}/valid.conf"
  cat >"${VALID_CONFIG}" <<'EOF'
SERVER_NAME="test-server"
BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
CHAT_ID="-123456789"
EOF
  chmod 600 "${VALID_CONFIG}"

  export MATRIX_CONFIG="${TEST_TMPDIR}/matrix.conf"
  cat >"${MATRIX_CONFIG}" <<'EOF'
SERVER_NAME="test-server"
MATRIX_URL="https://matrix.example.com"
MATRIX_ROOM_ID="!roomid:matrix.example.com"
MATRIX_ACCESS_TOKEN="syt_abcdefghijklmnopqrstuvwxyz123456"
EOF
  chmod 600 "${MATRIX_CONFIG}"

  export NTFY_CONFIG="${TEST_TMPDIR}/ntfy.conf"
  cat >"${NTFY_CONFIG}" <<'EOF'
SERVER_NAME="test-server"
NTFY_URL="https://ntfy.example.com"
NTFY_TOPIC="test-topic"
NTFY_TOKEN="tk_abcdef123456"
EOF
  chmod 600 "${NTFY_CONFIG}"

  export ALL_CONFIG="${TEST_TMPDIR}/all.conf"
  cat >"${ALL_CONFIG}" <<'EOF'
SERVER_NAME="test-server"
BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
CHAT_ID="-123456789"
MATRIX_URL="https://matrix.example.com"
MATRIX_ROOM_ID="!roomid:matrix.example.com"
MATRIX_ACCESS_TOKEN="syt_abcdefghijklmnopqrstuvwxyz123456"
NTFY_URL="https://ntfy.example.com"
NTFY_TOPIC="test-topic"
NTFY_TOKEN="tk_abcdef123456"
EOF
  chmod 600 "${ALL_CONFIG}"

  export NO_NOTIFIER_CONFIG="${TEST_TMPDIR}/no_notifier.conf"
  cat >"${NO_NOTIFIER_CONFIG}" <<'EOF'
SERVER_NAME="test-server"
EOF
  chmod 600 "${NO_NOTIFIER_CONFIG}"

  export INVALID_PERMS_CONFIG="${TEST_TMPDIR}/invalid_perms.conf"
  cat >"${INVALID_PERMS_CONFIG}" <<'EOF'
SERVER_NAME="test-server"
BOT_TOKEN="000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
CHAT_ID="-123456789"
EOF
  chmod 644 "${INVALID_PERMS_CONFIG}"
}

teardown_file() {
  [[ -n ${TEST_TMPDIR:-} ]] && rm -rf "${TEST_TMPDIR}"
}

@test "validate_bot_config succeeds with telegram config" {
  run validate_bot_config "${VALID_CONFIG}" "${TEST_TMPDIR}/cache"
  [ "$status" -eq 0 ]
}

@test "validate_bot_config succeeds with matrix config" {
  run validate_bot_config "${MATRIX_CONFIG}" "${TEST_TMPDIR}/cache"
  [ "$status" -eq 0 ]
}

@test "validate_bot_config succeeds with ntfy config" {
  run validate_bot_config "${NTFY_CONFIG}" "${TEST_TMPDIR}/cache"
  [ "$status" -eq 0 ]
}

@test "validate_bot_config succeeds with all notifiers" {
  run validate_bot_config "${ALL_CONFIG}" "${TEST_TMPDIR}/cache"
  [ "$status" -eq 0 ]
}

@test "validate_bot_config succeeds with no notifiers configured" {
  run validate_bot_config "${NO_NOTIFIER_CONFIG}" "${TEST_TMPDIR}/cache"
  [ "$status" -eq 0 ]
}

@test "validate_bot_config fails on invalid file permissions" {
  run validate_bot_config "${INVALID_PERMS_CONFIG}" "${TEST_TMPDIR}/cache"
  [ "$status" -eq 1 ]
}

@test "validate_bot_config fails on missing file" {
  run validate_bot_config "/nonexistent/path/bot.conf" "${TEST_TMPDIR}/cache"
  [ "$status" -eq 1 ]
}

@test "validate_bot_config fails without SERVER_NAME" {
  local empty_config="${TEST_TMPDIR}/empty.conf"
  echo "" >"${empty_config}"
  chmod 600 "${empty_config}"
  run validate_bot_config "${empty_config}" "${TEST_TMPDIR}/cache"
  [ "$status" -eq 1 ]
}

@test "urlencode encodes special characters" {
  run urlencode "hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "hello%20world" ]
}

@test "urlencode preserves alphanumeric and safe chars" {
  run urlencode "abc123-_ .~"
  [ "$status" -eq 0 ]
  [ "$output" = "abc123-_%20.~" ]
}

@test "validate_ipv4 accepts valid IP" {
  run validate_ipv4 "192.168.1.1"
  [ "$status" -eq 0 ]
}

@test "validate_ipv4 accepts localhost" {
  run validate_ipv4 "127.0.0.1"
  [ "$status" -eq 0 ]
}

@test "validate_ipv4 accepts boundary values" {
  run validate_ipv4 "0.0.0.0"
  [ "$status" -eq 0 ]
  run validate_ipv4 "255.255.255.255"
  [ "$status" -eq 0 ]
}

@test "validate_ipv4 rejects invalid format" {
  run validate_ipv4 "192.168.1"
  [ "$status" -eq 1 ]
  run validate_ipv4 "192.168.1.1.1"
  [ "$status" -eq 1 ]
}

@test "validate_ipv4 rejects out of range" {
  run validate_ipv4 "256.0.0.1"
  [ "$status" -eq 1 ]
  run validate_ipv4 "192.168.1.300"
  [ "$status" -eq 1 ]
}

@test "validate_ipv4 rejects leading zeros" {
  run validate_ipv4 "192.168.01.1"
  [ "$status" -eq 1 ]
  run validate_ipv4 "192.168.001.1"
  [ "$status" -eq 1 ]
}

@test "validate_ipv4 rejects non-numeric" {
  run validate_ipv4 "192.168.abc.1"
  [ "$status" -eq 1 ]
}

@test "validate_ipv6 accepts loopback" {
  run validate_ipv6 "::1"
  [ "$status" -eq 0 ]
}

@test "validate_ipv6 accepts unspecified address" {
  run validate_ipv6 "::"
  [ "$status" -eq 0 ]
}

@test "validate_ipv6 accepts compressed form" {
  run validate_ipv6 "2001:db8::1"
  [ "$status" -eq 0 ]
  run validate_ipv6 "fe80::1"
  [ "$status" -eq 0 ]
}

@test "validate_ipv6 accepts full form" {
  run validate_ipv6 "2001:0db8:0000:0000:0000:0000:0000:0001"
  [ "$status" -eq 0 ]
}

@test "validate_ipv6 accepts link-local" {
  run validate_ipv6 "fe80::1"
  [ "$status" -eq 0 ]
  run validate_ipv6 "fe80::1234:5678:90ab:cdef"
  [ "$status" -eq 0 ]
}

@test "validate_ipv6 accepts bracketed form" {
  run validate_ipv6 "[::1]"
  [ "$status" -eq 0 ]
  run validate_ipv6 "[2001:db8::1]"
  [ "$status" -eq 0 ]
}

@test "validate_ipv6 accepts trailing double colon" {
  run validate_ipv6 "2001:db8::"
  [ "$status" -eq 0 ]
}

@test "validate_ipv6 rejects double compression" {
  run validate_ipv6 "2001::db8::1"
  [ "$status" -eq 1 ]
  run validate_ipv6 "::1::"
  [ "$status" -eq 1 ]
}

@test "validate_ipv6 rejects invalid characters" {
  run validate_ipv6 "gggg::1"
  [ "$status" -eq 1 ]
  run validate_ipv6 "2001:db8::ghij"
  [ "$status" -eq 1 ]
}

@test "validate_ipv6 rejects too many hextets" {
  run validate_ipv6 "2001:db8:1:2:3:4:5:6:7"
  [ "$status" -eq 1 ]
}

@test "validate_ipv6 rejects too few hextets without ::" {
  run validate_ipv6 "2001:db8:1:2:3:4:5"
  [ "$status" -eq 1 ]
  run validate_ipv6 "2001:db8"
  [ "$status" -eq 1 ]
}

@test "validate_ipv6 rejects triple colon" {
  run validate_ipv6 ":::1"
  [ "$status" -eq 1 ]
}

@test "validate_ipv6 rejects leading single colon" {
  run validate_ipv6 ":1:2:3:4:5:6:7:8"
  [ "$status" -eq 1 ]
}

@test "validate_ipv6 rejects trailing single colon" {
  run validate_ipv6 "2001:db8:1:2:3:4:5:6:"
  [ "$status" -eq 1 ]
}

@test "validate_ipv6 rejects hextet too long" {
  run validate_ipv6 "2001:db8:12345::1"
  [ "$status" -eq 1 ]
}

@test "validate_domain accepts valid domains" {
  run validate_domain "example.com"
  [ "$status" -eq 0 ]
  run validate_domain "sub.example.com"
  [ "$status" -eq 0 ]
  run validate_domain "my-server-01.example.org"
  [ "$status" -eq 0 ]
}

@test "validate_domain rejects invalid chars" {
  run validate_domain "example com"
  [ "$status" -eq 1 ]
  run validate_domain "example#com"
  [ "$status" -eq 1 ]
}

@test "validate_domain rejects leading dash" {
  run validate_domain "-example.com"
  [ "$status" -eq 1 ]
}

@test "validate_domain rejects trailing dash" {
  run validate_domain "example-"
  [ "$status" -eq 1 ]
}

@test "validate_domain rejects double dots" {
  run validate_domain "example..com"
  [ "$status" -eq 1 ]
}

@test "validate_domain_ip accepts IPv4" {
  run validate_domain_ip "192.168.1.1"
  [ "$status" -eq 0 ]
}

@test "validate_domain_ip accepts IPv6" {
  run validate_domain_ip "::1"
  [ "$status" -eq 0 ]
  run validate_domain_ip "2001:db8::1"
  [ "$status" -eq 0 ]
}

@test "validate_domain_ip accepts domain" {
  run validate_domain_ip "example.com"
  [ "$status" -eq 0 ]
}

@test "validate_domain_ip accepts empty" {
  run validate_domain_ip ""
  [ "$status" -eq 0 ]
}

@test "validate_port accepts valid ports" {
  run validate_port "80"
  [ "$status" -eq 0 ]
  run validate_port "443"
  [ "$status" -eq 0 ]
  run validate_port "65535"
  [ "$status" -eq 0 ]
  run validate_port "1"
  [ "$status" -eq 0 ]
}

@test "validate_port accepts empty" {
  run validate_port ""
  [ "$status" -eq 0 ]
}

@test "validate_port rejects non-numeric" {
  run validate_port "abc"
  [ "$status" -eq 1 ]
}

@test "validate_port rejects out of range" {
  run validate_port "0"
  [ "$status" -eq 1 ]
  run validate_port "65536"
  [ "$status" -eq 1 ]
}

@test "validate_port handles leading zeros as decimal" {
  run validate_port "080"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "validate_domain_port accepts domain with port" {
  run validate_domain_port "example.com:8080"
  [ "$status" -eq 0 ]
}

@test "validate_domain_port accepts IPv4 with port" {
  run validate_domain_port "192.168.1.1:443"
  [ "$status" -eq 0 ]
}

@test "validate_domain_port accepts IPv6 with port" {
  run validate_domain_port "[::1]:8080"
  [ "$status" -eq 0 ]
  run validate_domain_port "[2001:db8::1]:443"
  [ "$status" -eq 0 ]
}

@test "validate_domain_port accepts IPv6 without port" {
  run validate_domain_port "::1"
  [ "$status" -eq 0 ]
  run validate_domain_port "[::1]"
  [ "$status" -eq 0 ]
}

@test "validate_domain_port accepts empty" {
  run validate_domain_port ""
  [ "$status" -eq 0 ]
}

@test "validate_domain_port rejects invalid port" {
  run validate_domain_port "example.com:99999"
  [ "$status" -eq 1 ]
}

@test "validate_url accepts http" {
  run validate_url "http://example.com"
  [ "$status" -eq 0 ]
}

@test "validate_url accepts https" {
  run validate_url "https://example.com"
  [ "$status" -eq 0 ]
}

@test "validate_url accepts port" {
  run validate_url "https://example.com:8080"
  [ "$status" -eq 0 ]
}

@test "validate_url accepts IPv6 host" {
  run validate_url "https://[::1]:8080"
  [ "$status" -eq 0 ]
}

@test "validate_url rejects non-http(s)" {
  run validate_url "ftp://example.com"
  [ "$status" -eq 1 ]
}

@test "validate_url rejects no scheme" {
  run validate_url "example.com"
  [ "$status" -eq 1 ]
}

@test "validate_matrix_room_id accepts v11 format with server" {
  run validate_matrix_room_id "!AbCdEfGhIj:matrix-example.tld"
  [ "$status" -eq 0 ]
  run validate_matrix_room_id "!room_name:matrix.org"
  [ "$status" -eq 0 ]
}

@test "validate_matrix_room_id accepts v12 format without server" {
  run validate_matrix_room_id "!0xRqYq5IIruJFFcCLhkzepUfk5m2InboNUkXe3ZTqPs"
  [ "$status" -eq 0 ]
  run validate_matrix_room_id "!AbCdEfGhIjklMnOpQrStUvWxYz1234567890"
  [ "$status" -eq 0 ]
}

@test "validate_matrix_room_id rejects missing exclamation" {
  run validate_matrix_room_id "abc123:example.com"
  [ "$status" -eq 1 ]
}

@test "validate_matrix_room_id rejects empty" {
  run validate_matrix_room_id ""
  [ "$status" -eq 1 ]
}

@test "validate_matrix_room_id rejects invalid chars" {
  run validate_matrix_room_id "!room#name:example.com"
  [ "$status" -eq 1 ]
}

@test "validate_bot_token accepts valid token" {
  run validate_bot_token "000000000:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  [ "$status" -eq 0 ]
}

@test "validate_bot_token rejects invalid token format" {
  run validate_bot_token "invalid-token"
  [ "$status" -eq 1 ]
}

@test "validate_bot_token rejects empty token" {
  run validate_bot_token ""
  [ "$status" -eq 1 ]
}

@test "validate_chat_id accepts valid chat id" {
  run validate_chat_id "123456789"
  [ "$status" -eq 0 ]
  run validate_chat_id "-1001234567890"
  [ "$status" -eq 0 ]
}

@test "validate_chat_id rejects invalid chat id" {
  run validate_chat_id "abc123"
  [ "$status" -eq 1 ]
}

@test "validate_chat_id rejects empty chat id" {
  run validate_chat_id ""
  [ "$status" -eq 1 ]
}

@test "validate_server_name accepts valid names" {
  run validate_server_name "my-server-01"
  [ "$status" -eq 0 ]
  run validate_server_name "prod.web.us-east"
  [ "$status" -eq 0 ]
  run validate_server_name "Server_Name.123"
  [ "$status" -eq 0 ]
  run validate_server_name "server name"
  [ "$status" -eq 0 ]
  run validate_server_name "server+name"
  [ "$status" -eq 0 ]
}

@test "validate_server_name rejects empty name" {
  run validate_server_name ""
  [ "$status" -eq 1 ]
  [[ $output == *"SERVER_NAME is not set"* ]]
}

@test "validate_server_name rejects CRLF injection" {
  run validate_server_name $'server\r\nX-Injected: true'
  [ "$status" -eq 1 ]
  [[ $output == *"SERVER_NAME format is invalid"* ]]
}

@test "validate_server_name rejects special chars" {
  run validate_server_name "server/../../etc"
  [ "$status" -eq 1 ]
  run validate_server_name 'server$(whoami)'
  [ "$status" -eq 1 ]
}

@test "validate_ntfy_topic accepts valid topic" {
  run validate_ntfy_topic "my-topic"
  [ "$status" -eq 0 ]
  run validate_ntfy_topic "server_alerts_01"
  [ "$status" -eq 0 ]
  run validate_ntfy_topic "MyTopic123"
  [ "$status" -eq 0 ]
}

@test "validate_ntfy_topic rejects empty topic" {
  run validate_ntfy_topic ""
  [ "$status" -eq 1 ]
  [[ $output == *"NTFY_TOPIC is not set"* ]]
}

@test "validate_ntfy_topic rejects CRLF injection" {
  run validate_ntfy_topic $'topic\r\nX-Attack: injected'
  [ "$status" -eq 1 ]
  [[ $output == *"NTFY_TOPIC format is invalid"* ]]
}

@test "validate_ntfy_topic rejects slashes and spaces" {
  run validate_ntfy_topic "topic/../../etc/passwd"
  [ "$status" -eq 1 ]
  run validate_ntfy_topic "topic with spaces"
  [ "$status" -eq 1 ]
}

@test "validate_ntfy_token accepts valid token" {
  run validate_ntfy_token "tk_abcdef123456"
  [ "$status" -eq 0 ]
}

@test "validate_ntfy_token accepts empty token" {
  run validate_ntfy_token ""
  [ "$status" -eq 0 ]
}

@test "validate_ntfy_token rejects invalid token" {
  run validate_ntfy_token "invalid-token"
  [ "$status" -eq 1 ]
}

@test "validate_matrix_access_token accepts valid token" {
  run validate_matrix_access_token "syt_abcdefghijklmnopqrstuvwxyz123456"
  [ "$status" -eq 0 ]
}

@test "validate_matrix_access_token rejects invalid token" {
  run validate_matrix_access_token "invalid-token"
  [ "$status" -eq 1 ]
}

@test "validate_matrix_access_token rejects empty token" {
  run validate_matrix_access_token ""
  [ "$status" -eq 1 ]
}

@test "validate_secure_config rejects unsafe subshells" {
  local unsafe_config="${TEST_TMPDIR}/unsafe.conf"
  cat >"${unsafe_config}" <<'EOF'
SERVER_NAME="test-server"
BOT_TOKEN="$(rm -rf /)"
EOF
  chmod 600 "${unsafe_config}"
  run validate_secure_config "${unsafe_config}"
  [ "$status" -eq 1 ]
}

@test "validate_secure_config rejects unsafe backticks" {
  local unsafe_config="${TEST_TMPDIR}/unsafe2.conf"
  cat >"${unsafe_config}" <<'EOF'
SERVER_NAME="test-server"
BOT_TOKEN="`rm -rf /`"
EOF
  chmod 600 "${unsafe_config}"
  run validate_secure_config "${unsafe_config}"
  [ "$status" -eq 1 ]
}
