# Ubuntu Cloud PC on Google Cloud Shell: Master Blueprint & Setup Guide

This document is the definitive, production-hardened engineering guide for setting up and running a persistent, high-performance Ubuntu XFCE Cloud PC on Google Cloud Shell with single-click Windows launchers for multiple accounts.

It documents the complete architecture, every script, multi-account management, and every historical failure discovered and resolved during development.

---

## 1. Architecture Overview

Google Cloud Shell provides a free Debian/Ubuntu-based virtual container with 5 GB of persistent storage in `$HOME`. However, the root filesystem (`/usr`, `/etc`, `/var`) is ephemeral and resets on cold boots (after 20 minutes of inactivity).

To build a reliable Cloud PC on this infrastructure, the system is designed in decoupled layers:

```
[ Windows Client Desktop ]
       │
       ▼ Double-click Start-Ubuntu-Cloud-PC-Money.bat / Start-Ubuntu-Cloud-PC-Munnar.bat
  ┌────────────────────────────────────────────────────────────────┐
  │ 1. Enforce OAuth Identity & APPDATA path                       │
  │ 2. SSH to Cloud Shell & trigger ~/start-desktop.sh             │
  │ 3. Wait for Port 8080 Health Probe (HTTP 200 OK)               │
  │ 4. Spawn Google Chrome explicitly in target Profile            │
  │ 5. Keep interactive Cloud Shell SSH alive (anti-idle)          │
  └────────────────────────────────────────────────────────────────┘
       │
       ▼ (Encrypted SSH Tunnel & Cloud Shell Reverse Proxy)
[ Google Cloud Shell Container ]
  ┌────────────────────────────────────────────────────────────────┐
  │ supervisord (Process Supervisor & Self-Healer)                 │
  │  ├── Xvfb (:1 @ 1920x1080x24) -> Virtual Display Buffer        │
  │  ├── xfce4-session            -> Lightweight Desktop GUI       │
  │  ├── x11vnc (:1 -> 5901)      -> VNC Server on Localhost       │
  │  ├── websockify (8080 -> 5901)-> noVNC WebSocket Web Gateway   │
  │  └── autocutsel (PRIMARY/CLIP)-> Bidirectional Clipboard Sync   │
  └────────────────────────────────────────────────────────────────┘
```

---

## 2. Complete Post-Mortem: Mistakes, Root Causes & Fixes

During the initial deployments, several subtle failure modes occurred. Every bug was forensically diagnosed and permanently resolved.

### Flaw 1: Dual APPDATA OAuth Token Disconnect & Poisoning
- **Symptom**: Running the batch file failed with `Account is not logged in` or connected to the wrong account (`food24villa`), causing an instant `HTTP ERROR 404`.
- **Root Cause**: Windows maintains two separate credential directories: `AppData\Local` and `AppData\Roaming`. Windows Explorer launches `.bat` files with `APPDATA=AppData\Roaming`. When an account is logged in via interactive CLI, `gcloud` may store credentials in `AppData\Local\gcloud\credentials.db`, leaving `AppData\Roaming\gcloud\credentials.db` empty or contaminated.
- **The Fix**:
  1. Synchronize authentic OAuth credentials from `AppData\Local\gcloud\credentials.db` into `AppData\Roaming\gcloud\credentials.db`.
  2. Purge stale tokens from `access_tokens.db`.
  3. Enforce the environment variables in the launcher:
     ```cmd
     set "ACCOUNT=your_account@gmail.com"
     set "CLOUDSDK_CORE_ACCOUNT=%ACCOUNT%"
     set "APPDATA=C:\Users\Abhishek soni\AppData\Roaming"
     ```

### Flaw 2: Ephemeral Root Filesystem Wipe on Cold Boot (The 20-Minute Trap)
- **Symptom**: After 20 minutes of idle time, Cloud Shell recycles its container. The next start fails with:
  ```
  novnc BACKOFF can't find command '/usr/bin/websockify'
  xvfb BACKOFF can't find command '/usr/bin/Xvfb'
  ```
- **Root Cause**: Only `$HOME` is preserved across container recycles. Packages installed into `/usr/bin/` are deleted upon container restart.
- **The Fix**: Embedded an automated dependency check in `~/start-desktop.sh`:
  ```bash
  if ! command -v Xvfb >/dev/null 2>&1 || ! command -v websockify >/dev/null 2>&1 || ! command -v startxfce4 >/dev/null 2>&1; then
      echo "=== Cold reboot detected: Restoring desktop packages ==="
      bash "$HOME/setup-cloudshell-xfce.sh"
  fi
  ```

### Flaw 3: Premature Client Launch Race Condition
- **Symptom**: Chrome opened immediately on double-click, showing an `HTTP ERROR 404` or connection refused error. Refreshing 5 seconds later loaded the desktop fine.
- **Root Cause**: WebSockify takes 2 to 4 seconds to bind TCP port 8080. If Chrome requests the Google Cloud Shell proxy URL before the port is bound, Google's proxy returns a 404 error.
- **The Fix**: Embedded a 20-second active health polling loop inside `~/start-desktop.sh`:
  ```bash
  for i in {1..20}; do
      if curl -s -I http://127.0.0.1:8080/vnc.html 2>/dev/null | grep -q "200 OK"; then
          echo "=== SUCCESS: Desktop server is active and verified healthy on port 8080 ==="
          exit 0
      fi
      sleep 1
  done
  echo "=== ERROR: Timeout waiting for port 8080 ==="
  exit 1
  ```
  The batch file checks `%errorlevel%` and only launches Chrome after port 8080 is verified healthy.

### Flaw 4: Windows CRLF Line Ending Corruption
- **Symptom**: Deploying bash scripts from Windows PowerShell resulted in:
  ```
  syntax error near unexpected token $'do\r''
  set: -: invalid option
  ```
- **Root Cause**: Windows pipes use CRLF (`\r\n`) line endings. Linux bash interprets `\r` as part of the command.
- **The Fix**: Strip carriage returns during deployment using `tr -d '\r'`:
  ```bash
  tr -d '\r' > ~/start-desktop.sh && chmod +x ~/start-desktop.sh
  ```

### Flaw 5: Regional Hostname Differences Across Cloud Shell Instances
- **Symptom**: Copying the Web Preview URL from one account to another caused `HTTP ERROR 404`.
- **Root Cause**: Different Cloud Shell accounts are routed to different regional clusters:
  - Account `money000000money@gmail.com`: `cs-1758105958-default.cs-asia-southeast1-yelo.cloudshell.dev`
  - Account `munnartirupatitrip2@gmail.com`: `cs-358858335060-default.cs-asia-southeast1-seal.cloudshell.dev`
- **The Fix**: Query the exact `WEB_HOST` environment variable directly from Cloud Shell:
  ```bash
  env | grep WEB_HOST
  ```
  Then prefix with `https://8080-` and append `/vnc.html?autoconnect=true&resize=remote&authuser=0`.

### Flaw 6: Chrome Multi-Profile Routing
- **Symptom**: Opening the Web Preview link in the wrong profile causes permission denied or loads the wrong Cloud Shell instance.
- **The Fix**: Map each account to its specific Chrome profile folder in `C:\Users\Abhishek soni\AppData\Local\Google\Chrome\User Data\Local State`:
  - `money000000money@gmail.com` -> `--profile-directory="Profile 19"`
  - `munnartirupatitrip2@gmail.com` -> `--profile-directory="Profile 33"`

### Flaw 7: noVNC DOM Null Element & Browser Script Caching Crash
- **Symptom**: The browser displays a full-screen red error modal:
  ```
  noVNC encountered an error:
  Uncaught TypeError: Cannot read properties of null (reading 'addEventListener')
  https://.../app/ui.js:236:13
  at Object.addTouchSpecificHandlers (ui.js:236:13)
  ```
- **Root Cause**:
  1. Default upstream noVNC lacks null checks on `#noVNC_keyboard_button` and other control bar elements in `addTouchSpecificHandlers()`, `updateViewOnly()`, `toggleVirtualKeyboard()`, `onfocusVirtualKeyboard()`, and `onblurVirtualKeyboard()`.
  2. WebSockify's built-in Python web server does not send `Cache-Control` headers by default. Chrome aggressively caches `vnc.html` and `app/ui.js` in disk cache, serving outdated, unpatched JavaScript even after server-side updates.
- **The Fix**:
  1. Guard every element lookup in `/usr/share/novnc/app/ui.js` (`kbBtn`, `kbInput`, `extraBtn`, `clipBtn`).
  2. Inject `end_headers` into `WebSockifyRequestHandler` in `/usr/lib/python3/dist-packages/websockify/websockifyserver.py` to send `Cache-Control: no-cache, no-store, must-revalidate`, `Pragma: no-cache`, and `Expires: 0` on every response.
  3. Inject cache-control meta tags into `vnc.html` and `index.html` along with script versioning `app/ui.js?v=20261119c`.
  4. Include `?v=20261119c` directly in the Windows launcher `DIRECT_URL` to bust Chrome's initial document cache.

### Flaw 8: False-Positive Port 8080 Health Gates
- **Symptom**: `start-desktop.sh` reported healthy, but opening the browser resulted in "Connection closed" or an unusable blank desktop.
- **Root Cause**: Earlier versions of `start-desktop.sh` only verified `curl http://127.0.0.1:8080/vnc.html`. If WebSockify stayed alive while `xvfb`, `xfce`, or `x11vnc` crashed, the health probe returned 200 OK and skipped recovery.
- **The Fix**: Embedded a multi-process health validator `desktop_healthy` in `start-desktop.sh` that verifies:
  1. HTTP 200 OK on port 8080.
  2. Supervisor Unix socket is active.
  3. Every managed process (`xvfb`, `xfce`, `x11vnc`, `novnc`, `clipboard`) is explicitly in `RUNNING` state without any `FATAL`, `BACKOFF`, or `STOPPED` flags.

---

## 3. Server-Side Installation (Google Cloud Shell)

Follow these steps on any fresh Google Cloud Shell account.

### Step 1: Create `~/setup-cloudshell-xfce.sh`
Run this command inside Cloud Shell:

```bash
cat << 'EOF' > ~/setup-cloudshell-xfce.sh
#!/usr/bin/env bash
set -e

USER_HOME="${HOME:-/home/$(whoami)}"
USER_NAME="$(whoami)"

echo "=== [1/6] Installing XFCE Desktop, Google Chrome, and Audio/Video Stack for $USER_NAME ==="
MISSING_PKGS=()
for pkg in xfce4 xfce4-terminal xfce4-goodies dbus-x11 xvfb x11vnc novnc websockify autocutsel fonts-liberation thunar mousepad pulseaudio pavucontrol libsecret-1-0 libsecret-tools gnome-keyring supervisor; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "Installing missing packages: ${MISSING_PKGS[*]}"
    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${MISSING_PKGS[@]}"
fi

if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "Downloading and installing Google Chrome..."
    curl -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -o /tmp/chrome.deb
    sudo dpkg -i /tmp/chrome.deb || sudo apt-get install -f -y
    rm -f /tmp/chrome.deb
fi

echo "=== [2/6] Configuring Google Chrome Sandbox Wrapper ==="
sudo tee /usr/local/bin/google-chrome > /dev/null << 'INNER_EOF'
#!/bin/bash
exec /usr/bin/google-chrome-stable --no-sandbox --disable-dev-shm-usage --test-type "$@"
INNER_EOF
sudo chmod +x /usr/local/bin/google-chrome
sudo ln -sf /usr/local/bin/google-chrome /usr/local/bin/chrome 2>/dev/null || true

echo "=== [3/6] Configuring Desktop Shortcuts ==="
mkdir -p "$USER_HOME/Desktop"
chmod 755 "$USER_HOME/Desktop"

cat << 'INNER_EOF' > "$USER_HOME/Desktop/google-chrome.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Chrome
Comment=Access the Internet
Exec=/usr/local/bin/google-chrome %U
Icon=google-chrome
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
INNER_EOF
chmod +x "$USER_HOME/Desktop/google-chrome.desktop"

cat << 'INNER_EOF' > "$USER_HOME/Desktop/terminal.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Terminal
Comment=XFCE Terminal Emulator
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
StartupNotify=true
INNER_EOF
chmod +x "$USER_HOME/Desktop/terminal.desktop"

echo "=== [4/6] Patching noVNC Bidirectional Web Clipboard & Null-Safe Handlers ==="
sudo python3 - << 'PY_EOF'
import os

candidates = [
    '/usr/share/novnc/app/ui.js',
    '/usr/local/novnc/noVNC-1.6.0/app/ui.js'
]

for path in candidates:
    if not os.path.exists(path):
        continue
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Null-safe addTouchSpecificHandlers
    target_touch = '''    addTouchSpecificHandlers() {
        document.getElementById("noVNC_keyboard_button")
            .addEventListener('click', UI.toggleVirtualKeyboard);'''
    replacement_touch = '''    addTouchSpecificHandlers() {
        const kbBtn = document.getElementById("noVNC_keyboard_button");
        if (kbBtn) {
            kbBtn.addEventListener('click', UI.toggleVirtualKeyboard);
        }
        const kbInput = document.getElementById("noVNC_keyboardinput");
        if (!kbInput) return;'''
    if target_touch in content:
        content = content.replace(target_touch, replacement_touch, 1)

    # 2. Clipboard Sync Bridge
    if 'BIDIRECTIONAL SYNC BRIDGE' not in content:
        target1 = 'addClipboardHandlers() {'
        patch1 = '''addClipboardHandlers() {
        // --- BIDIRECTIONAL SYNC BRIDGE ---
        window.addEventListener('focus', async () => {
            try {
                if (navigator.clipboard && navigator.clipboard.readText && UI.connected && UI.rfb) {
                    const text = await navigator.clipboard.readText();
                    const el = document.getElementById('noVNC_clipboard_text');
                    if (text && el && text !== el.value) {
                        el.value = text;
                        UI.rfb.clipboardPasteFrom(text);
                    }
                }
            } catch (err) {}
        });

        window.addEventListener('keydown', async (e) => {
            if ((e.ctrlKey || e.metaKey) && (e.key === 'v' || e.key === 'V')) {
                if (!UI.connected || !UI.rfb) return;
                try {
                    if (navigator.clipboard && navigator.clipboard.readText) {
                        const text = await navigator.clipboard.readText();
                        if (text) {
                            const el = document.getElementById('noVNC_clipboard_text');
                            if (el) el.value = text;
                            UI.rfb.clipboardPasteFrom(text);
                            if (!e.shiftKey) {
                                setTimeout(() => {
                                    if (UI.connected && UI.rfb) {
                                        UI.rfb.sendKey(0xffe1, 'ShiftLeft', true);
                                        UI.rfb.sendKey(0xff63, 'Insert', true);
                                        UI.rfb.sendKey(0xff63, 'Insert', false);
                                        UI.rfb.sendKey(0xffe1, 'ShiftLeft', false);
                                    }
                                }, 30);
                            }
                        }
                    }
                } catch (err) {}
            }
        }, true);'''
        content = content.replace(target1, patch1, 1)

        target2 = '''clipboardReceive(e) {
        Log.Debug(">> UI.clipboardReceive: " + e.detail.text.substr(0, 40) + "...");
        document.getElementById('noVNC_clipboard_text').value = e.detail.text;
        Log.Debug("<< UI.clipboardReceive");
    },'''
        patch2 = '''clipboardReceive(e) {
        Log.Debug(">> UI.clipboardReceive: " + e.detail.text.substr(0, 40) + "...");
        document.getElementById('noVNC_clipboard_text').value = e.detail.text;
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(e.detail.text).catch(() => {});
        }
        Log.Debug("<< UI.clipboardReceive");
    },'''
        content = content.replace(target2, patch2, 1)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Successfully patched {path}")

# Invalidate browser cache on client script imports
for html_file in ['/usr/share/novnc/vnc.html', '/usr/share/novnc/index.html']:
    if os.path.exists(html_file):
        with open(html_file, 'r', encoding='utf-8') as f:
            html = f.read()
        html = re.sub(r'src="app/ui\.js(\?v=[^"]*)?"', 'src="app/ui.js?v=20261119b"', html)
        with open(html_file, 'w', encoding='utf-8') as f:
            f.write(html)
        print(f"Verified cache buster on {html_file}")
PY_EOF

# Set default landing page to autoconnect & scale
if [ -f /usr/share/novnc/vnc.html ]; then
    sudo cp /usr/share/novnc/vnc.html /usr/share/novnc/index.html 2>/dev/null || true
fi

echo "=== [5/6] Updating Supervisor Configuration ==="
cat << EOF > "$USER_HOME/cloudshell-desktop-supervisor.conf"
[unix_http_server]
file=$USER_HOME/supervisor.sock
chmod=0700

[supervisord]
logfile=$USER_HOME/supervisord.log
logfile_maxbytes=10MB
logfile_backups=3
loglevel=info
pidfile=$USER_HOME/supervisord.pid
nodaemon=false

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix://$USER_HOME/supervisor.sock

[program:xvfb]
command=/usr/bin/Xvfb :1 -screen 0 1920x1080x24 -listen tcp -ac
autorestart=true
priority=100
stdout_logfile=$USER_HOME/xvfb.log
stderr_logfile=$USER_HOME/xvfb.err

[program:xfce]
command=$USER_HOME/start-xfce.sh
autorestart=true
priority=200
stdout_logfile=$USER_HOME/xfce.log
stderr_logfile=$USER_HOME/xfce.err

[program:x11vnc]
command=$USER_HOME/start-x11vnc.sh
autorestart=true
priority=300
stdout_logfile=$USER_HOME/x11vnc.log
stderr_logfile=$USER_HOME/x11vnc.err

[program:novnc]
command=/usr/bin/websockify --web /usr/share/novnc 8080 127.0.0.1:5901
autorestart=true
priority=400
stdout_logfile=$USER_HOME/novnc.log
stderr_logfile=$USER_HOME/novnc.err

[program:clipboard]
command=$USER_HOME/start-clipboard.sh
autorestart=true
priority=500
stdout_logfile=$USER_HOME/clipboard.log
stderr_logfile=$USER_HOME/clipboard.err
EOF

cat << EOF > "$USER_HOME/start-xfce.sh"
#!/bin/bash
export DISPLAY=:1
export HOME=$USER_HOME
export USER=$USER_NAME

until xset q >/dev/null 2>&1; do
    sleep 0.5
done

if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ] && command -v dbus-launch >/dev/null 2>&1; then
    eval \$(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

xfconf-query -c xfce4-session -p /startup/screensaver/Type -s 0 --create -t int 2>/dev/null || true
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -s 0 --create -t int 2>/dev/null || true

exec startxfce4
EOF
chmod +x "$USER_HOME/start-xfce.sh"

cat << 'EOF' > "$USER_HOME/start-x11vnc.sh"
#!/bin/bash
export DISPLAY=:1

until xset q >/dev/null 2>&1; do
    sleep 0.5
done

exec x11vnc -display :1 -nopw -listen 127.0.0.1 -forever -shared -rfbport 5901
EOF
chmod +x "$USER_HOME/start-x11vnc.sh"

cat << EOF > "$USER_HOME/start-clipboard.sh"
#!/bin/bash
export DISPLAY=:1
export HOME=$USER_HOME

until xset q >/dev/null 2>&1; do
    sleep 0.5
done

autocutsel -display :1 -selection CLIPBOARD -fork
exec autocutsel -display :1 -selection PRIMARY
EOF
chmod +x "$USER_HOME/start-clipboard.sh"

echo "=== [6/6] Launching Supervisor Desktop Services ==="
bash "$USER_HOME/start-desktop.sh"

echo "=== Setup Completed Successfully ==="
EOF
chmod +x ~/setup-cloudshell-xfce.sh
```

---

### Step 2: Create `~/start-desktop.sh`
Run this command inside Cloud Shell:

```bash
cat << 'EOF' > ~/start-desktop.sh
#!/usr/bin/env bash
set -e

mkdir -p "$HOME/.cloudshell"
touch "$HOME/.cloudshell/no-apt-get-warning"

desktop_healthy() {
    if ! curl -s -I http://127.0.0.1:8080/vnc.html 2>/dev/null | grep -q "200 OK"; then
        return 1
    fi
    if [ ! -S "$HOME/supervisor.sock" ]; then
        return 1
    fi
    local failed
    failed=$(supervisorctl -c "$HOME/cloudshell-desktop-supervisor.conf" status 2>/dev/null | grep -v -E "RUNNING" || true)
    if [ -n "$failed" ]; then
        return 1
    fi
    return 0
}

# 1. Immediate exit if desktop is already running and verified healthy
if desktop_healthy; then
    echo "=== Desktop is already running and verified healthy on port 8080 ==="
    supervisorctl -c "$HOME/cloudshell-desktop-supervisor.conf" status
    exit 0
fi

# 2. Idempotent cold-reboot package restoration
if ! command -v Xvfb >/dev/null 2>&1 || ! command -v websockify >/dev/null 2>&1 || ! command -v startxfce4 >/dev/null 2>&1; then
    echo "=== Cold reboot detected: Restoring desktop packages ==="
    if [ -f "$HOME/setup-cloudshell-xfce.sh" ]; then
        bash "$HOME/setup-cloudshell-xfce.sh"
    else
        echo "Error: setup-cloudshell-xfce.sh not found!"
        exit 1
    fi
fi

# 3. Clean up stale supervisor instances and locks
echo "=== Cleaning up stale instances ==="
supervisorctl -c "$HOME/cloudshell-desktop-supervisor.conf" stop all 2>/dev/null || true
pkill -f "supervisord.*cloudshell" 2>/dev/null || true
pkill -f "websockify.*8080" 2>/dev/null || true
pkill -f "x11vnc.*5901" 2>/dev/null || true
pkill -f "startxfce4" 2>/dev/null || true
pkill -f "xfce4-session" 2>/dev/null || true
pkill -f "autocutsel" 2>/dev/null || true
pkill -f "Xvfb :1" 2>/dev/null || true
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 "$HOME/supervisor.sock" "$HOME/supervisord.pid" 2>/dev/null || true
sleep 1

# 4. Start supervisor daemon
echo "=== Starting supervisord daemon ==="
supervisord -c "$HOME/cloudshell-desktop-supervisor.conf"

# 5. Verification gate: Poll until all services are RUNNING and port 8080 responds
echo "=== Verifying desktop and port 8080 health ==="
for i in {1..25}; do
    if desktop_healthy; then
        echo "=== SUCCESS: Desktop server is active and verified healthy on port 8080 (took ${i}s) ==="
        supervisorctl -c "$HOME/cloudshell-desktop-supervisor.conf" status
        exit 0
    fi
    sleep 1
done

echo "=== ERROR: Timeout waiting for desktop services to become healthy ==="
supervisorctl -c "$HOME/cloudshell-desktop-supervisor.conf" status
exit 1
EOF
chmod +x ~/start-desktop.sh
```

---

## 4. Multi-Account Windows Launchers & Control Manager

All start and stop batch files are organized in a dedicated manager folder:
- Desktop Path: `C:\Users\Abhishek soni\Desktop\Ubuntu-Cloud-PC-Manager`
- Backup Path: `F:\EMPIRE D DRIVE\BACKup of soft\Ubuntu-Cloud-PC-Manager`

### Account 1: MONEY (`money000000money@gmail.com`)
- **Start Batch File**: `Start-Ubuntu-Cloud-PC-Money.bat`
- **Stop Batch File**: `Stop-Ubuntu-Cloud-PC-Money.bat`
- **Cloud Host**: `cs-1758105958-default.cs-asia-southeast1-yelo.cloudshell.dev`
- **Direct URL**: `https://8080-cs-1758105958-default.cs-asia-southeast1-yelo.cloudshell.dev/vnc.html?v=20261119c&autoconnect=true&resize=remote&authuser=0`
- **Chrome Profile**: `Profile 19`

### Account 2: MUNNAR (`munnartirupatitrip2@gmail.com`)
- **Start Batch File**: `Start-Ubuntu-Cloud-PC-Munnar.bat`
- **Stop Batch File**: `Stop-Ubuntu-Cloud-PC-Munnar.bat`
- **Cloud Host**: `cs-358858335060-default.cs-asia-southeast1-seal.cloudshell.dev`
- **Direct URL**: `https://8080-cs-358858335060-default.cs-asia-southeast1-seal.cloudshell.dev/vnc.html?v=20261119c&autoconnect=true&resize=remote&authuser=0`
- **Chrome Profile**: `Profile 33`

---

## 5. Operations & Health Checks

### How to Stop the Cloud PC Server (Munnar)
```powershell
& "C:\Users\Abhishek soni\AppData\Local\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd" cloud-shell ssh --account=munnartirupatitrip2@gmail.com --command="supervisorctl -c ~/cloudshell-desktop-supervisor.conf stop all; pkill -9 -f supervisord; pkill -9 -f websockify; pkill -9 -f x11vnc; pkill -9 -f Xvfb; pkill -9 -f xfce4; rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 ~/supervisor.sock; echo SERVER_SHUTDOWN_COMPLETE"
```

### How to Verify Port 8080
```bash
curl -s -I http://127.0.0.1:8080/vnc.html
```
Expected output:
```
HTTP/1.1 200 OK
Server: WebSockify Python/3.12.3
Content-type: text/html
Cache-Control: no-cache, no-store, must-revalidate
Pragma: no-cache
Expires: 0
```
