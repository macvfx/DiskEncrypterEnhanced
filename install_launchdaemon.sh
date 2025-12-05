#!/bin/bash

# Installation script for DiskEncrypter LaunchDaemon
# macOS 15+ (Sequoia) and macOS 26+ compatible
# Run with: sudo bash install_launchdaemon.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="DiskEncrypter_Enhanced.sh"
PLIST_NAME="com.custom.diskencrypter.volumewatcher.plist"
INSTALL_DIR="/Library/Application Support/Custom"
LAUNCHDAEMON_DIR="/Library/LaunchDaemons"
LOG_DIR="/var/log"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}DiskEncrypter LaunchDaemon Installer${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}ERROR: This script must be run as root${NC}"
   echo "Usage: sudo bash install_launchdaemon.sh"
   exit 1
fi

echo -e "${YELLOW}Step 1/6: Checking prerequisites...${NC}"

# Check if script exists
if [[ ! -f "$SCRIPT_DIR/$SCRIPT_NAME" ]]; then
    echo -e "${RED}ERROR: $SCRIPT_NAME not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Check if plist exists
if [[ ! -f "$SCRIPT_DIR/$PLIST_NAME" ]]; then
    echo -e "${RED}ERROR: $PLIST_NAME not found in $SCRIPT_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Unload existing daemon if running
echo -e "${YELLOW}Step 2/6: Checking for existing installation...${NC}"
if launchctl list | grep -q "com.custom.diskencrypter.volumewatcher"; then
    echo "Unloading existing LaunchDaemon..."
    launchctl unload "$LAUNCHDAEMON_DIR/$PLIST_NAME" 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}✓ Existing daemon unloaded${NC}"
else
    echo -e "${GREEN}✓ No existing daemon found${NC}"
fi
echo ""

# Create installation directory
echo -e "${YELLOW}Step 3/6: Creating installation directory...${NC}"
mkdir -p "$INSTALL_DIR"
echo -e "${GREEN}✓ Created $INSTALL_DIR${NC}"
echo ""

# Copy script
echo -e "${YELLOW}Step 4/6: Installing script...${NC}"
cp "$SCRIPT_DIR/$SCRIPT_NAME" "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR/$SCRIPT_NAME"
chown root:wheel "$INSTALL_DIR/$SCRIPT_NAME"
echo -e "${GREEN}✓ Installed $SCRIPT_NAME to $INSTALL_DIR${NC}"
echo ""

# Copy and set permissions on plist
echo -e "${YELLOW}Step 5/6: Installing LaunchDaemon...${NC}"
cp "$SCRIPT_DIR/$PLIST_NAME" "$LAUNCHDAEMON_DIR/"
chmod 644 "$LAUNCHDAEMON_DIR/$PLIST_NAME"
chown root:wheel "$LAUNCHDAEMON_DIR/$PLIST_NAME"
echo -e "${GREEN}✓ Installed $PLIST_NAME to $LAUNCHDAEMON_DIR${NC}"
echo ""

# Create log files
echo -e "${YELLOW}Step 6/6: Setting up logging...${NC}"
touch "$LOG_DIR/diskencrypter.log"
touch "$LOG_DIR/diskencrypter_error.log"
chmod 644 "$LOG_DIR/diskencrypter.log"
chmod 644 "$LOG_DIR/diskencrypter_error.log"
echo -e "${GREEN}✓ Created log files in $LOG_DIR${NC}"
echo ""

# Load the daemon
echo -e "${YELLOW}Loading LaunchDaemon...${NC}"
launchctl load "$LAUNCHDAEMON_DIR/$PLIST_NAME"
sleep 2
echo ""

# Verify installation
echo -e "${YELLOW}Verifying installation...${NC}"
if launchctl list | grep -q "com.custom.diskencrypter.volumewatcher"; then
    echo -e "${GREEN}✓ LaunchDaemon loaded successfully${NC}"
else
    echo -e "${RED}✗ LaunchDaemon failed to load${NC}"
    echo "Check logs at:"
    echo "  $LOG_DIR/diskencrypter_error.log"
    exit 1
fi
echo ""

# Show status
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Script:       $INSTALL_DIR/$SCRIPT_NAME"
echo "  Plist:        $LAUNCHDAEMON_DIR/$PLIST_NAME"
echo "  Stdout Log:   $LOG_DIR/diskencrypter.log"
echo "  Stderr Log:   $LOG_DIR/diskencrypter_error.log"
echo ""
echo "Monitor logs with:"
echo "  tail -f $LOG_DIR/diskencrypter.log"
echo "  tail -f $LOG_DIR/diskencrypter_error.log"
echo ""
echo "Manage daemon:"
echo "  sudo launchctl unload $LAUNCHDAEMON_DIR/$PLIST_NAME"
echo "  sudo launchctl load $LAUNCHDAEMON_DIR/$PLIST_NAME"
echo "  sudo launchctl start com.custom.diskencrypter.volumewatcher"
echo ""
echo "The daemon will now automatically run when external volumes are mounted."
echo ""
