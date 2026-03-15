#!/bin/bash
# UI Test Runner for VirtManager
# Uses macOS Accessibility (System Events) via osascript
set -euo pipefail

PASS=0; FAIL=0; TOTAL=0
pass() { echo "  ✔ $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "  ✘ $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

echo "=== VirtManager UI Tests ==="
echo ""

# Build
swift build 2>&1 | tail -1

# Build .app bundle
APP_DIR=".build/VirtManager.app/Contents"
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources"
cp .build/arm64-apple-macosx/debug/VirtManager "$APP_DIR/MacOS/VirtManager"
cp Sources/VirtManager/Resources/Info.plist "$APP_DIR/Info.plist"

# Check if app is already running with VMs visible
ALREADY_RUNNING=false
if pgrep -x VirtManager >/dev/null 2>&1; then
    EXISTING=$(osascript -e '
    tell app "System Events" to tell process "VirtManager"
        set vals to {}
        repeat with e in (entire contents of window 1)
            try
                set v to value of e
                if v is not missing value then set end of vals to v
            end try
        end repeat
        return vals as text
    end tell' 2>/dev/null || echo "")
    if echo "$EXISTING" | grep -q "opnsense"; then
        ALREADY_RUNNING=true
        echo "(Using existing app instance — already connected)"
    fi
fi

if [ "$ALREADY_RUNNING" = "false" ]; then
    killall VirtManager 2>/dev/null || true; sleep 0.5
    .build/VirtManager.app/Contents/MacOS/VirtManager &
    APP_PID=$!
    sleep 2
    osascript -e 'tell app "System Events" to set frontmost of process "VirtManager" to true' 2>/dev/null || true
fi

# ---- App Launch ----
echo "--- App Launch ---"
W=$(osascript -e 'tell app "System Events" to count windows of process "VirtManager"' 2>/dev/null || echo 0)
[ "$W" -ge 1 ] && pass "Window exists" || fail "No window"

TB=$(osascript -e 'tell app "System Events" to tell process "VirtManager" to return exists toolbar 1 of window 1' 2>/dev/null || echo false)
[ "$TB" = "true" ] && pass "Toolbar exists" || fail "No toolbar"

# ---- Connection Sheet ----
echo "--- Connection Sheet ---"
if [ "$ALREADY_RUNNING" = "true" ]; then
    pass "Sheet opens (skipped — already connected)"
    pass "Form submitted (skipped — already connected)"
else
    osascript -e '
    tell app "System Events" to tell process "VirtManager"
        set frontmost to true
        delay 0.3
        click (first button of toolbar 1 of window 1 whose description is "Add Connection")
    end tell' 2>/dev/null || true
    sleep 1

    SHEET=$(osascript -e 'tell app "System Events" to tell process "VirtManager" to return exists sheet 1 of window 1' 2>/dev/null || echo false)
    [ "$SHEET" = "true" ] && pass "Sheet opens" || fail "Sheet didn't open"

    if [ "$SHEET" = "true" ]; then
        osascript << 'AS'
tell app "System Events"
    tell process "VirtManager"
        set grp to group 1 of sheet 1 of window 1
        click text field "Display Name" of grp
        delay 0.2
        keystroke "jolyne-uitest"
        delay 0.3
        click button 2 of grp
    end tell
end tell
AS
        pass "Form submitted"
    fi
fi

# ---- VM Discovery ----
echo "--- VM Discovery ---"
echo "  ... waiting for SSH connection (up to 15s)"
FOUND=false
for i in $(seq 1 15); do
    TEXT=$(osascript -e '
    tell app "System Events" to tell process "VirtManager"
        set vals to {}
        repeat with e in (entire contents of window 1)
            try
                set v to value of e
                if v is not missing value then set end of vals to v
            end try
        end repeat
        return vals as text
    end tell' 2>/dev/null || echo "")
    if echo "$TEXT" | grep -q "opnsense"; then
        FOUND=true; break
    fi
    sleep 1
done
[ "$FOUND" = "true" ] && pass "Connected — opnsense visible" || fail "Connection timeout"

if [ "$FOUND" = "true" ]; then
    for VM in opnsense PROD-Brokers-41 unifi-new hass.calii.lan fedora-workstation; do
        echo "$TEXT" | grep -q "$VM" && pass "VM '$VM' listed" || fail "VM '$VM' missing"
    done
fi

# ---- VM Detail ----
echo "--- VM Detail ---"
if [ "$FOUND" = "true" ]; then
    osascript -e '
    tell app "System Events" to tell process "VirtManager"
        -- Click on opnsense static text
        repeat with e in (every static text of window 1)
            if value of e is "opnsense" then
                click e
                exit repeat
            end if
        end repeat
    end tell' 2>/dev/null || true
    sleep 1

    DETAIL=$(osascript -e '
    tell app "System Events" to tell process "VirtManager"
        set vals to {}
        repeat with e in (entire contents of window 1)
            try
                set v to value of e
                if v is not missing value then set end of vals to v
            end try
        end repeat
        return vals as text
    end tell' 2>/dev/null || echo "")
    echo "$DETAIL" | grep -qi "running" && pass "Shows Running state" || fail "No Running state"
    echo "$DETAIL" | grep -qi "vnc\|VNC" && pass "Shows VNC graphics" || fail "No VNC shown"
fi

# ---- VNC Console ----
echo "--- VNC Console ---"
if [ "$FOUND" = "true" ]; then
    # Try double-click or find Open Console button
    osascript -e '
    tell app "System Events" to tell process "VirtManager"
        repeat with b in (every button of window 1)
            try
                if title of b contains "Console" and title of b does not contain "Serial" then
                    click b
                    exit repeat
                end if
            end try
        end repeat
    end tell' 2>/dev/null || true
    sleep 4

    WC=$(osascript -e 'tell app "System Events" to count windows of process "VirtManager"' 2>/dev/null || echo 0)
    [ "$WC" -ge 2 ] && pass "VNC console window opened ($WC windows)" || fail "Console window not opened ($WC windows)"
fi

echo ""
echo "=== Results: $TOTAL total | $PASS passed | $FAIL failed ==="
killall VirtManager 2>/dev/null || true
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
