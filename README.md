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
├── com.custom.diskencrypter.volumewatcher.plist      # LaunchDaemon configuration (script install)
├── com.custom.diskencrypter.plist                    # Settings/preferences (example)
├── install_launchdaemon.sh                           # Installation script
├── uninstall_launchdaemon.sh                         # Uninstallation script
└── README.md                                         # This file
```

## Quick Start Installation

There are two ways to install. They set up the same daemon under **different LaunchDaemon labels** — use one, not both:

| Install method | LaunchDaemon label | Plist |
|---|---|---|
| Installer package from [Releases](https://github.com/macvfx/DiskEncrypterEnhanced/releases) | `com.custom.diskencrypter` | `/Library/LaunchDaemons/com.custom.diskencrypter.plist` |
| `install_launchdaemon.sh` (steps below) | `com.custom.diskencrypter.volumewatcher` | `/Library/LaunchDaemons/com.custom.diskencrypter.volumewatcher.plist` |

The installer package also installs the settings file. To see which label a Mac has:

```bash
ls /Library/LaunchDaemons/ | grep diskencrypter
```

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

You should see `com.custom.diskencrypter.volumewatcher` (script install) or `com.custom.diskencrypter` (installer package). Use `sudo` — without it, `launchctl list` doesn't show system daemons.

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

Works for both the installer package and the script install. This will:
- Unload the LaunchDaemon (either label) and clear any disabled flag
- Remove the LaunchDaemon plist(s), the installed script and the package receipt
- Archive log files to `~/diskencrypter_logs_<timestamp>/`

Settings in `/Library/Managed Preferences/` are left in place, since they may be managed by MDM.

## Troubleshooting

### Check if daemon is running
```bash
sudo launchctl list | grep diskencrypter
```

### Manual daemon control

These use the installer package label, `com.custom.diskencrypter`. For a script install, use `com.custom.diskencrypter.volumewatcher` and its plist instead.

```bash
# Status ("Could not find service" = not loaded)
sudo launchctl print system/com.custom.diskencrypter

# Stop for the current boot session
sudo launchctl bootout system/com.custom.diskencrypter

# Keep stopped across reboots (not needed for a short writing exception)
sudo launchctl disable system/com.custom.diskencrypter

# Re-enable after a persistent disable, then start
sudo launchctl enable system/com.custom.diskencrypter
sudo launchctl bootstrap system /Library/LaunchDaemons/com.custom.diskencrypter.plist
```

Starting the daemon runs the script immediately (`RunAtLoad`) against every mounted volume — eject any drive you don't want it to act on first.

### Temporarily write to an unencrypted disk

Use this procedure only for a deliberate, short-lived exception. Stopping the daemon does **not** change a disk that DiskEncrypter has already mounted read-only; the volume must be unmounted and mounted again after the daemon is confirmed stopped.

First, identify the volume and its parent physical disk. Replace the fictional identifiers below with the values shown by `diskutil list external physical`:

```bash
diskutil list external physical
VOLUME_ID="diskXsY"
PHYSICAL_DISK="diskX"
```

Stop the installer-package daemon and confirm it is no longer loaded:

```bash
sudo launchctl bootout system/com.custom.diskencrypter
sudo launchctl print system/com.custom.diskencrypter
```

The second command should report `Could not find service`. If it still prints service details, **stop here**; do not remount the unencrypted volume while DiskEncrypter remains active.

Remount only the intended volume and verify that it is writable:

```bash
diskutil unmount "$VOLUME_ID"
diskutil mount "$VOLUME_ID"
diskutil info "$VOLUME_ID" | grep -E "Media Read-Only|Volume Read-Only"
```

Both read-only fields should report `No`. If either reports `Yes`, do not write to the disk until the cause is understood. A hardware write-protect switch, unsupported filesystem, damaged filesystem, or another policy can also make a volume read-only.

When the write is complete, eject the physical disk **before** restarting DiskEncrypter:

```bash
diskutil eject "$PHYSICAL_DISK"
sudo launchctl bootstrap system /Library/LaunchDaemons/com.custom.diskencrypter.plist
sudo launchctl print system/com.custom.diskencrypter
```

The final command should print the loaded service. Because the plist uses `RunAtLoad`, restarting DiskEncrypter immediately scans all mounted volumes.

For an installation made with `install_launchdaemon.sh`, substitute these values throughout the stop, status and start commands:

| Setting | Installer package | Script install |
|---|---|---|
| LaunchDaemon label | `com.custom.diskencrypter` | `com.custom.diskencrypter.volumewatcher` |
| LaunchDaemon plist | `/Library/LaunchDaemons/com.custom.diskencrypter.plist` | `/Library/LaunchDaemons/com.custom.diskencrypter.volumewatcher.plist` |

`launchctl bootout` is the appropriate temporary control: the plist remains installed and will load again after `bootstrap` or the next reboot. Avoid `launchctl disable` for a short exception because its disabled state persists across reboots.

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
| LaunchDaemon (installer package) | `/Library/LaunchDaemons/com.custom.diskencrypter.plist` |
| LaunchDaemon (script install) | `/Library/LaunchDaemons/com.custom.diskencrypter.volumewatcher.plist` |
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

### Unreleased
- **FIXED:** `uninstall_launchdaemon.sh` did nothing on Macs installed from the installer package. The package installs LaunchDaemon `com.custom.diskencrypter`, but the uninstaller only looked for `com.custom.diskencrypter.volumewatcher` (the `install_launchdaemon.sh` label), so the daemon stayed loaded after its script was deleted. It now handles both labels and removes the package receipt.
- **DOCS:** Installation, troubleshooting and file locations now cover both LaunchDaemon labels, including a verified stop, remount, write, eject and restart procedure for temporary unencrypted-disk access.

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
