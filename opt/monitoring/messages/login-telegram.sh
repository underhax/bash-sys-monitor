#!/usr/bin/env bash
# shellcheck disable=SC2154
# Rationale: Variables are exported by login.sh at runtime before sourcing this module

login_message_telegram() {
  cat <<EOF
🔐 *SSH Login:* \`${SERVER_NAME}\`
Alert Time: \`${ALERT_TIME}\`

*User:* \`${LOGIN_USER}\`
*TTY:* \`${LOGIN_TTY}\`
*IP Address:* \`${LOGIN_IP}\`
*Login Time:* \`${LOGIN_TIME}\`
EOF
}
