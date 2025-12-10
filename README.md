# DiskEncryption 2.0 Package

**Version:** 2.3
**Date:** December 9, 2025
**Compatibility:** macOS 15+ (Sequoia) and macOS 26+

## What's New in v2.3

- **Changed:** Auto-mount unencrypted disks as read-only before prompting user
- Updated dialog options: "Keep Read-Only", "Eject", "Encrypt"
- Improved user workflow with safer default (read-only mount)
- Scans for Internal SD card slot volumes
  
## What's New in v2.2

- **Fixed:** Read-only mount re-prompt issue - volumes mounted as read-only or unmounted are now automatically skipped during scanning, preventing repeated prompts when new volumes appear

## Package Contents

This package contains all files needed to deploy the DiskEncrypter solution:

```
DiskEncryption2.0/
├── DiskEncrypter_Enhanced.sh                          # Main encryption script
├── com.custom.diskencrypter.volumewatcher.plist      # LaunchDaemon configuration
├── com.custom.diskencrypter.plist                    # Settings/preferences (example)
├── install_launchdaemon.sh                           # Installation script
├── uninstall_launchdaemon.sh                         # Uninstallation script
└── README.md                                         # This file
```

## Quick Start Installation

### 1. Copy Settings File (Optional but Recommended)

```bash
sudo mkdir -p "/Library/Managed Preferences"
sudo cp com.custom.diskencrypter.plist "/Library/Managed Preferences/"
sudo chmod 644 "/Library/Managed Preferences/com.custom.diskencrypter.plist"
sudo chown root:wheel "/Library/Managed Preferences/com.custom.diskencrypter.plist"
```

### 2. Install the LaunchDaemon

```bash
sudo bash install_launchdaemon.sh
```

The installer will:
- Copy the script to `/Library/Application Support/Custom/`
- Install the LaunchDaemon plist to `/Library/LaunchDaemons/`
- Set correct permissions
- Create log files
- Load and start the daemon

### 3. Verify Installation

```bash
sudo launchctl list | grep diskencrypter
```

You should see: `com.custom.diskencrypter.volumewatcher`

### 4. Monitor Logs

```bash
# View main log
tail -f /var/log/diskencrypter.log

# View error log
tail -f /var/log/diskencrypter_error.log
```

## Key Features

### Automatic Encryption Enforcement
- Automatically detects unencrypted external drives
- Prompts users to encrypt or mount read-only
- Supports APFS, HFS+, ExFAT/FAT volumes

### Smart Volume Handling (v2.2)
- **Skips read-only volumes** - won't re-prompt for volumes already mounted read-only
- **Skips unmounted volumes** - ignores volumes that aren't currently mounted
- **Prevents duplicate prompts** - when new volumes appear, previously handled volumes are automatically skipped

### User Options
1. **Encrypt** - Convert and encrypt the volume with user-provided password
2. **Keep Read-Only** - Mount the volume in read-only mode (choice is remembered)
3. **Eject** - Unmount and eject the volume

### Advanced Features
- Dry-run mode for testing
- Configurable log levels (0-3)
- AC power requirement for encryption
- SwiftDialog integration for user notifications
- Multi-volume summary
- Automatic log rotation

## Configuration

Edit `/Library/Managed Preferences/com.custom.diskencrypter.plist` to customize:

### Key Settings

```xml
<!-- Enable dry-run mode (no actual operations) -->
<key>dryRun</key>
<string>no</string>

<!-- Log level: 0=minimal, 1=normal, 2=verbose, 3=debug -->
<key>logLevel</key>
<integer>1</integer>

<!-- Enable user notifications -->
<key>notifyUser</key>
<string>yes</string>

<!-- Password requirements -->
<key>passwordRegex</key>
<string>^[^\s]{4,}$</string>
```

## Command Line Usage

The script can also be run manually with options:

```bash
# Test without making changes
sudo /Library/Application\ Support/Custom/DiskEncrypter_Enhanced.sh --dry-run

# Run with verbose logging
sudo /Library/Application\ Support/Custom/DiskEncrypter_Enhanced.sh --log-level 2

# Combine options
sudo /Library/Application\ Support/Custom/DiskEncrypter_Enhanced.sh --dry-run --log-level 3
```

### Options

- `-d, --dry-run` - Test mode (no actual disk operations)
- `-l, --log-level LEVEL` - Set log level (0-3)
- `-h, --help` - Show help message

## Uninstallation

```bash
sudo bash uninstall_launchdaemon.sh
```

This will:
- Unload the LaunchDaemon
- Remove installed files
- Optionally remove log files

## Troubleshooting

### Check if daemon is running
```bash
sudo launchctl list | grep diskencrypter
```

### Manual daemon control
```bash
# Stop
sudo launchctl unload /Library/LaunchDaemons/com.custom.diskencrypter.volumewatcher.plist

# Start
sudo launchctl load /Library/LaunchDaemons/com.custom.diskencrypter.volumewatcher.plist
```

### Check logs
```bash
# Main log
cat /var/log/diskencrypter.log

# Error log
cat /var/log/diskencrypter_error.log

# System log
log show --predicate 'process == "DiskEncrypter"' --last 1h
```

### Test manually
```bash
# Dry-run mode to test without changes
sudo /Library/Application\ Support/Custom/DiskEncrypter_Enhanced.sh --dry-run --log-level 3
```

## File Locations

| Component | Location |
|-----------|----------|
| Script | `/Library/Application Support/Custom/DiskEncrypter_Enhanced.sh` |
| LaunchDaemon | `/Library/LaunchDaemons/com.custom.diskencrypter.volumewatcher.plist` |
| Settings | `/Library/Managed Preferences/com.custom.diskencrypter.plist` |
| Main Log | `/var/log/diskencrypter.log` |
| Error Log | `/var/log/diskencrypter_error.log` |
| Log Archives | `/var/log/diskencrypter_archives/` |

## Requirements

- macOS 15+ (Sequoia) or macOS 26+
- Full Disk Access permission
- Root/administrator privileges
- AC power for encryption operations
- SwiftDialog (auto-downloaded if not present)

## Version History

### v2.3 - December 9, 2025

- **Changed:** Auto-mount unencrypted disks as read-only before prompting user
- Updated dialog options: "Keep Read-Only", "Eject", "Encrypt"
- Improved user workflow with safer default (read-only mount)
- Scans for Internal SD card slot volumes

### v2.2 - December 4, 2025
- Fixed read-only mount re-prompt issue
- Volumes mounted as read-only are now skipped during scanning
- Unmounted volumes are also skipped
- Prevents duplicate prompts when new volumes appear

### v2.1 - December 3, 2025
- Enhanced with comprehensive logging
- Added dry-run mode
- Added command-line arguments
- Improved macOS 15+ compatibility

### v2.0 - December 3, 2025
- Multi-volume support
- Two-phase processing (scan then encrypt)
- Volume name display
- Encryption summary dialog

## Support

For issues or questions, check the logs first:
```bash
tail -100 /var/log/diskencrypter.log
tail -100 /var/log/diskencrypter_error.log
```

## License

© 2022-2025 Thijs Xhaflaire

## Credits

Created by: Thijs Xhaflaire
Enhanced: December 2025
