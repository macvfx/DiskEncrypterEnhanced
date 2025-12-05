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
PLIST_NAME="com.custom.diskencrypter.volumewatcher.plist"
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
if launchctl list | grep -q "com.custom.diskencrypter.volumewatcher"; then
    launchctl unload "$LAUNCHDAEMON_DIR/$PLIST_NAME" 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}✓ LaunchDaemon unloaded${NC}"
else
    echo -e "${YELLOW}⚠ LaunchDaemon was not loaded${NC}"
fi
echo ""

# Remove plist
echo -e "${YELLOW}Step 2/4: Removing LaunchDaemon plist...${NC}"
if [[ -f "$LAUNCHDAEMON_DIR/$PLIST_NAME" ]]; then
    rm "$LAUNCHDAEMON_DIR/$PLIST_NAME"
    echo -e "${GREEN}✓ Removed $PLIST_NAME${NC}"
else
    echo -e "${YELLOW}⚠ Plist not found${NC}"
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
if launchctl list | grep -q "com.custom.diskencrypter.volumewatcher"; then
    echo -e "${RED}✗ LaunchDaemon still loaded (this shouldn't happen)${NC}"
else
    echo -e "${GREEN}✓ LaunchDaemon successfully removed${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Uninstallation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
