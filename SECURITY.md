# Security policy

DiskEncrypter and Disk Encrypter Access enforce disk-write restrictions and include privileged macOS components. Please avoid publishing exploitable details before a fix is available.

## Supported versions

Security fixes are provided for the latest published DiskEncrypter installer and Disk Encrypter Access app releases:

| Component | Supported release |
|---|---|
| DiskEncrypter | 2.4.6 |
| Disk Encrypter Access | 0.1.0 |

Older releases may be evaluated when a report also affects the current release, but they are not independently supported.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/macvfx/DiskEncrypterEnhanced/security/advisories/new) when it is available. Include:

- the affected component, version, build, and macOS version;
- clear reproduction steps using a disposable test disk;
- the expected and observed security boundary;
- relevant sanitized logs or crash information; and
- whether the issue can bypass administrator, signature, UUID, expiry, ownership, or permission checks.

Do not include credentials, operator-entered exception reasons, real volume names, customer data, or the contents of protected audit logs. Replace private identifiers with fictional values.

If private reporting is unavailable, open a public issue requesting a private contact channel without including vulnerability details.

## Safety

Do not test against the only copy of any data. Use a blank disposable external disk, keep valuable unencrypted media disconnected, and preserve the installed helper state and logs when reporting a failure. Do not manually launch the helper or alter protected exception state to reproduce an issue.
