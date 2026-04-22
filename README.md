# bash-sys-monitor

**bash-sys-monitor** is a lightweight, security-hardened, and modular suite of shell scripts designed for high-availability monitoring of Ubuntu Server 24+ (and compatible Linux distributions). It provides real-time system performance monitoring and security auditing with multi-channel alerting.

## Overview

The suite provides autonomous monitoring with zero external dependencies beyond standard system utilities:
- **`high-load.sh`**: Proactive system performance monitoring focused on resource saturation.
- **`login.sh`**: Real-time auditing of user access events.

## Architecture

The project follows a **modular plugin-based architecture** (Runtime DRY):
- **Core Scripts**: Primary logic for data collection and analysis.
- **Senders (`senders/`)**: Communication drivers for Telegram, Matrix, and ntfy.
- **Messages (`messages/`)**: Isolated templates for notification formatting.
- **Library (`lib/`)**: Shared utilities, including a strict configuration validator.
- **State (`state/`)**: Persistent data storage to ensure robust tracking (e.g., preventing duplicate login alerts).

The system automatically detects available plugins at runtime. You only need to download the core components and the specific notifiers you intend to use.

## Monitoring Concepts

### Load Monitoring (`high-load.sh`)
Our approach to load monitoring combines two critical metrics to ensure alerts are meaningful and actionable:
1. **Load Average**: Serves as the primary gate, measuring the long-term trend of tasks in the run queue and uninterruptible sleep.
2. **Pressure Stall Information (PSI)**: Provides immediate verification of resource contention. By checking if CPU, Memory, or IO stalls are actually occurring, the script confirms that resource saturation is impacting system performance, which helps filter out alerts from transient or historical load spikes.

### Security Auditing (`login.sh`)
The login monitor focuses on immediate visibility into system access. It monitors the `wtmp` log for authentication events, providing real-time alerts to ensure administrators are instantly aware of every entry into the system environment.

## Prerequisites

### 1. System Requirements
- **OS**: Ubuntu 24.04+ (or compatible Linux distribution).
- **Kernel**: Version 4.20 or higher (required for PSI). Check with:
  ```bash
  uname -r
  [ -d /proc/pressure ] && echo "PSI supported" || echo "PSI not supported"
  ```
- **Bash**: Version 4.4 or higher. Check with:
  ```bash
  bash --version
  ```

### 2. Dependencies
Install the necessary utilities using the package manager:
```bash
sudo apt update && sudo apt install -y awk bc curl jq procps coreutils file
```

## Installation

The directory structure in this repository reflects the expected layout. You can place the root directory anywhere in the system by simply adjusting the `BASE_PROJECT_PATH` variable below.

### 1. Initialize Environment
```bash
BASE_PROJECT_PATH="/opt/monitoring"
sudo mkdir -p "${BASE_PROJECT_PATH}"/{lib,senders,messages,state}
```

### 2. Download Core Components
```bash
BASE_URL="https://raw.githubusercontent.com/underhax/bash-sys-monitor/main/opt/monitoring"

sudo curl -fsSL "${BASE_URL}/high-load.sh" -o "${BASE_PROJECT_PATH}/high-load.sh"
sudo curl -fsSL "${BASE_URL}/login.sh" -o "${BASE_PROJECT_PATH}/login.sh"
sudo curl -fsSL "${BASE_URL}/lib/validation.sh" -o "${BASE_PROJECT_PATH}/lib/validation.sh"
sudo curl -fsSL "${BASE_URL}/bot.conf.example" -o "${BASE_PROJECT_PATH}/bot.conf"

sudo chmod 500 "${BASE_PROJECT_PATH}/high-load.sh" "${BASE_PROJECT_PATH}/login.sh" "${BASE_PROJECT_PATH}/lib/validation.sh"
```

### 3. Download Notifiers
Only download the components for the channels you want to enable.

**Telegram:**
```bash
sudo curl -fsSL "${BASE_URL}/senders/telegram.sh" -o "${BASE_PROJECT_PATH}/senders/telegram.sh"
sudo curl -fsSL "${BASE_URL}/messages/high-load-telegram.sh" -o "${BASE_PROJECT_PATH}/messages/high-load-telegram.sh"
sudo curl -fsSL "${BASE_URL}/messages/login-telegram.sh" -o "${BASE_PROJECT_PATH}/messages/login-telegram.sh"
```

**Matrix:**
```bash
sudo curl -fsSL "${BASE_URL}/senders/matrix.sh" -o "${BASE_PROJECT_PATH}/senders/matrix.sh"
sudo curl -fsSL "${BASE_URL}/messages/high-load-matrix.sh" -o "${BASE_PROJECT_PATH}/messages/high-load-matrix.sh"
sudo curl -fsSL "${BASE_URL}/messages/login-matrix.sh" -o "${BASE_PROJECT_PATH}/messages/login-matrix.sh"
```

**ntfy:**
```bash
sudo curl -fsSL "${BASE_URL}/senders/ntfy.sh" -o "${BASE_PROJECT_PATH}/senders/ntfy.sh"
sudo curl -fsSL "${BASE_URL}/messages/high-load-ntfy.sh" -o "${BASE_PROJECT_PATH}/messages/high-load-ntfy.sh"
sudo curl -fsSL "${BASE_URL}/messages/login-ntfy.sh" -o "${BASE_PROJECT_PATH}/messages/login-ntfy.sh"
```

## Configuration Guide (`bot.conf`)

The `bot.conf` file contains credentials for your notification channels. Populate only the variables for the notifiers you have installed.

### Common Variables
- `SERVER_NAME`: A unique, human-readable name for your server.

### Telegram Notifier
- `BOT_TOKEN`: The API token from @BotFather.
- `CHAT_ID`: Your user ID or group/channel ID.

### Matrix Notifier
> [!CAUTION]
> Due to the script's simple nature, messages will be sent as unencrypted. In encrypted rooms, they will be marked as "unencrypted" or "warning" by most clients.

> [!IMPORTANT]
> It is highly recommended to create a dedicated bot account. Do not use your personal account's access token.

- `MATRIX_URL`: Your homeserver base URL.
- `MATRIX_ROOM_ID`: The target room ID.
- `MATRIX_ACCESS_TOKEN`: The access token for the bot.

### ntfy Notifier
- `NTFY_URL`: The ntfy server URL.
- `NTFY_TOPIC`: The target topic name.
- `NTFY_TOKEN`: Optional authentication token. Highly recommended if your server supports authentication.

**Security Requirement:** The configuration file must have strict read-only permissions:
```bash
sudo chmod 400 "${BASE_PROJECT_PATH}/bot.conf"
```

## Systemd Integration

### 1. Download and Configure Unit Files
Download the units and automatically adjust the paths to match your `BASE_PROJECT_PATH`.

```bash
SYSTEMD_URL="https://raw.githubusercontent.com/underhax/bash-sys-monitor/main/etc/systemd/system"

for unit in monitoring-validator.service high-load.service high-load.timer login-monitor.service login-monitor.path; do
  sudo curl -fsSL "${SYSTEMD_URL}/${unit}" -o "/etc/systemd/system/${unit}"
  if [[ "${BASE_PROJECT_PATH}" != "/opt/monitoring" ]]; then
    sudo sed -i "s|/opt/monitoring|${BASE_PROJECT_PATH}|g" "/etc/systemd/system/${unit}"
  fi
done
```

### 2. Enable and Start
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now monitoring-validator.service
sudo systemctl enable --now high-load.timer
sudo systemctl enable --now login-monitor.path
```

## Advanced Usage: Filtering Notifiers

If you have downloaded multiple notifiers but wish to restrict a specific service to only a subset of them, use the `--notifiers` flag in the systemd `ExecStart` line:

```ini
ExecStart=/opt/monitoring/high-load.sh --threshold 4.0 --notifiers matrix,ntfy
```

You can apply the same logic to `login-monitor.service`:

```ini
ExecStart=/opt/monitoring/login.sh --notifiers ntfy,matrix
```

---
*Optimized for professional DevOps environments and security-conscious system administrators.*
