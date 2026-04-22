#!/usr/bin/env bash
# shellcheck disable=SC2154
# Rationale: Variables (SERVER_NAME, ALERT_TIME, LOGIN_*) are exported by login.sh at runtime

login_title_ntfy() {
  printf '🔐 SSH Login: %s' "${SERVER_NAME}"
}

login_message_ntfy() {
  cat <<EOF
Alert Time: ${ALERT_TIME}

User: ${LOGIN_USER}
TTY: ${LOGIN_TTY}
IP Address: ${LOGIN_IP}
Login Time: ${LOGIN_TIME}
EOF
}
