#!/usr/bin/env bash
set -e

USER_HOME="${HOME:-/home/$(whoami)}"
USER_NAME="$(whoami)"

echo "=== [1/7] Checking and installing required packages for $USER_NAME ==="
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
else
    echo "All core packages are already installed."
fi

if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "Downloading and installing Google Chrome..."
    curl -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -o /tmp/chrome.deb
    sudo dpkg -i /tmp/chrome.deb || sudo apt-get install -f -y
    rm -f /tmp/chrome.deb
fi

echo "=== [2/7] Configuring Google Chrome Sandbox Wrapper ==="
sudo tee /usr/local/bin/google-chrome > /dev/null << 'EOF'
#!/bin/bash
exec /usr/bin/google-chrome-stable --no-sandbox --disable-dev-shm-usage --test-type "$@"
EOF
sudo chmod +x /usr/local/bin/google-chrome
sudo ln -sf /usr/local/bin/google-chrome /usr/local/bin/chrome 2>/dev/null || true

echo "=== [3/7] Configuring Desktop Shortcuts ==="
mkdir -p "$USER_HOME/Desktop"
chmod 755 "$USER_HOME/Desktop"

cat << 'EOF' > "$USER_HOME/Desktop/google-chrome.desktop"
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
EOF
chmod +x "$USER_HOME/Desktop/google-chrome.desktop"

cat << 'EOF' > "$USER_HOME/Desktop/terminal.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Terminal
Comment=XFCE Terminal Emulator
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
StartupNotify=true
EOF
chmod +x "$USER_HOME/Desktop/terminal.desktop"

echo "=== [4/7] Patching noVNC Null-Safe Handlers & Clipboard Bridge ==="
sudo python3 - << 'PY_EOF'
import os, re

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
    target_touch_orig = '''    addTouchSpecificHandlers() {
        document.getElementById("noVNC_keyboard_button")
            .addEventListener('click', UI.toggleVirtualKeyboard);'''
    replacement_touch = '''    addTouchSpecificHandlers() {
        const kbBtn = document.getElementById("noVNC_keyboard_button");
        if (kbBtn) {
            kbBtn.addEventListener('click', UI.toggleVirtualKeyboard);
        }
        const kbInput = document.getElementById("noVNC_keyboardinput");
        if (!kbInput) return;'''
    if target_touch_orig in content:
        content = content.replace(target_touch_orig, replacement_touch, 1)

    # 2. Null-safe virtual keyboard toggle/focus/blur
    target_toggle = '''    toggleVirtualKeyboard() {
        if (document.getElementById('noVNC_keyboard_button')
            .classList.contains("noVNC_selected")) {'''
    patch_toggle = '''    toggleVirtualKeyboard() {
        const kbBtn = document.getElementById('noVNC_keyboard_button');
        if (kbBtn && kbBtn.classList.contains("noVNC_selected")) {'''
    if target_toggle in content:
        content = content.replace(target_toggle, patch_toggle, 1)

    target_onfocus = '''    onfocusVirtualKeyboard(event) {
        document.getElementById('noVNC_keyboard_button')
            .classList.add("noVNC_selected");'''
    patch_onfocus = '''    onfocusVirtualKeyboard(event) {
        const kbBtn = document.getElementById('noVNC_keyboard_button');
        if (kbBtn) kbBtn.classList.add("noVNC_selected");'''
    if target_onfocus in content:
        content = content.replace(target_onfocus, patch_onfocus, 1)

    target_onblur = '''    onblurVirtualKeyboard(event) {
        document.getElementById('noVNC_keyboard_button')
            .classList.remove("noVNC_selected");'''
    patch_onblur = '''    onblurVirtualKeyboard(event) {
        const kbBtn = document.getElementById('noVNC_keyboard_button');
        if (kbBtn) kbBtn.classList.remove("noVNC_selected");'''
    if target_onblur in content:
        content = content.replace(target_onblur, patch_onblur, 1)

    # 3. Null-safe updateViewOnly
    target_view_only = '''    updateViewOnly() {
        if (!UI.rfb) return;
        UI.rfb.viewOnly = UI.getSetting('view_only');

        // Hide input related buttons in view only mode
        if (UI.rfb.viewOnly) {
            document.getElementById('noVNC_keyboard_button')
                .classList.add('noVNC_hidden');
            document.getElementById('noVNC_toggle_extra_keys_button')
                .classList.add('noVNC_hidden');
            document.getElementById('noVNC_clipboard_button')
                .classList.add('noVNC_hidden');
        } else {
            document.getElementById('noVNC_keyboard_button')
                .classList.remove('noVNC_hidden');
            document.getElementById('noVNC_toggle_extra_keys_button')
                .classList.remove('noVNC_hidden');
            document.getElementById('noVNC_clipboard_button')
                .classList.remove('noVNC_hidden');
        }
    },'''
    patch_view_only = '''    updateViewOnly() {
        if (!UI.rfb) return;
        UI.rfb.viewOnly = UI.getSetting('view_only');

        // Hide input related buttons in view only mode
        const kbBtn = document.getElementById('noVNC_keyboard_button');
        const extraBtn = document.getElementById('noVNC_toggle_extra_keys_button');
        const clipBtn = document.getElementById('noVNC_clipboard_button');
        if (UI.rfb.viewOnly) {
            if (kbBtn) kbBtn.classList.add('noVNC_hidden');
            if (extraBtn) extraBtn.classList.add('noVNC_hidden');
            if (clipBtn) clipBtn.classList.add('noVNC_hidden');
        } else {
            if (kbBtn) kbBtn.classList.remove('noVNC_hidden');
            if (extraBtn) extraBtn.classList.remove('noVNC_hidden');
            if (clipBtn) clipBtn.classList.remove('noVNC_hidden');
        }
    },'''
    if target_view_only in content:
        content = content.replace(target_view_only, patch_view_only, 1)

    # 4. Clipboard Sync Bridge
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
    print(f"Successfully verified/patched {path}")

# 5. WebSockify Cache-Control headers
ws_server_path = '/usr/lib/python3/dist-packages/websockify/websockifyserver.py'
if os.path.exists(ws_server_path):
    with open(ws_server_path, 'r', encoding='utf-8') as f:
        ws_code = f.read()
    if 'Cache-Control' not in ws_code:
        ws_target = 'class WebSockifyRequestHandler(WebSocketRequestHandlerMixIn, SimpleHTTPRequestHandler):'
        ws_patch = '''class WebSockifyRequestHandler(WebSocketRequestHandlerMixIn, SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()'''
        if ws_target in ws_code:
            ws_code = ws_code.replace(ws_target, ws_patch, 1)
            with open(ws_server_path, 'w', encoding='utf-8') as f:
                f.write(ws_code)
            print(f"Successfully injected Cache-Control headers into {ws_server_path}")

# 6. Cache buster and meta tags in vnc.html and index.html
for html_file in ['/usr/share/novnc/vnc.html', '/usr/share/novnc/index.html']:
    if os.path.exists(html_file):
        with open(html_file, 'r', encoding='utf-8') as f:
            html = f.read()
        if 'http-equiv="Cache-Control"' not in html:
            meta_tags = '''<meta charset="utf-8">
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">'''
            html = html.replace('<meta charset="utf-8">', meta_tags)
        html = re.sub(r'src="app/ui\.js(\?v=[^"]*)?"', 'src="app/ui.js?v=20261119c"', html)
        with open(html_file, 'w', encoding='utf-8') as f:
            f.write(html)
        print(f"Verified cache buster and meta tags on {html_file}")
PY_EOF

# Set default page to vnc.html
if [ -f /usr/share/novnc/vnc.html ]; then
    sudo cp /usr/share/novnc/vnc.html /usr/share/novnc/index.html 2>/dev/null || true
fi

echo "=== [5/7] Writing Supervisor Configuration & Runners ==="
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

echo "=== [6/7] Writing Self-Healing start-desktop.sh and setup-cloudshell-xfce.sh ==="
cp "$0" "$USER_HOME/setup-cloudshell-xfce.sh" 2>/dev/null || true
chmod +x "$USER_HOME/setup-cloudshell-xfce.sh"

cat << 'EOF' > "$USER_HOME/start-desktop.sh"
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
chmod +x "$USER_HOME/start-desktop.sh"

echo "=== [7/7] Launching start-desktop.sh and verifying health ==="
bash "$USER_HOME/start-desktop.sh"
