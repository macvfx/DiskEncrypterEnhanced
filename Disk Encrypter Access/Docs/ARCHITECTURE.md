# Disk Encrypter Access architecture

## Product boundary

Disk Encrypter Access grants one administrator-approved, time-limited writing exception to one mounted unencrypted external volume. It must not unload DiskEncrypter globally. Every other volume remains protected.

The SwiftUI app is an unprivileged client. It discovers candidate volumes and constructs an exception request, but it cannot change mounts, launchd services, protected state, or audit files by itself.

## Privileged path

The production helper will:

1. Accept requests only from the correctly signed Disk Encrypter Access application.
2. obtain the requesting UID from the XPC connection and require membership in the local `admin` group;
3. resolve the selected disk again and match its stable Volume UUID, current BSD identifier, filesystem, external status, and writable media status;
4. reject missing notes, excessive durations, unstable identifiers, multiple concurrent exceptions, and changed or disconnected disks;
5. atomically write the active exception to a root-owned property list under `/var/db/DiskEncrypter/`;
6. append requested, granted, revoked, expired, pending, denied, and failed events to a root-owned JSONL log under `/Library/Logs/DiskEncrypter/`;
7. remount only the selected volume normally after the protected exception record exists; and
8. expire or revoke the exception even when the app is closed, asleep, relaunched, or rebooted.

DiskEncrypter will read only the root-owned active-exception property list and skip a volume only when its Volume UUID matches and the absolute expiration time is still in the future.

## Expiration safety

At expiration the helper attempts a clean unmount and read-only remount. It never force-unmounts a busy filesystem. If open files prevent the transition, the state becomes `expirationPending`, the event is logged, the user is notified, and bounded retries continue while the exception remains visibly unresolved.

If the disk is disconnected, the exception closes. A later reconnection has no exception and is handled normally by DiskEncrypter.

## Future SimpleMDM reporting

The local protected audit log is canonical. A later reporting adapter can expose a sanitized current-state or last-event value to a SimpleMDM custom attribute. API credentials must not be embedded in the user-facing app, and sending the operator note must be separately configurable because it can contain private information.
