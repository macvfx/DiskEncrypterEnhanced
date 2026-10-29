import XCTest
@testable import Disk_Encrypter_Access

final class DiskEncrypterAccessTests: XCTestCase {
    func testAdminGroupMatchingUsesSupplementaryGroups() {
        XCTAssertTrue(AdminEligibility.containsAdminGroup([20, 80, 204], adminGroupID: 80))
        XCTAssertFalse(AdminEligibility.containsAdminGroup([20, 61, 204], adminGroupID: 80))
    }

    func testServiceManagementPermissionErrorRequiresApproval() {
        let error = NSError(
            domain: "SMAppServiceErrorDomain",
            code: Int(EPERM),
            userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"]
        )

        guard case .approvalRequired = XPCPrivilegedExceptionService.registrationError(from: error) else {
            return XCTFail("Service Management permission errors must enter the approval flow.")
        }
    }

    func testRegistrationFailureIncludesDomainAndCode() {
        let error = NSError(
            domain: "ExampleRegistrationDomain",
            code: 108,
            userInfo: [NSLocalizedDescriptionKey: "Unable to read plist"]
        )

        guard case .registrationFailed(let detail) = XPCPrivilegedExceptionService.registrationError(from: error) else {
            return XCTFail("Unexpected registration error mapping.")
        }
        XCTAssertTrue(detail.contains("ExampleRegistrationDomain code 108"))
    }

    func testParsesMountedUnencryptedExternalVolume() throws {
        let info: [String: Any] = [
            "Internal": false,
            "WholeDisk": false,
            "BusProtocol": "USB",
            "MountPoint": "/Volumes/Example_Media",
            "VolumeName": "Example Media",
            "VolumeUUID": "11111111-2222-3333-4444-555555555555",
            "FilesystemName": "ExFAT",
            "ParentWholeDisk": "disk8",
            "TotalSize": 64_000_000_000 as NSNumber,
            "Writable": false,
        ]

        let volume = try XCTUnwrap(DiskutilVolumeDiscovery.parseVolumeInfo(info, identifier: "disk8s1"))
        XCTAssertEqual(volume.name, "Example Media")
        XCTAssertEqual(volume.parentWholeDisk, "disk8")
        XCTAssertTrue(volume.isReadOnly)
        XCTAssertTrue(volume.isEligible)
    }

    func testRejectsEncryptedAndDiskImageVolumes() {
        let base: [String: Any] = [
            "Internal": false,
            "WholeDisk": false,
            "MountPoint": "/Volumes/Example_Archive",
            "VolumeName": "Example Archive",
            "VolumeUUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "FilesystemName": "APFS",
            "Writable": true,
        ]

        var encrypted = base
        encrypted["BusProtocol"] = "USB"
        encrypted["FileVault"] = true
        XCTAssertNil(DiskutilVolumeDiscovery.parseVolumeInfo(encrypted, identifier: "disk9s1"))

        var image = base
        image["BusProtocol"] = "Disk Image"
        XCTAssertNil(DiskutilVolumeDiscovery.parseVolumeInfo(image, identifier: "disk10s1"))
    }

    func testRequestRequiresAndTrimsAuditNote() throws {
        let volume = ExternalVolume(
            bsdName: "disk8s1",
            parentWholeDisk: "disk8",
            name: "Example Media",
            volumeUUID: "11111111-2222-3333-4444-555555555555",
            fileSystem: "ExFAT",
            mountPoint: "/Volumes/Example_Media",
            size: 64_000_000_000,
            isReadOnly: true
        )
        let request = try ExceptionRequest(
            volume: volume,
            duration: .fifteenMinutes,
            note: "  Export approved deliverables  "
        )

        XCTAssertEqual(request.note, "Export approved deliverables")
        XCTAssertEqual(request.durationMinutes, 15)
        XCTAssertThrowsError(try ExceptionRequest(volume: volume, duration: .fiveMinutes, note: ""))
    }

    func testProtectedStateAndAuditRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskEncrypterAccessTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ExceptionStoragePaths(
            stateURL: root.appendingPathComponent("state/active-exception.plist"),
            auditURL: root.appendingPathComponent("logs/exceptions.jsonl")
        )
        let store = ProtectedExceptionStore(paths: paths)
        let audit = ProtectedAuditLog(paths: paths)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let active = ActiveException(
            requestID: UUID(),
            volumeUUID: "11111111-2222-3333-4444-555555555555",
            bsdName: "disk8s1",
            volumeName: "Example Media",
            fileSystem: "ExFAT",
            note: "Export approved deliverables",
            requestedBy: "example-admin",
            requestingUID: 501,
            startedAt: started,
            expiresAt: started.addingTimeInterval(900),
            expiresAtEpoch: 1_700_000_900,
            status: .active,
            retryCount: 0,
            lastRetryAt: nil,
            lastError: nil
        )

        try store.write(active)
        XCTAssertEqual(try store.read(), active)
        let stateMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: paths.stateURL.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(stateMode, 0o600)

        try audit.append(ExceptionAuditEvent(
            eventID: UUID(),
            requestID: active.requestID,
            timestamp: started,
            action: .granted,
            volumeUUID: active.volumeUUID,
            volumeName: active.volumeName,
            requestedBy: active.requestedBy,
            requestingUID: active.requestingUID,
            note: active.note,
            detail: "Selected volume remounted writable."
        ))
        let lines = try String(contentsOf: paths.auditURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("\"action\":\"granted\""))
        let auditMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: paths.auditURL.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(auditMode, 0o600)
    }
}
