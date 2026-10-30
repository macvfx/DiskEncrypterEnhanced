#!/bin/bash

# Uninstallation script for DiskEncrypter LaunchDaemon
# Run with: sudo bash uninstall_launchdaemon.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
# The installer package installs com.custom.diskencrypter; install_launchdaemon.sh
# installs com.custom.diskencrypter.volumewatcher. Remove whichever is present.
LABELS=("com.custom.diskencrypter" "com.custom.diskencrypter.volumewatcher")
PKG_ID="com.custom.diskencrypter"
INSTALL_DIR="/Library/Application Support/Custom"
LAUNCHDAEMON_DIR="/Library/LaunchDaemons"
LOG_DIR="/var/log"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}DiskEncrypter LaunchDaemon Uninstaller${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}ERROR: This script must be run as root${NC}"
   echo "Usage: sudo bash uninstall_launchdaemon.sh"
   exit 1
fi

# Unload daemon
echo -e "${YELLOW}Step 1/4: Unloading LaunchDaemon...${NC}"
for label in "${LABELS[@]}"; do
    if launchctl print "system/$label" &>/dev/null; then
        launchctl bootout "system/$label" 2>/dev/null || true
        sleep 1
        echo -e "${GREEN}✓ Unloaded $label${NC}"
    else
        echo -e "${YELLOW}⚠ $label was not loaded${NC}"
    fi
    # Clear a leftover "launchctl disable" so a later reinstall loads normally
    if launchctl print-disabled system 2>/dev/null | grep -Eq "\"$label\" => (disabled|true)"; then
        launchctl enable "system/$label" 2>/dev/null || true
        echo -e "${GREEN}✓ Cleared disabled flag for $label${NC}"
    fi
done
echo ""

# Remove plist
echo -e "${YELLOW}Step 2/4: Removing LaunchDaemon plist...${NC}"
for label in "${LABELS[@]}"; do
    if [[ -f "$LAUNCHDAEMON_DIR/$label.plist" ]]; then
        rm "$LAUNCHDAEMON_DIR/$label.plist"
        echo -e "${GREEN}✓ Removed $label.plist${NC}"
    else
        echo -e "${YELLOW}⚠ $label.plist not found${NC}"
    fi
done

# Forget the installer package receipt, if it was installed from the pkg
if pkgutil --pkg-info "$PKG_ID" &>/dev/null; then
    pkgutil --forget "$PKG_ID" >/dev/null
    echo -e "${GREEN}✓ Removed package receipt $PKG_ID${NC}"
fi
echo ""

# Remove script
echo -e "${YELLOW}Step 3/4: Removing script...${NC}"
if [[ -f "$INSTALL_DIR/DiskEncrypter_Enhanced.sh" ]]; then
    rm "$INSTALL_DIR/DiskEncrypter_Enhanced.sh"
    echo -e "${GREEN}✓ Removed DiskEncrypter_Enhanced.sh${NC}"
else
    echo -e "${YELLOW}⚠ Script not found${NC}"
fi

# Remove directory if empty
if [[ -d "$INSTALL_DIR" ]] && [[ -z "$(ls -A "$INSTALL_DIR")" ]]; then
    rmdir "$INSTALL_DIR"
    echo -e "${GREEN}✓ Removed empty directory $INSTALL_DIR${NC}"
fi
echo ""

# Archive logs
echo -e "${YELLOW}Step 4/4: Handling log files...${NC}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [[ -f "$LOG_DIR/diskencrypter.log" ]] || [[ -f "$LOG_DIR/diskencrypter_error.log" ]]; then
    echo "Archiving log files to ~/diskencrypter_logs_$TIMESTAMP/"
    mkdir -p ~/diskencrypter_logs_$TIMESTAMP
    [[ -f "$LOG_DIR/diskencrypter.log" ]] && mv "$LOG_DIR/diskencrypter.log" ~/diskencrypter_logs_$TIMESTAMP/
    [[ -f "$LOG_DIR/diskencrypter_error.log" ]] && mv "$LOG_DIR/diskencrypter_error.log" ~/diskencrypter_logs_$TIMESTAMP/
    echo -e "${GREEN}✓ Logs archived to ~/diskencrypter_logs_$TIMESTAMP/${NC}"
else
    echo -e "${YELLOW}⚠ No log files found${NC}"
fi
echo ""

# Verify removal
echo -e "${YELLOW}Verifying uninstallation...${NC}"
still_loaded=0
for label in "${LABELS[@]}"; do
    if launchctl print "system/$label" &>/dev/null; then
        echo -e "${RED}✗ $label still loaded (this shouldn't happen)${NC}"
        still_loaded=1
    fi
done
if [[ $still_loaded -eq 0 ]]; then
    echo -e "${GREEN}✓ LaunchDaemon successfully removed${NC}"
fi
echo ""

if [[ -f "/Library/Managed Preferences/com.custom.diskencrypter.plist" ]]; then
    echo "Note: settings were left in place (may be managed by MDM):"
    echo "  /Library/Managed Preferences/com.custom.diskencrypter.plist"
    echo ""
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Uninstallation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
