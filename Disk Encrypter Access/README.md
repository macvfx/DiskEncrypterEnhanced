# Disk Encrypter Access

Disk Encrypter Access is a small SwiftUI macOS administrator tool for granting one audited, time-limited writing exception to one unencrypted external volume. DiskEncrypter remains active for every other disk.

## Current implementation

- Discovers mounted unencrypted external volumes using structured `diskutil` property lists.
- Identifies an exception target by stable Volume UUID rather than a changing BSD disk identifier.
- Requires a local administrator account, one selected disk, an approved duration, and a written reason.
- Bundles a root LaunchDaemon registered through `SMAppService.daemon`.
- Accepts XPC clients only when the running app has the expected bundle identifier, a valid signature, and the same Team ID as the helper.
- Stores active state at `/var/db/DiskEncrypter/active-exception.plist` with root ownership and mode `0600`.
- Appends JSONL audit events to `/Library/Logs/DiskEncrypter/exceptions.jsonl` with root ownership and mode `0600`.
- Presents protected audit events as grouped exceptions in an administrator-only **Exception History** window without weakening log permissions.
- Restores read-only protection at expiry or early revocation. A busy disk becomes visibly `expirationPending`; the helper never force-unmounts it and uses bounded rapid retries followed by five-minute retry intervals.
- Reconciles persisted state after helper restart, app exit, sleep/wake, or reboot.
- Includes standard macOS About and Help windows describing current controls, safety behavior, history, and troubleshooting.

The existing DiskEncrypter scripts consult the protected state and skip enforcement only when the mounted volume UUID matches an unexpired `activating` or `active` exception.

## Releases

Disk Encrypter Access has its own release track inside the DiskEncrypter Enhanced repository. App tags use `access-v<version>` so they remain distinct from DiskEncrypter installer tags.

The current app release is `access-v0.1.0` (build 8). Its DMG contains the optional app and bundled privileged helper; it does not install the main DiskEncrypter enforcement package. Install DiskEncrypter 2.4.6 or later first.

## Build and test

Generate the Xcode project after editing `project.yml`:

```bash
xcodegen generate
```

Run tests with an isolated DerivedData directory:

```bash
xcodebuild \
  -project DiskEncrypterAccess.xcodeproj \
  -scheme "Disk Encrypter Access" \
  -configuration Debug \
  -derivedDataPath Build \
  test CODE_SIGNING_ALLOWED=NO
```

The tests use fictional volume identities and a fake disk controller. They do not modify launchd or a real disk.

## Signed helper requirement

`SMAppService` requires a properly code-signed app, and a LaunchDaemon distributed this way must be notarized. Install the signed app in `/Applications`, select **Register Privileged Helper**, then approve it in **System Settings > General > Login Items & Extensions** if macOS requests approval.

An ad-hoc or unsigned development build can compile and run the non-privileged interface, but it is not accepted as live helper-registration proof. Live acceptance must separately verify registration, administrator rejection/approval, XPC caller validation, one disposable external volume, expiry, busy-volume recovery, sleep/wake, reboot, and audit ownership/content.

Use [Docs/TESTING.md](Docs/TESTING.md) for the two-Mac signed-build acceptance checklist, evidence requirements, and failure recovery procedure.

Security issues involving helper authorization, protected audit storage, exception expiry, or disk mutation should be reported privately according to the repository [security policy](../SECURITY.md).

## Future SimpleMDM reporting

The protected local audit log is canonical. A future adapter can publish a sanitized current-state or last-event value to a SimpleMDM custom attribute without embedding an API credential in the user-facing app. Sending the operator-entered reason must be separately configurable because it may contain private information.
