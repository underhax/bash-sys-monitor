#!/usr/bin/env bash
# shellcheck disable=SC2154
# Rationale: Variables are exported by login.sh at runtime before sourcing this module

login_message_matrix_plain() {
  cat <<EOF
🔐 SSH Login: ${SERVER_NAME}
Alert Time: ${ALERT_TIME}

User: ${LOGIN_USER}
TTY: ${LOGIN_TTY}
IP Address: ${LOGIN_IP}
Login Time: ${LOGIN_TIME}
EOF
}

login_message_matrix_html() {
  cat <<EOF
🔐 <strong>SSH Login:</strong> ${SERVER_NAME}<br>
Alert Time: ${ALERT_TIME}<br><br>
<strong>User:</strong> ${LOGIN_USER}<br>
<strong>TTY:</strong> ${LOGIN_TTY}<br>
<strong>IP Address:</strong> ${LOGIN_IP}<br>
<strong>Login Time:</strong> ${LOGIN_TIME}
EOF
}
