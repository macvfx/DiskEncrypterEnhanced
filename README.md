# DiskEncryption 2.0 "Enhanced"

- **Version:** 2.4.5
- **Date:** December 15, 2025
- **Compatibility:** macOS 15+ (Sequoia) and macOS 26+

## What's New in 2.4.5
- **FIXED:** Password hints can now have spaces when encrypting
- Fixed it twice. Should really work now. Default Managed Pref was blocking.
  
## What's New in 2.4.4
- **FIXED:** Passwords can now have spaces when encrypting
- Fixed a typo in the error dialog
- Fixed the highlighted text in the installer packge install flow

  *KNOWN ISSUES:*
- If HFS formatted volume has a MBR pation scheme then conversion to APFS will fail. You will need to erase the drive
 
## What's New in 2.4.3
- **CHANGED:** Safer option. It does not offer to erase non-encryptable disks , only mount read only or eject
- Instructions in dialog to erase disks after backin up data
- Re-name script from "DiskEncrypter_Enhanced-NO-ERASE.sh" to "DiskEncrypter_Enhanced.sh" to use if installing manually

  *KNOWN ISSUES:*
- If HFS formatted volume has a MBR pation scheme then conversion to APFS will fail. You will need to erase the drive
- Password can't have spaces when encrypting. 
  
## What's New in v2.3

- **Changed:** Auto-mount unencrypted disks as read-only before prompting user
- Use "DiskEncrypter_Enhanced.sh" v.2.3 to if installing manually for the "EraseEncrypt" option
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

### Safer Handling of Unencrypted Volumes ###
- in v.2.4.2 and above there is no erase option (NO_ERASE version of the script)
- instructions for erasing after backups only
  
### Automatic Encryption Enforcement
- Automatically detects unencrypted external drives and mounts as read-only **(v.2.3)**
- Prompts users to encrypt, eject or keep mounted as read-only **(Encrypt and erase option only in v.2.3)**
- Supports APFS, HFS+, ExFAT/FAT/NTFS volumes

### Smart Volume Handling (v2.2)
- **Skips read-only volumes** - won't re-prompt for volumes already mounted read-only
- **Skips unmounted volumes** - ignores volumes that aren't currently mounted
- **Prevents duplicate prompts** - when new volumes appear, previously handled volumes are automatically skipped

### User Options
1. **Encrypt** - Convert and encrypt the volume with user-provided password (**Note:** in v2.3 exFAT, FAT and NTFS volumes will be erased. Make sure your data is backed up if you choose this option)
2. **Keep Read-Only** - Keep the volume in read-only mode (all un-encrypted volumes are automatically re-mounted as read-only)
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

### v2.4.5 - December 15, 2025
- **FIXED:** Password hints can now have spaces when encrypting
  
### v2.4.4 - December 12, 2025
- **FIXED:** Passwords can now have spaces when encrypting
- Fixed a typo in the error dialog
- Fixed the highlighted text in the installer packge install flow
  
### v2.4.3 - December 11, 2025
- Fixed duplicate dialog issue caused by LaunchDaemon re-triggering
- Added lock file mechanism to prevent concurrent runs
- Added processed volumes tracking to prevent re-processing
- Prevents feedback loop from disk unmount events

### v2.4.2 - December 10, 2025
- Improved dialog layout with infobox for detailed instructions
- Reduced main message text to prevent scrolling
- Better user experience with cleaner dialog presentation

### v2.4 - December 10, 2025
- **CHANGED:** Safer option. It does not offer to erase non-encryptable disks , only mount read only or eject
- Instructions in dialog to erase disks after backin up data
- Re-name script from "DiskEncrypter_Enhanced-NO-ERASE.sh" to "DiskEncrypter_Enhanced.sh" to use if installing manually
  
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

© 2022 Thijs Xhaflaire

## Credits

Created by: Thijs Xhaflaire in 2022
Enhanced: December 2025
