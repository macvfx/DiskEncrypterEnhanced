# Disk Encrypter Access acceptance testing

Use this checklist to test a signed and notarized Disk Encrypter Access build on two Macs. Record each case as **Pass**, **Fail**, **Blocked**, or **Skipped**. A blocked or skipped required case is not a pass.

## Safety boundary

- Use only blank, disposable external disks. Never test with the only copy of any data.
- Disconnect valuable unencrypted external disks before a mutating test.
- Keep the main DiskEncrypter LaunchDaemon loaded. This app grants one UUID-specific exception; it does not intentionally unload global protection.
- Install Disk Encrypter Access in `/Applications`. Do not register its helper while running the app from the DMG.
- Do not launch the helper executable directly or manually bootstrap its bundled plist. `SMAppService` must register it so launchd supplies the root context and privileged Mach service.
- Do not manually remove `/var/db/DiskEncrypter/active-exception.plist` during a failed test. Eject the disposable disk and preserve the state for diagnosis.

## Current capability boundary

The app does not yet verify whether the main DiskEncrypter LaunchDaemon is loaded. The green protection notice is not a live status reading. Verify the daemon manually before each disk test.

Disconnect/reconnect is not yet production-safe. If an excepted disk disconnects before expiry, the current helper retains the exception until expiry. Do not reconnect it until the original expiry time has passed.

## Test record

Create one copy of this table per Mac.

| Field | Value |
| --- | --- |
| Tester | `<tester>` |
| Mac label | `TEST-MAC-A` or `TEST-MAC-B` |
| macOS version/build | |
| Mac architecture | |
| App version/build | |
| DMG SHA-256 | |
| DiskEncrypter label | |
| Disposable volume | `DEA-TEST-A` |
| Disposable volume UUID | |
| Test date | |

## 1. Artifact and installation preflight

1. Verify the supplied checksum:

   ```bash
   shasum -a 256 "Disk-Encrypter-Access-<version>-build-<build>.dmg"
   ```

2. Verify Gatekeeper accepts the DMG:

   ```bash
   spctl --assess --type open --context context:primary-signature --verbose=4 \
     "Disk-Encrypter-Access-<version>-build-<build>.dmg"
   ```

3. Open the DMG, copy **Disk Encrypter Access.app** to `/Applications`, eject the DMG, and launch the installed copy.
4. Verify the installed app and its embedded components:

   ```bash
   APP="/Applications/Disk Encrypter Access.app"

   codesign --verify --deep --strict --verbose=4 "$APP"
   spctl --assess --type execute --verbose=4 "$APP"
   ls -l "$APP/Contents/Library/LaunchDaemons/com.macvfx.DiskEncrypterAccess.Helper.plist"
   ls -l "$APP/Contents/Library/LaunchServices/com.macvfx.DiskEncrypterAccess.Helper"
   plutil -lint "$APP/Contents/Library/LaunchDaemons/com.macvfx.DiskEncrypterAccess.Helper.plist"
   ```

Expected:

- Gatekeeper reports `source=Notarized Developer ID`.
- Strict signature verification succeeds.
- Both embedded helper files exist.
- The LaunchDaemon plist passes `plutil` validation.

## 2. Main DiskEncrypter preflight

Identify the installed label and verify that one main daemon is loaded:

```bash
sudo launchctl list | grep diskencrypter
```

Expected main label:

- Package installation: `com.custom.diskencrypter`
- Script installation: `com.custom.diskencrypter.volumewatcher`

Verify that the installed script understands protected UUID exceptions:

```bash
sudo grep -n "active-exception.plist" \
  "/Library/Application Support/Custom/DiskEncrypter_Enhanced.sh"
```

Do not continue if the main daemon is absent or the installed script does not contain the exception-state check.

## 3. Administrator detection

Launch the installed app from an administrator account.

Expected:

- The footer says **Administrator account**.
- It does not show **Administrator account required**.

Record the system evidence without including personal account names in a shared report:

```bash
id -Gn | tr ' ' '\n' | grep '^admin$'
```

## 4. Privileged-helper registration

Before registration, both of these are expected to be absent:

```bash
sudo launchctl print system/com.macvfx.DiskEncrypterAccess.Helper
sudo test ! -e /var/db/DiskEncrypter/active-exception.plist \
  && echo "No active exception state (expected)"
```

The state plist is not installed with the app. The root helper creates it only after a valid exception request has been accepted.

1. Select **Register Privileged Helper**.
2. The first registration may return `Operation not permitted` while macOS creates a pending background item. The app must treat this as **Requires Approval**, not as a fatal registration error, and open **System Settings > General > Login Items & Extensions**.
3. Approve Disk Encrypter Access in System Settings.
4. Return to the app and allow up to five seconds for status refresh.
5. Verify the registered service:

   ```bash
   sudo launchctl print system/com.macvfx.DiskEncrypterAccess.Helper
   ```

Expected:

- The app says the signed helper is approved.
- `launchctl print` returns the helper job.
- `/var/db/DiskEncrypter/active-exception.plist` is still absent because no exception is active.

If registration fails, stop disk testing and capture:

```bash
log show --last 10m --style compact \
  --predicate 'subsystem == "com.apple.ServiceManagement" OR eventMessage CONTAINS[c] "DiskEncrypterAccess"'
sudo tail -n 50 /var/log/diskencrypter-access-helper-error.log
```

Also record the complete error shown by the app.

## 5. Protected baseline

Use a blank unencrypted external volume named `DEA-TEST-A`.

1. Connect the disk and allow the main DiskEncrypter daemon to process it.
2. Inspect it:

   ```bash
   diskutil info "/Volumes/DEA-TEST-A"
   ```

3. Attempt a harmless write:

   ```bash
   touch "/Volumes/DEA-TEST-A/baseline-write-should-fail.txt"
   ```

Expected:

- The disk is external, has a stable Volume UUID, and is read-only.
- The write attempt fails.
- The app lists the volume as eligible and read-only.

## 6. Five-minute exception

1. Select `DEA-TEST-A`.
2. Select **5 minutes**.
3. Enter the fictional reason `QA test - disposable volume`.
4. Select **Start Timed Exception**.

Expected:

- The selected volume unmounts and remounts writable.
- The app shows **Writing exception active** and a countdown.
- The main DiskEncrypter daemon remains loaded.
- Other volumes receive no exception.

Verify the selected disk:

```bash
touch "/Volumes/DEA-TEST-A/exception-write-succeeded.txt"
diskutil info "/Volumes/DEA-TEST-A"
```

Verify protected state and audit evidence:

```bash
sudo stat -f '%Su:%Sg %OLp %N' \
  /var/db/DiskEncrypter/active-exception.plist \
  /Library/Logs/DiskEncrypter/exceptions.jsonl
sudo plutil -p /var/db/DiskEncrypter/active-exception.plist
sudo tail -n 10 /Library/Logs/DiskEncrypter/exceptions.jsonl
```

Expected:

- State and audit files are owned by `root:wheel` with mode `600`.
- The state UUID matches `DEA-TEST-A`.
- Audit events include `requested` and `granted`.

## 7. Early revocation

During an active exception, select **End Now**.

Expected:

- The disk remounts read-only.
- The active card disappears.
- The active state plist is removed.
- The audit log contains `revoked`.
- A subsequent `touch` fails.

## 8. Automatic expiry with the app closed

1. Start another five-minute exception.
2. Confirm one write succeeds.
3. Quit Disk Encrypter Access completely.
4. Wait beyond the displayed expiry time.
5. Verify:

   ```bash
   diskutil info "/Volumes/DEA-TEST-A"
   sudo test ! -e /var/db/DiskEncrypter/active-exception.plist \
     && echo "Exception state cleared"
   sudo tail -n 10 /Library/Logs/DiskEncrypter/exceptions.jsonl
   ```

Expected:

- The helper expires the exception without the app running.
- The volume is read-only.
- State is removed and audit contains `expired`.
- A subsequent write fails.

## 9. Two-volume isolation

Use two blank disposable volumes, `DEA-TEST-A` and `DEA-TEST-B`.

1. Confirm both begin read-only.
2. Grant an exception only to `DEA-TEST-A`.
3. Confirm writes succeed on `DEA-TEST-A`.
4. Confirm writes still fail on `DEA-TEST-B`.

This case is required before claiming that one-disk isolation works on a live Mac.

## 10. Busy-volume recovery

Run only after the basic cases pass.

1. Start a five-minute exception on the disposable disk.
2. Keep a test file open from another process so a clean unmount may be refused.
3. Select **End Now** or allow expiry.

Expected if the disk is busy:

- The app reports **Protection restoration pending**.
- The protected state remains present with status `expirationPending`.
- The audit contains `expirationPending`.
- The helper retries without force-unmounting the disk.
- After the file is closed, a later retry returns the volume to read-only and clears state.

## 11. Sleep, wake, and reboot

Run these as separate cases with a disposable disk:

- Sleep and wake during an active exception.
- Reboot during an active exception.

After wake or reboot, verify the absolute expiry remains unchanged and the helper eventually restores read-only protection. Record the active-state plist and audit evidence before and after the transition.

## 12. Standard-user rejection

On a separate standard account:

- The app may inspect eligible volumes.
- The footer must state that an administrator account is required.
- The user must not be able to register the helper or begin an exception.
- A direct XPC request from a non-admin process must be rejected by the helper.

## Failure hold and recovery

If a volume remains writable unexpectedly:

1. Stop writing immediately.
2. Eject the disposable disk; do not reconnect it while an exception is unexpired.
3. Preserve these diagnostics:

   ```bash
   sudo launchctl print system/com.macvfx.DiskEncrypterAccess.Helper
   sudo plutil -p /var/db/DiskEncrypter/active-exception.plist
   sudo tail -n 30 /Library/Logs/DiskEncrypter/exceptions.jsonl
   sudo tail -n 50 /var/log/diskencrypter-access-helper.log
   sudo tail -n 50 /var/log/diskencrypter-access-helper-error.log
   sudo tail -n 50 /var/log/diskencrypter.log
   sudo tail -n 50 /var/log/diskencrypter_error.log
   ```

4. Mark the case failed and keep the evidence intact for diagnosis.

## Results matrix

| Case | TEST-MAC-A | TEST-MAC-B | Evidence or blocker |
| --- | --- | --- | --- |
| Artifact and Gatekeeper | | | |
| Embedded helper layout | | | |
| Main daemon and compatible script | | | |
| Administrator detection | | | |
| Helper registration and approval | | | |
| Protected baseline | | | |
| Five-minute exception | | | |
| Early revocation | | | |
| Automatic expiry with app closed | | | |
| Two-volume isolation | | | |
| Busy-volume recovery | | | |
| Sleep/wake | | | |
| Reboot | | | |
| Standard-user rejection | | | |

Do not mark the build accepted until all required cases have inspectable evidence. Helper registration, early revocation, automatic expiry, and one-volume isolation are release blockers.
