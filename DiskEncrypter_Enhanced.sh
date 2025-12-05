#!/bin/bash

# Created by Thijs Xhaflaire, on 01/10/2022
# Modified on 12/07/2023
# Fixed and improved for macOS 15+ compatibility - 12/03/2025
# Enhanced with comprehensive logging and dry-run mode
# v2.2 - 12/04/2025 - Fixed read-only mount re-prompt issue (corrected field name from "Read-Only Volume" to "Volume Read-Only")
#                   - Added NTFS volume support alongside ExFAT/FAT volumes

## Managed Preferences
settingsPlist="/Library/Managed Preferences/com.custom.diskencrypter.plist"

###########################################
########## COMMAND LINE ARGUMENTS #########
###########################################

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Monitors and enforces encryption on external drives.

OPTIONS:
    -d, --dry-run           Enable dry-run mode (no actual disk operations)
    -l, --log-level LEVEL   Set log level: 0=minimal, 1=normal, 2=verbose, 3=debug
    -h, --help              Show this help message

EXAMPLES:
    $(basename "$0")                    # Run with defaults
    $(basename "$0") --dry-run          # Test without making changes
    $(basename "$0") -l 2               # Run with verbose logging
    $(basename "$0") -d -l 3            # Dry-run with debug logging

NOTES:
    - Command-line arguments override plist settings
    - Without arguments, defaults from plist are used
    - Plist location: $settingsPlist

EOF
    exit 0
}

# Parse command-line arguments
DRY_RUN_CLI=""
LOG_LEVEL_CLI=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN_CLI="yes"
            shift
            ;;
        -l|--log-level)
            if [[ -z "$2" ]] || ! [[ "$2" =~ ^[0-3]$ ]]; then
                echo "ERROR: --log-level requires a value between 0 and 3" >&2
                exit 1
            fi
            LOG_LEVEL_CLI="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

###########################################
############ DRY RUN SETTING ##############
###########################################
## Priority: 1) Command-line, 2) Plist, 3) Default
if [[ -n "$DRY_RUN_CLI" ]]; then
    DRY_RUN="$DRY_RUN_CLI"
else
    DRY_RUN_RAW=$( /usr/libexec/PlistBuddy -c "Print :dryRun" "$settingsPlist" 2>/dev/null )
    if [[ $? -ne 0 ]] || [[ -z "$DRY_RUN_RAW" ]]; then
        DRY_RUN="no"
    else
        DRY_RUN="$DRY_RUN_RAW"
    fi
fi

## Verbose logging level
## 0 = minimal, 1 = normal, 2 = verbose, 3 = debug
## Priority: 1) Command-line, 2) Plist, 3) Default
if [[ -n "$LOG_LEVEL_CLI" ]]; then
    LOG_LEVEL="$LOG_LEVEL_CLI"
else
    LOG_LEVEL_RAW=$( /usr/libexec/PlistBuddy -c "Print :logLevel" "$settingsPlist" 2>/dev/null )
    if [[ $? -ne 0 ]] || [[ -z "$LOG_LEVEL_RAW" ]] || ! [[ "$LOG_LEVEL_RAW" =~ ^[0-3]$ ]]; then
        LOG_LEVEL=1
    else
        LOG_LEVEL="$LOG_LEVEL_RAW"
    fi
fi

###########################################
############ LOGGING FUNCTIONS ############
###########################################

# Get current timestamp in ISO 8601 format
get_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

log_error() {
    echo "[$(get_timestamp)] ERROR: $*" >&2
    logger -p user.error "DiskEncrypter [ERROR]: $*"
}

log_warn() {
    echo "[$(get_timestamp)] WARNING: $*" >&2
    logger -p user.warning "DiskEncrypter [WARN]: $*"
}

log_info() {
    if [[ $LOG_LEVEL -ge 1 ]]; then
        echo "[$(get_timestamp)] INFO: $*"
        logger -p user.info "DiskEncrypter [INFO]: $*"
    fi
}

log_verbose() {
    if [[ $LOG_LEVEL -ge 2 ]]; then
        echo "[$(get_timestamp)] VERBOSE: $*"
        logger -p user.notice "DiskEncrypter [VERBOSE]: $*"
    fi
}

log_debug() {
    if [[ $LOG_LEVEL -ge 3 ]]; then
        echo "[$(get_timestamp)] DEBUG: $*"
        logger -p user.debug "DiskEncrypter [DEBUG]: $*"
    fi
}

log_operation() {
    local operation=$1
    shift
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "[DRY RUN] Would execute: $operation $*"
        logger "DiskEncrypter [DRY RUN]: Would execute: $operation $*"
    else
        log_info "Executing: $operation"
        log_debug "Full command: $operation $*"
    fi
}

###########################################
############ GLOBAL TRACKING ###############
###########################################

# Array to track all encrypted volumes in this session
declare -a ENCRYPTED_VOLUMES=()

# Function to add encrypted volume to tracking array
track_encrypted_volume() {
    local volumeName=$1
    local volumeID=$2
    local volumeType=$3
    ENCRYPTED_VOLUMES+=("$volumeName|$volumeID|$volumeType")
    log_debug "Added to tracking: $volumeName ($volumeID) [$volumeType]"
}

# Function to show summary dialog of all encrypted volumes
show_encryption_summary() {
    local count=${#ENCRYPTED_VOLUMES[@]}

    if [[ $count -eq 0 ]]; then
        return
    fi

    log_info "Showing encryption summary for $count volume(s)"

    # Build summary message
    local summaryMessage=""
    if [[ $count -eq 1 ]]; then
        summaryMessage="The following volume was encrypted during this session:\\n\\n"
    else
        summaryMessage="The following $count volumes were encrypted during this session:\\n\\n"
    fi

    # Add each encrypted volume to the message
    for entry in "${ENCRYPTED_VOLUMES[@]}"; do
        IFS='|' read -r volName volID volType <<< "$entry"
        summaryMessage+="• \"$volName\" ($volID)\\n  Type: $volType\\n\\n"
    done

    summaryMessage+="All encryption processes are running in the background and will complete shortly."

    # Show summary dialog
    if [[ "$DRY_RUN" != "yes" ]] && [[ -f "$notificationApp" ]]; then
        runDialogAsUser \
            --title "Encryption Summary" \
            --message "$summaryMessage" \
            --icon "$iconPath" \
            --button1text "OK" \
            --timer 15
    else
        log_info "ENCRYPTION SUMMARY:"
        for entry in "${ENCRYPTED_VOLUMES[@]}"; do
            IFS='|' read -r volName volID volType <<< "$entry"
            log_info "  - \"$volName\" ($volID) [$volType]"
        done
    fi
}

###########################################
############ SETTINGS FUNCTIONS ###########
###########################################

readSetting() {
    local key=$1
    local defaultValue=$2

    if ! value=$( /usr/libexec/PlistBuddy -c "Print :$key" "$settingsPlist" 2>/dev/null ); then
        value="$defaultValue"
    fi
    echo "$value"
}

readSettingsFile(){
    log_debug "Reading settings from $settingsPlist"

    ## USER NOTIFICATION SETTINGS
    notifyUser=$( readSetting notifyUser "yes" )
    notifyUserHint=$( readSetting notifyUserHint "yes" )
    downloadSwiftDialog=$( readSetting downloadSwiftDialog "yes" )
    notificationApp=$( readSetting notificationApp "/usr/local/bin/dialog" )

    ## swiftDialog Customization
    companyName=$( readSetting companyName "Jamf" )
    iconPath=$( readSetting iconPath "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns" )
    batteryIconPath=$( readSetting batteryIconPath "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns")

    ## General text section
    title=$( readSetting title "Unencrypted Removable Media Device detected" )
    subTitleBattery=$( readSetting subTitleBattery "The Mac is not connected to AC Power and therefore the removable media device can't be encrypted, plug in the AC adapter and try again")
    batteryExitMainButton=$( readSetting batteryExitMainButton "Quit" )
    subTitlePassword=$( readSetting subTitlePassword "Writing files to unencrypted removable media devices is not allowed, encrypt the disk in order to allow writing files. securely store the password and in case of loss the data will be unaccesible!" )
    mainButtonLabelPassword=$( readSetting mainButtonLabelPassword "Continue" )
    subTitleConversion=$( readSetting subTitleConversion "Writing files to unencrypted removable media devices is not allowed, encrypt the disk in order to allow writing files. we need to convert this volume to APFS before encryption. Securely store the password and in case of loss the data will be unaccesible!" )
    mainButtonLabelConversion=$( readSetting mainButtonLabelConversion "Convert" )
    subTitleEXFAT=$( readSetting subTitleEXFAT "Writing files to unencrypted removable media devices is not allowed, encrypt the disk in order to allow writing files. As this volume type does not support conversion or encryption we need to erase the volume. all existing content will be erased!!!. Securely store the password and in case of loss the data will be unaccesible!" )
    mainButtonLabelEXFAT=$( readSetting mainButtonLabelEXFAT "Erase existing data and encrypt" )
    exitButtonLabel=$( readSetting exitButtonLabel "Eject" )

    ## Password text and REGEX requirements
    secondTitlePassword=$( readSetting secondTitlePassword "Enter the password you want to use to encrypt the removable media" )
    placeholderPassword=$( readSetting placeholderPassword "Enter password here" )
    secondaryButtonLabelPassword=$( readSetting secondaryButtonLabelPassword "Mount as read-only" )
    passwordRegex=$( readSetting passwordRegex "^[^\s]{4,}$" )
    passwordRegexErrorMessage=$( readSetting passwordRegexErrorMessage "The provided password does not meet the requirements, please use at leasts 4 characters" )

    ## Hint text and REGEX requirements
    subTitleHint=$( readSetting subTitleHint "Optionally you can specify a hint, a password hint is a sort of reminder that helps the user remember their password." )
    mainButtonLabelHint=$( readSetting mainButtonLabelHint "Encrypt" )
    secondaryButtonLabelHint=$( readSetting secondaryButtonLabelHint "Encrypt w/o hint" )
    secondTitleHint=$( readSetting secondTitleHint "Enter the hint you want to set" )
    placeholderHint=$( readSetting placeholderHint "Enter hint here" )
    hintRegex=$( readSetting hintRegex "^[^\s]{6,}$" )
    hintRegexErrorMessage=$( readSetting hintRegexErrorMessage "The provided hint does not meet the requirements, please use a stronger hint that contains 6 characters" )

    ## Progress bar text
    titleProgress=$( readSetting titleProgress "Disk Encryption Progress" )
    subTitleProgress=$( readSetting subTitleProgress "Please wait while the external disk is being encrypted." )
    mainButtonLabelProgress=$( readSetting mainButtonLabelProgress "Exit" )

    log_verbose "Settings loaded: notifyUser=$notifyUser, DRY_RUN=$DRY_RUN, LOG_LEVEL=$LOG_LEVEL"
}

###########################################
############ UTILITY FUNCTIONS ############
###########################################

cleanup() {
    log_debug "Cleaning up sensitive data from memory"
    unset Password
    unset Passphrase
}

trap cleanup EXIT

checkFullDiskAccess() {
    log_verbose "Checking for Full Disk Access permission"
    if ! diskutil list >/dev/null 2>&1; then
        log_error "This script requires Full Disk Access permission"
        exit 1
    fi
    log_verbose "Full Disk Access permission verified"
}

installSwiftDialog() {
    if [[ "$downloadSwiftDialog" == "yes" ]] && [[ ! -f "$notificationApp" ]]; then

        log_info "swiftDialog not installed, downloading and installing"

        expectedDialogTeamID="PWA5E9TQ59"

        log_verbose "Fetching latest swiftDialog release URL"
        LOCATION=$(/usr/bin/curl -s https://api.github.com/repos/bartreardon/swiftDialog/releases/latest | grep browser_download_url | grep .pkg | grep -v debug | awk '{ print $2 }' | sed 's/,$//' | sed 's/"//g')

        if [[ -z "$LOCATION" ]]; then
            log_error "Failed to get swiftDialog download URL"
            return 1
        fi

        log_debug "Download URL: $LOCATION"

        if [[ "$DRY_RUN" == "yes" ]]; then
            log_operation "curl" "-L $LOCATION -o /tmp/swiftDialog.pkg"
            log_operation "installer" "-pkg /tmp/swiftDialog.pkg -target /"
            return 0
        fi

        log_verbose "Downloading swiftDialog package"
        /usr/bin/curl -L "$LOCATION" -o /tmp/swiftDialog.pkg

        if [[ ! -f /tmp/swiftDialog.pkg ]]; then
            log_error "Failed to download swiftDialog"
            return 1
        fi

        log_verbose "Verifying package signature"
        teamID=$(/usr/sbin/spctl -a -vv -t install "/tmp/swiftDialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')

        if [[ "$expectedDialogTeamID" = "$teamID" ]] || [[ "$expectedDialogTeamID" = "" ]]; then
            log_info "swiftDialog Team ID verification succeeded (TeamID: $teamID)"
            /usr/sbin/installer -pkg /tmp/swiftDialog.pkg -target /
        else
            log_error "swiftDialog Team ID verification failed. Expected: $expectedDialogTeamID, Got: $teamID"
            /bin/rm /tmp/swiftDialog.pkg
            return 1
        fi

        log_verbose "Cleaning up swiftDialog.pkg"
        /bin/rm /tmp/swiftDialog.pkg
    else
        log_debug "swiftDialog already installed at $notificationApp"
    fi
    return 0
}

runDialogAsUser() {
    # Run swiftDialog in the logged-in user's GUI session
    # This is critical when running as root via LaunchDaemon

    if [[ -n "$loggedInUserUID" ]]; then
        # Use launchctl asuser to run in user's GUI session
        /bin/launchctl asuser "$loggedInUserUID" sudo -u "$loggedInUser" "$notificationApp" "$@"
    else
        # Fallback to simple sudo -u
        /usr/bin/sudo -u "$loggedInUser" "$notificationApp" "$@"
    fi
}

checkACPower() {
    log_verbose "Checking power source status"
    if [[ $(pmset -g ps | head -1) =~ "AC Power" ]]; then
        log_info "Device is connected to AC Power, proceeding"
        return 0
    else
        log_warn "Device is connected to battery and not charging, exiting"
        if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]]; then
            runDialogAsUser --title "$title" --message "$subTitleBattery" --button1text "$batteryExitMainButton" --icon "$batteryIconPath"
        fi
        return 1
    fi
}

###########################################
############ DISK OPERATIONS ##############
###########################################

processAPFSDisk() {
    local DiskID=$1
    local VolumeID=$2
    local volumeName=$3

    log_info "Processing APFS disk: $DiskID (Volume: $VolumeID, Name: '$volumeName')"

    # Install swiftDialog first if needed
    if ! installSwiftDialog; then
        log_error "Failed to install swiftDialog"
        exit 1
    fi

    # Show user dialog FIRST to get their choice
    if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]]; then
        log_verbose "Displaying options dialog to user for volume: $volumeName ($VolumeID)"

        # Construct custom message including volume name
        customMessage="Unencrypted volume detected: \"$volumeName\" ($VolumeID)\n\n$subTitlePassword"

        if [[ "$DRY_RUN" == "yes" ]]; then
            log_operation "swiftDialog" "password prompt"
            Password="DRY_RUN_PASSWORD"
            dialogExitCode=0
        else
            dialog=$(runDialogAsUser --title "$title" --message "$customMessage" --button1text "$mainButtonLabelPassword" --button2text "$secondaryButtonLabelPassword" --infobuttontext "$exitButtonLabel" --quitoninfo --icon "$iconPath" --textfield "$secondTitlePassword",prompt="$placeholderPassword",regex="$passwordRegex",regexerror="$passwordRegexErrorMessage",secure=true,required=yes)
            dialogExitCode=$?
            Password=$(echo "$dialog" | grep "$secondTitlePassword" | awk -F " : " '{print $NF}')
        fi
    else
        log_error "User notification is disabled or swiftDialog is not available"
        exit 1
    fi

    case $dialogExitCode in
        0)
        log_info "User chose to encrypt disk $DiskID"

        # Check AC Power only when user chooses to encrypt
        if ! checkACPower; then
            exit 1
        fi

        if [[ -z "$Password" ]] && [[ "$DRY_RUN" != "yes" ]]; then
            log_error "Password is empty, cannot proceed"
            exit 1
        fi

        log_verbose "Password received (length: ${#Password} characters)"

        if [[ "$notifyUserHint" == "yes" ]] && [[ -f "$notificationApp" ]]; then
            log_verbose "Displaying hint prompt to user"

            if [[ "$DRY_RUN" == "yes" ]]; then
                log_operation "swiftDialog" "hint prompt"
                Passphrase="DRY_RUN_HINT"
            else
                hintDialog=$(runDialogAsUser --title "$title" --message "$subTitleHint" --button1text "$mainButtonLabelHint" --button2text "$secondaryButtonLabelHint" --icon "$iconPath" --textfield "$secondTitleHint",prompt="$placeholderHint",regex="$hintRegex",regexerror="$hintRegexErrorMessage")
                Passphrase=$(echo "$hintDialog" | grep "$secondTitleHint" | awk -F " : " '{print $NF}')
            fi

            if [[ -n "$Passphrase" ]]; then
                log_verbose "Hint provided by user"
            else
                log_verbose "No hint provided by user"
            fi
        fi

        if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]] && [[ -n "$Password" ]]; then

            if [[ "$DRY_RUN" != "yes" ]]; then
                # Include volume name in progress message
                progressMessage="Encrypting volume: \"$volumeName\" ($VolumeID)\n\n$subTitleProgress"
                runDialogAsUser --title "$titleProgress" --message "$progressMessage" --icon "$iconPath" --button1text "$mainButtonLabelProgress" --timer 60 --progresstext "Encrypting \"$volumeName\" ($VolumeID)..." &
                dialogPID=$!
                log_debug "Progress dialog PID: $dialogPID"
            fi

            log_operation "diskutil unmountDisk" "$VolumeID"
            [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$VolumeID" 2>/dev/null

            log_operation "diskutil mount" "$VolumeID"
            [[ "$DRY_RUN" != "yes" ]] && diskutil mount "$VolumeID"

            log_operation "diskutil apfs encryptVolume" "$VolumeID -user disk"

            if [[ "$DRY_RUN" == "yes" ]]; then
                log_info "DRY RUN: Encryption would start for $VolumeID"
                encryptSuccess=true
            else
                if diskutil apfs encryptVolume "$VolumeID" -user "disk" -passphrase "$Password"; then
                    encryptSuccess=true
                else
                    encryptSuccess=false
                fi
            fi

            if [[ "$encryptSuccess" == true ]]; then
                log_info "Encryption started successfully for $VolumeID"

                if [[ -n "$Passphrase" ]]; then
                    log_verbose "Setting passphrase hint"
                    sleep 5

                    log_operation "diskutil unmountDisk" "$DiskID"
                    [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$DiskID" 2>/dev/null

                    log_operation "diskutil apfs unlockVolume" "$VolumeID"

                    if [[ "$DRY_RUN" == "yes" ]] || diskutil apfs unlockVolume "$VolumeID" -passphrase "$Password"; then
                        log_operation "diskutil apfs setPassphraseHint" "$VolumeID"

                        if [[ "$DRY_RUN" != "yes" ]]; then
                            diskutil apfs setPassphraseHint "$VolumeID" -user "disk" -hint "$Passphrase"
                        fi

                        log_info "Passphrase hint set successfully"
                    else
                        log_warn "Failed to unlock volume for hint setting"
                    fi
                fi

                # Show success dialog instead of just killing progress dialog
                if [[ "$DRY_RUN" != "yes" ]]; then
                    kill $dialogPID 2>/dev/null
                    runDialogAsUser \
                        --title "Encryption Complete" \
                        --message "Volume \"$volumeName\" ($VolumeID) has been successfully encrypted.\n\nThe encryption process is running in the background and will complete shortly." \
                        --icon "$iconPath" \
                        --button1text "OK" \
                        --timer 10
                fi

                # Track this encrypted volume for summary
                track_encrypted_volume "$volumeName" "$VolumeID" "APFS"

                log_info "APFS disk encryption workflow completed successfully"
                return 0
            else
                log_error "Encryption failed for $VolumeID"
                if [[ "$DRY_RUN" != "yes" ]]; then
                    kill $dialogPID 2>/dev/null
                    runDialogAsUser \
                        --title "Encryption Failed" \
                        --message "Failed to encrypt volume \"$volumeName\" ($VolumeID).\n\nPlease check the system logs for details." \
                        --icon "$iconPath" \
                        --button1text "OK"
                fi
                return 1
            fi
        fi
        ;;
        2)
        log_info "$loggedInUser decided to mount $DiskID as read-only"
        log_operation "diskutil unmountDisk" "$DiskID"
        [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$DiskID" 2>/dev/null

        log_operation "diskutil mount readOnly" "$VolumeID"
        [[ "$DRY_RUN" != "yes" ]] && diskutil mount readOnly "$VolumeID"
        return 2
        ;;
        3)
        log_info "$loggedInUser decided to eject $DiskID"
        log_operation "diskutil unmountDisk" "$DiskID"
        [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$DiskID" 2>/dev/null
        return 3
        ;;
    esac
}

processHFSDisk() {
    local DiskID=$1
    local VolumeID=$2
    local volumeName=$3

    log_info "Processing HFS disk: $DiskID (Volume: $VolumeID, Name: '$volumeName')"
    log_warn "HFS volume requires conversion to APFS before encryption"

    # Install swiftDialog first if needed
    if ! installSwiftDialog; then
        log_error "Failed to install swiftDialog"
        exit 1
    fi

    # Show user dialog FIRST to get their choice
    if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]]; then
        log_verbose "Displaying conversion options to user for volume: $volumeName ($VolumeID)"

        # Construct custom message including volume name
        customMessage="Unencrypted HFS+ volume detected: \"$volumeName\" ($VolumeID)\n\n$subTitleConversion"

        if [[ "$DRY_RUN" == "yes" ]]; then
            log_operation "swiftDialog" "conversion prompt"
            Password="DRY_RUN_PASSWORD"
            dialogExitCode=0
        else
            dialog=$(runDialogAsUser --title "$title" --message "$customMessage" --button1text "$mainButtonLabelConversion" --button2text "$secondaryButtonLabelPassword" --infobuttontext "$exitButtonLabel" --quitoninfo --icon "$iconPath" --textfield "$secondTitlePassword",prompt="$placeholderPassword",regex="$passwordRegex",regexerror="$passwordRegexErrorMessage",secure=true,required=yes)
            dialogExitCode=$?
            Password=$(echo "$dialog" | grep "$secondTitlePassword" | awk -F " : " '{print $NF}')
        fi
    else
        log_error "User notification is disabled or swiftDialog is not available"
        exit 1
    fi

    case $dialogExitCode in
        0)
        log_info "User chose to convert and encrypt disk $DiskID"

        # Check AC Power only when user chooses to encrypt
        if ! checkACPower; then
            exit 1
        fi

        if [[ -z "$Password" ]] && [[ "$DRY_RUN" != "yes" ]]; then
            log_error "Password is empty, cannot proceed"
            exit 1
        fi

        if [[ "$notifyUserHint" == "yes" ]] && [[ -f "$notificationApp" ]]; then
            if [[ "$DRY_RUN" == "yes" ]]; then
                Passphrase="DRY_RUN_HINT"
            else
                hintDialog=$(runDialogAsUser --title "$title" --message "$subTitleHint" --button1text "$mainButtonLabelHint" --button2text "$secondaryButtonLabelHint" --icon "$iconPath" --textfield "$secondTitleHint",prompt="$placeholderHint",regex="$hintRegex",regexerror="$hintRegexErrorMessage")
                Passphrase=$(echo "$hintDialog" | grep "$secondTitleHint" | awk -F " : " '{print $NF}')
            fi
        fi

        if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]] && [[ -n "$Password" ]]; then

            if [[ "$DRY_RUN" != "yes" ]]; then
                # Include volume name in progress message
                progressMessage="Converting and encrypting volume: \"$volumeName\" ($VolumeID)\n\n$subTitleProgress"
                runDialogAsUser --title "$titleProgress" --message "$progressMessage" --icon "$iconPath" --button1text "$mainButtonLabelProgress" --timer 60 --progresstext "Converting and encrypting \"$volumeName\" ($VolumeID)..." &
                dialogPID=$!
            fi

            log_operation "diskutil unmountDisk" "$VolumeID"
            [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$VolumeID" 2>/dev/null

            log_operation "diskutil mount" "$VolumeID"
            [[ "$DRY_RUN" != "yes" ]] && diskutil mount "$VolumeID"

            log_operation "diskutil apfs convert" "$VolumeID"

            if [[ "$DRY_RUN" == "yes" ]]; then
                log_info "DRY RUN: Conversion to APFS would proceed"
                convertSuccess=true
                NewDiskID="disk99"
                NewVolumeID="disk99s1"
            else
                if diskutil apfs convert "$VolumeID"; then
                    convertSuccess=true
                    log_info "Conversion to APFS successful"

                    sleep 2
                    NewDiskID=$(diskutil list "$DiskID" | grep -o 'Container disk[0-9]*' | awk '{print $2}')
                    NewVolumeID="${NewDiskID}s1"

                    log_info "New APFS container: $NewDiskID, Volume: $NewVolumeID"
                else
                    convertSuccess=false
                fi
            fi

            if [[ "$convertSuccess" == true ]]; then
                log_operation "diskutil apfs encryptVolume" "$NewVolumeID -user disk"

                if [[ "$DRY_RUN" == "yes" ]] || diskutil apfs encryptVolume "$NewVolumeID" -user "disk" -passphrase "$Password"; then
                    log_info "Encryption started successfully for $NewVolumeID"

                    if [[ -n "$Passphrase" ]]; then
                        sleep 5
                        log_operation "diskutil unmountDisk" "$NewDiskID"
                        [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$NewDiskID" 2>/dev/null

                        if [[ "$DRY_RUN" == "yes" ]] || diskutil apfs unlockVolume "$NewVolumeID" -passphrase "$Password"; then
                            log_operation "diskutil apfs setPassphraseHint" "$NewVolumeID"
                            [[ "$DRY_RUN" != "yes" ]] && diskutil apfs setPassphraseHint "$NewVolumeID" -user "disk" -hint "$Passphrase"
                            log_info "Passphrase hint set successfully"
                        fi
                    fi

                    # Show success dialog instead of just killing progress dialog
                    if [[ "$DRY_RUN" != "yes" ]]; then
                        kill $dialogPID 2>/dev/null
                        runDialogAsUser \
                            --title "Encryption Complete" \
                            --message "Volume \"$volumeName\" ($NewVolumeID) has been successfully converted to APFS and encrypted.\n\nThe encryption process is running in the background and will complete shortly." \
                            --icon "$iconPath" \
                            --button1text "OK" \
                            --timer 10
                    fi

                    # Track this encrypted volume for summary
                    track_encrypted_volume "$volumeName" "$NewVolumeID" "HFS+ (Converted)"

                    log_info "HFS conversion and encryption workflow completed successfully"
                    return 0
                else
                    log_error "Encryption failed for $NewVolumeID"
                    if [[ "$DRY_RUN" != "yes" ]]; then
                        kill $dialogPID 2>/dev/null
                        runDialogAsUser \
                            --title "Encryption Failed" \
                            --message "Failed to encrypt volume \"$volumeName\" ($NewVolumeID).\n\nPlease check the system logs for details." \
                            --icon "$iconPath" \
                            --button1text "OK"
                    fi
                    return 1
                fi
            else
                log_error "APFS conversion failed"
                if [[ "$DRY_RUN" != "yes" ]]; then
                    kill $dialogPID 2>/dev/null
                    runDialogAsUser \
                        --title "Conversion Failed" \
                        --message "Failed to convert volume \"$volumeName\" ($VolumeID) to APFS.\n\nPlease check the system logs for details." \
                        --icon "$iconPath" \
                        --button1text "OK"
                fi
                return 1
            fi
        fi
        ;;
        2)
        log_info "$loggedInUser decided to mount $DiskID as read-only"
        log_operation "diskutil unmountDisk" "$DiskID"
        [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$DiskID" 2>/dev/null

        log_operation "diskutil mount readOnly" "$VolumeID"
        [[ "$DRY_RUN" != "yes" ]] && diskutil mount readOnly "$VolumeID"
        return 2
        ;;
        3)
        log_info "$loggedInUser decided to eject $DiskID"
        log_operation "diskutil unmountDisk" "$DiskID"
        [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$DiskID" 2>/dev/null
        return 3
        ;;
    esac
}

processExFATDisk() {
    local DiskID=$1
    local VolumeID=$2
    local volumeName=$3

    log_info "Processing ExFAT/FAT disk: $DiskID (Volume: $VolumeID, Name: '$volumeName')"
    log_warn "ExFAT/FAT volume requires erasure - ALL DATA WILL BE LOST"

    # Install swiftDialog first if needed
    if ! installSwiftDialog; then
        log_error "Failed to install swiftDialog"
        exit 1
    fi

    # Show user dialog FIRST to get their choice
    if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]]; then
        log_verbose "Displaying erase warning to user for volume: $volumeName ($VolumeID)"

        # Construct custom message including volume name
        customMessage="Unencrypted ExFAT/FAT volume detected: \"$volumeName\" ($VolumeID)\n\n$subTitleEXFAT"

        if [[ "$DRY_RUN" == "yes" ]]; then
            log_operation "swiftDialog" "erase prompt"
            Password="DRY_RUN_PASSWORD"
            dialogExitCode=0
        else
            dialog=$(runDialogAsUser --title "$title" --message "$customMessage" --button1text "$mainButtonLabelEXFAT" --button2text "$secondaryButtonLabelPassword" --infobuttontext "$exitButtonLabel" --quitoninfo --icon "$iconPath" --textfield "$secondTitlePassword",prompt="$placeholderPassword",regex="$passwordRegex",regexerror="$passwordRegexErrorMessage",secure=true,required=yes)
            dialogExitCode=$?
            Password=$(echo "$dialog" | grep "$secondTitlePassword" | awk -F " : " '{print $NF}')
        fi
    else
        log_error "User notification is disabled or swiftDialog is not available"
        exit 1
    fi

    case $dialogExitCode in
        0)
        log_info "User chose to erase and encrypt disk $DiskID"
        log_warn "DESTRUCTIVE OPERATION: Erasing all data on $DiskID ($volumeName)"

        # Check AC Power only when user chooses to encrypt
        if ! checkACPower; then
            exit 1
        fi

        if [[ -z "$Password" ]] && [[ "$DRY_RUN" != "yes" ]]; then
            log_error "Password is empty, cannot proceed"
            exit 1
        fi

        if [[ "$notifyUserHint" == "yes" ]] && [[ -f "$notificationApp" ]]; then
            if [[ "$DRY_RUN" == "yes" ]]; then
                Passphrase="DRY_RUN_HINT"
            else
                hintDialog=$(runDialogAsUser --title "$title" --message "$subTitleHint" --button1text "$mainButtonLabelHint" --button2text "$secondaryButtonLabelHint" --icon "$iconPath" --textfield "$secondTitleHint",prompt="$placeholderHint",regex="$hintRegex",regexerror="$hintRegexErrorMessage")
                Passphrase=$(echo "$hintDialog" | grep "$secondTitleHint" | awk -F " : " '{print $NF}')
            fi
        fi

        if [[ "$notifyUser" == "yes" ]] && [[ -f "$notificationApp" ]] && [[ -n "$Password" ]]; then

            if [[ "$DRY_RUN" != "yes" ]]; then
                # Include volume name in progress message
                progressMessage="Erasing and encrypting volume: \"$volumeName\" ($VolumeID)\n\n$subTitleProgress"
                runDialogAsUser --title "$titleProgress" --message "$progressMessage" --icon "$iconPath" --button1text "$mainButtonLabelProgress" --timer 60 --progresstext "Erasing and encrypting \"$volumeName\"..." &
                dialogPID=$!
            fi

            safeVolumeName="${volumeName// /_}"
            if [[ -z "$safeVolumeName" ]]; then
                safeVolumeName="EncryptedDisk"
            fi

            log_debug "Safe volume name: $safeVolumeName"
            log_operation "diskutil eraseDisk APFS" "$safeVolumeName $DiskID"

            if [[ "$DRY_RUN" == "yes" ]]; then
                log_warn "DRY RUN: Disk would be erased here - ALL DATA WOULD BE LOST"
                eraseSuccess=true
                NewDiskID="disk99"
                NewVolumeID="disk99s1"
            else
                if diskutil eraseDisk APFS "$safeVolumeName" "$DiskID"; then
                    eraseSuccess=true
                    log_info "Disk erased and formatted successfully"

                    sleep 2
                    NewDiskID=$(diskutil list "$DiskID" | grep -o 'Container disk[0-9]*' | awk '{print $2}')
                    NewVolumeID=$(diskutil list "$NewDiskID" | grep "APFS Volume" | head -1 | awk '{print $NF}' | sed 's/^//')

                    if [[ -z "$NewVolumeID" ]]; then
                        NewVolumeID="${NewDiskID}s1"
                    fi

                    log_info "New APFS container: $NewDiskID, Volume: $NewVolumeID"
                else
                    eraseSuccess=false
                fi
            fi

            if [[ "$eraseSuccess" == true ]]; then
                log_operation "diskutil apfs encryptVolume" "$NewVolumeID -user disk"

                if [[ "$DRY_RUN" == "yes" ]] || diskutil apfs encryptVolume "$NewVolumeID" -user "disk" -passphrase "$Password"; then
                    log_info "Encryption started successfully for $NewVolumeID"

                    if [[ -n "$Passphrase" ]]; then
                        sleep 5
                        log_operation "diskutil unmountDisk" "$NewDiskID"
                        [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$NewDiskID" 2>/dev/null

                        if [[ "$DRY_RUN" == "yes" ]] || diskutil apfs unlockVolume "$NewVolumeID" -passphrase "$Password"; then
                            log_operation "diskutil apfs setPassphraseHint" "$NewVolumeID"
                            [[ "$DRY_RUN" != "yes" ]] && diskutil apfs setPassphraseHint "$NewVolumeID" -user "disk" -hint "$Passphrase"
                            log_info "Passphrase hint set successfully"
                        fi
                    fi

                    # Show success dialog instead of just killing progress dialog
                    if [[ "$DRY_RUN" != "yes" ]]; then
                        kill $dialogPID 2>/dev/null
                        runDialogAsUser \
                            --title "Encryption Complete" \
                            --message "Volume \"$volumeName\" has been successfully erased, formatted as APFS, and encrypted.\n\nThe encryption process is running in the background and will complete shortly." \
                            --icon "$iconPath" \
                            --button1text "OK" \
                            --timer 10
                    fi

                    # Track this encrypted volume for summary
                    track_encrypted_volume "$volumeName" "$NewVolumeID" "ExFAT (Erased)"

                    log_info "ExFAT erase and encryption workflow completed successfully"
                    return 0
                else
                    log_error "Encryption failed for $NewVolumeID"
                    if [[ "$DRY_RUN" != "yes" ]]; then
                        kill $dialogPID 2>/dev/null
                        runDialogAsUser \
                            --title "Encryption Failed" \
                            --message "Failed to encrypt volume \"$volumeName\".\n\nPlease check the system logs for details." \
                            --icon "$iconPath" \
                            --button1text "OK"
                    fi
                    return 1
                fi
            else
                log_error "Disk erase failed"
                if [[ "$DRY_RUN" != "yes" ]]; then
                    kill $dialogPID 2>/dev/null
                    runDialogAsUser \
                        --title "Erase Failed" \
                        --message "Failed to erase and format volume \"$volumeName\" ($VolumeID).\n\nPlease check the system logs for details." \
                        --icon "$iconPath" \
                        --button1text "OK"
                fi
                return 1
            fi
        fi
        ;;
        2)
        log_info "$loggedInUser decided to mount $DiskID as read-only"
        log_operation "diskutil unmountDisk" "$DiskID"
        [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$DiskID" 2>/dev/null

        log_operation "diskutil mount readOnly" "$VolumeID"
        [[ "$DRY_RUN" != "yes" ]] && diskutil mount readOnly "$VolumeID"
        return 2
        ;;
        3)
        log_info "$loggedInUser decided to eject $DiskID"
        log_operation "diskutil unmountDisk" "$DiskID"
        [[ "$DRY_RUN" != "yes" ]] && diskutil unmountDisk "$DiskID" 2>/dev/null
        return 3
        ;;
    esac
}

###########################################
########## LOG ROTATION FUNCTION ###########
###########################################

rotate_logs() {
    local log_file="/var/log/diskencrypter.log"
    local error_log_file="/var/log/diskencrypter_error.log"
    local archive_dir="/var/log/diskencrypter_archives"
    local today=$(date +"%Y-%m-%d")

    # Create archive directory if it doesn't exist
    if [[ ! -d "$archive_dir" ]]; then
        mkdir -p "$archive_dir" 2>/dev/null
        chmod 755 "$archive_dir" 2>/dev/null
    fi

    # Check if logs need rotation (if they have entries from previous days)
    if [[ -f "$log_file" ]]; then
        # Get the date of the first log entry (if it exists)
        local first_log_date=$(head -1 "$log_file" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)

        # If log exists and has a date, and it's not today, rotate it
        if [[ -n "$first_log_date" ]] && [[ "$first_log_date" != "$today" ]]; then
            local archive_name="diskencrypter_${first_log_date}.log"

            # Archive the old log with compression
            if [[ -s "$log_file" ]]; then
                gzip -c "$log_file" > "$archive_dir/$archive_name.gz" 2>/dev/null
                : > "$log_file"  # Truncate the log file
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] INFO: Log rotated, archived to $archive_dir/$archive_name.gz" >> "$log_file"
            fi
        fi
    fi

    # Rotate error log
    if [[ -f "$error_log_file" ]]; then
        local first_error_date=$(head -1 "$error_log_file" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)

        if [[ -n "$first_error_date" ]] && [[ "$first_error_date" != "$today" ]]; then
            local error_archive_name="diskencrypter_error_${first_error_date}.log"

            if [[ -s "$error_log_file" ]]; then
                gzip -c "$error_log_file" > "$archive_dir/$error_archive_name.gz" 2>/dev/null
                : > "$error_log_file"
                echo "[$(date +"%Y-%m-%d %H:%M:%S")] INFO: Error log rotated, archived to $archive_dir/$error_archive_name.gz" >> "$error_log_file"
            fi
        fi
    fi

    # Clean up archives older than 30 days
    if [[ -d "$archive_dir" ]]; then
        find "$archive_dir" -name "*.log.gz" -type f -mtime +30 -delete 2>/dev/null
    fi
}

###########################################
############ MAIN EXECUTION ###############
###########################################

main() {
    # Rotate logs at the start of each run
    rotate_logs
    # Determine configuration source
    local dryRunSource="default"
    local logLevelSource="default"

    [[ -n "$DRY_RUN_CLI" ]] && dryRunSource="command-line"
    [[ -z "$DRY_RUN_CLI" ]] && [[ -n "$DRY_RUN_RAW" ]] && dryRunSource="plist"

    [[ -n "$LOG_LEVEL_CLI" ]] && logLevelSource="command-line"
    [[ -z "$LOG_LEVEL_CLI" ]] && [[ -n "$LOG_LEVEL_RAW" ]] && logLevelSource="plist"

    log_info "========================================="
    log_info "DiskEncrypter Script Starting"
    log_info "Version: 2.0 Enhanced (Dry-Run Capable)"
    log_info "========================================="
    log_info "DRY RUN MODE: $DRY_RUN (source: $dryRunSource)"
    log_info "LOG LEVEL: $LOG_LEVEL (source: $logLevelSource)"
    log_info "  0=minimal, 1=normal, 2=verbose, 3=debug"
    log_info "========================================="

    if [[ "$DRY_RUN" == "yes" ]]; then
        log_warn "*** DRY RUN MODE ENABLED - NO ACTUAL OPERATIONS WILL BE PERFORMED ***"
    fi

    loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
    log_info "Logged in user: $loggedInUser"

    # Get user ID for GUI session context
    if [[ -n "$loggedInUser" ]]; then
        loggedInUserUID=$(id -u "$loggedInUser")
        log_debug "Logged in user UID: $loggedInUserUID"
    else
        log_error "No logged in user found"
        exit 1
    fi

    checkFullDiskAccess
    readSettingsFile

    log_verbose "Scanning for external disks"
    ExternalDisks=$(diskutil list external physical | grep "/dev/disk" | awk '{print $1}')

    if [[ -z $ExternalDisks ]]; then
        log_info "No external disks mounted"
        exit 0
    fi

    diskCount=$(echo "$ExternalDisks" | wc -l | tr -d ' ')
    log_info "Found $diskCount external disk(s)"

    # Array to store unencrypted volumes for processing
    declare -a UNENCRYPTED_QUEUE=()

    log_info "========================================="
    log_info "Phase 1: Scanning for unencrypted volumes"
    log_info "========================================="

    # PHASE 1: Discovery - scan all drives and build queue
    while IFS= read -r DiskID; do
        [[ -z "$DiskID" ]] && continue

        log_verbose "Scanning disk: $DiskID"

        StorageInfo=$(diskutil list "$DiskID")
        log_debug "Storage info for $DiskID:\n$StorageInfo"

        # Track if we found any partitions on this disk
        foundPartitions=false

        # Check for APFS containers (can coexist with other partition types)
        if [[ $StorageInfo =~ "Apple_APFS" ]]; then
            log_verbose "Detected APFS partition(s) on $DiskID"

            ContainerDiskID=$(echo "$StorageInfo" | grep -o 'Container disk[0-9]*' | awk '{print $2}')

            if [[ -n "$ContainerDiskID" ]]; then
                log_verbose "Container Disk ID: $ContainerDiskID"

                # Get full APFS container info
                apfsInfo=$(diskutil apfs list "$ContainerDiskID" 2>&1)

                # Extract all volumes in this container
                volumeList=$(echo "$apfsInfo" | grep -E "^\s+\+-> Volume" | awk '{print $3}')

                if [[ -n "$volumeList" ]]; then
                    log_verbose "Found volumes in $ContainerDiskID: $(echo $volumeList | tr '\n' ' ')"

                    # Process each volume in the container
                    volumeProcessed=false
                    while IFS= read -r VolumeID; do
                        [[ -z "$VolumeID" ]] && continue

                        log_verbose "Checking volume: $VolumeID"

                        # Get detailed info for this specific volume
                        # Use grep with context to get 10 lines after the volume marker
                        volumeInfo=$(echo "$apfsInfo" | grep -A 10 "+-> Volume $VolumeID ")

                        # Check FileVault status for this volume
                        volumeFileVaultLine=$(echo "$volumeInfo" | grep "FileVault:" | sed 's/.*FileVault:[[:space:]]*//')
                        volumeName=$(echo "$volumeInfo" | grep "Name:" | sed 's/.*Name:[[:space:]]*//' | sed 's/ (Case.*$//')

                        log_verbose "Volume $VolumeID ($volumeName): FileVault=$volumeFileVaultLine"

                        # Check if this volume is locked
                        if echo "$volumeFileVaultLine" | grep -q "Locked"; then
                            log_info "Volume $VolumeID ($volumeName) is encrypted and locked, skipping"
                            continue
                        fi

                        # Check if this volume is already encrypted (Yes or Yes (Unlocked))
                        if echo "$volumeFileVaultLine" | grep -q "^Yes"; then
                            log_info "Volume $VolumeID ($volumeName) is already encrypted, skipping"
                            continue
                        fi

                        # Check if volume is mounted read-only
                        volumeMountInfo=$(diskutil info "$VolumeID" 2>/dev/null | grep "Volume Read-Only:" | sed 's/.*Volume Read-Only:[[:space:]]*//')
                        if [[ "$volumeMountInfo" =~ ^Yes ]]; then
                            log_info "Volume $VolumeID ($volumeName) is mounted read-only, skipping"
                            continue
                        fi

                        # Check if volume is not mounted at all
                        volumeMounted=$(diskutil info "$VolumeID" 2>/dev/null | grep "Mounted:" | sed 's/.*Mounted:[[:space:]]*//')
                        if [[ "$volumeMounted" == "No" ]]; then
                            log_info "Volume $VolumeID ($volumeName) is not mounted, skipping"
                            continue
                        fi

                        # Found an unencrypted volume (FileVault: No)
                        if [[ "$volumeFileVaultLine" == "No" ]]; then
                            log_info "Found unencrypted APFS volume: $VolumeID ($volumeName)"
                            UNENCRYPTED_QUEUE+=("APFS|$ContainerDiskID|$VolumeID|$volumeName")
                            volumeProcessed=true
                            foundPartitions=true
                        fi

                    done <<< "$volumeList"

                    if [[ "$volumeProcessed" == false ]]; then
                        log_verbose "All volumes in $ContainerDiskID are already encrypted"
                    fi
                else
                    log_warn "No volumes found in container $ContainerDiskID"
                fi
            else
                log_warn "Could not determine APFS container for $DiskID"
            fi
        fi

        # Check for HFS+ partitions (can coexist with APFS)
        if [[ $StorageInfo =~ "Apple_HFS" ]]; then
            log_verbose "Detected HFS+ partition(s) on $DiskID"

            # Get all HFS+ partitions on this disk
            hfsPartitions=$(echo "$StorageInfo" | grep "Apple_HFS" | awk '{print $NF}')

            while IFS= read -r VolumeID; do
                [[ -z "$VolumeID" ]] && continue

                log_verbose "Checking HFS+ volume: $VolumeID"

                volumeName=$(diskutil info "$VolumeID" 2>/dev/null | grep "Volume Name:" | sed 's/.*Volume Name:[[:space:]]*//')
                if [[ -z "$volumeName" ]]; then
                    volumeName="ExternalDisk"
                fi
                log_verbose "Volume Name: '$volumeName'"

                # Check if volume is mounted read-only
                volumeMountInfo=$(diskutil info "$VolumeID" 2>/dev/null | grep "Volume Read-Only:" | sed 's/.*Volume Read-Only:[[:space:]]*//')
                if [[ "$volumeMountInfo" =~ ^Yes ]]; then
                    log_info "Volume $VolumeID ($volumeName) is mounted read-only, skipping"
                    continue
                fi

                # Check if volume is not mounted at all
                volumeMounted=$(diskutil info "$VolumeID" 2>/dev/null | grep "Mounted:" | sed 's/.*Mounted:[[:space:]]*//')
                if [[ "$volumeMounted" == "No" ]]; then
                    log_info "Volume $VolumeID ($volumeName) is not mounted, skipping"
                    continue
                fi

                log_info "Found unencrypted HFS+ volume: $VolumeID ($volumeName)"
                UNENCRYPTED_QUEUE+=("HFS|$DiskID|$VolumeID|$volumeName")
                foundPartitions=true

            done <<< "$hfsPartitions"
        fi

        # Check for ExFAT/FAT/NTFS partitions (can coexist with other types)
        if [[ $StorageInfo =~ "Microsoft Basic Data" ]] || [[ $StorageInfo =~ "Windows_FAT" ]] || [[ $StorageInfo =~ "DOS_FAT" ]] || [[ $StorageInfo =~ "Windows_NTFS" ]]; then
            log_verbose "Detected ExFAT/FAT/NTFS partition(s) on $DiskID"

            # Get all ExFAT/FAT/NTFS partitions on this disk
            fatPartitions=$(echo "$StorageInfo" | grep -E "(Microsoft Basic Data|Windows_FAT|DOS_FAT|Windows_NTFS)" | awk '{print $NF}')

            while IFS= read -r VolumeID; do
                [[ -z "$VolumeID" ]] && continue

                log_verbose "Checking ExFAT/FAT/NTFS volume: $VolumeID"

                volumeName=$(diskutil info "$VolumeID" 2>/dev/null | grep "Volume Name:" | sed 's/.*Volume Name:[[:space:]]*//')
                if [[ -z "$volumeName" ]]; then
                    volumeName="ExternalDisk"
                fi
                log_verbose "Volume Name: '$volumeName'"

                # Check if volume is mounted read-only
                volumeMountInfo=$(diskutil info "$VolumeID" 2>/dev/null | grep "Volume Read-Only:" | sed 's/.*Volume Read-Only:[[:space:]]*//')
                if [[ "$volumeMountInfo" =~ ^Yes ]]; then
                    log_info "Volume $VolumeID ($volumeName) is mounted read-only, skipping"
                    continue
                fi

                # Check if volume is not mounted at all
                volumeMounted=$(diskutil info "$VolumeID" 2>/dev/null | grep "Mounted:" | sed 's/.*Mounted:[[:space:]]*//')
                if [[ "$volumeMounted" == "No" ]]; then
                    log_info "Volume $VolumeID ($volumeName) is not mounted, skipping"
                    continue
                fi

                log_info "Found unencrypted ExFAT/FAT/NTFS volume: $VolumeID ($volumeName)"
                UNENCRYPTED_QUEUE+=("ExFAT|$DiskID|$VolumeID|$volumeName")
                foundPartitions=true

            done <<< "$fatPartitions"
        fi

        if [[ "$foundPartitions" == false ]]; then
            log_warn "No supported unencrypted partitions found on $DiskID"
            log_debug "Storage info: $StorageInfo"
        fi

    done <<< "$ExternalDisks"

    # Report discovery results
    log_info "========================================="
    log_info "Discovery complete: Found ${#UNENCRYPTED_QUEUE[@]} unencrypted volume(s)"
    log_info "========================================="

    # Exit if no unencrypted volumes found
    if [[ ${#UNENCRYPTED_QUEUE[@]} -eq 0 ]]; then
        log_info "All external volumes are already encrypted"
        exit 0
    fi

    # Show what was found
    log_info "Unencrypted volumes found:"
    for entry in "${UNENCRYPTED_QUEUE[@]}"; do
        IFS='|' read -r volType diskID volumeID volName <<< "$entry"
        log_info "  - \"$volName\" ($volumeID) [$volType]"
    done

    # PHASE 2: Processing - encrypt each volume in the queue
    log_info "========================================="
    log_info "Phase 2: Processing unencrypted volumes"
    log_info "========================================="

    local queueIndex=0
    local queueTotal=${#UNENCRYPTED_QUEUE[@]}

    for entry in "${UNENCRYPTED_QUEUE[@]}"; do
        queueIndex=$((queueIndex + 1))
        IFS='|' read -r volType diskID volumeID volName <<< "$entry"

        log_info "========================================="
        log_info "Processing volume $queueIndex of $queueTotal"
        log_info "Volume: \"$volName\" ($volumeID) [$volType]"
        log_info "========================================="

        case "$volType" in
            APFS)
                processAPFSDisk "$diskID" "$volumeID" "$volName"
                ;;
            HFS)
                processHFSDisk "$diskID" "$volumeID" "$volName"
                ;;
            ExFAT)
                processExFATDisk "$diskID" "$volumeID" "$volName"
                ;;
        esac
    done

    log_info "========================================="
    log_info "All volumes processed"
    log_info "Script execution completed"
    log_info "========================================="

    # Show summary dialog if volumes were encrypted
    if [[ ${#ENCRYPTED_VOLUMES[@]} -gt 0 ]]; then
        show_encryption_summary
    fi
}

main
