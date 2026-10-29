import XCTest
@testable import Disk_Encrypter_Access

final class DiskEncrypterAccessTests: XCTestCase {
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
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = try ExceptionRequest(
            volume: volume,
            duration: .fifteenMinutes,
            note: "  Export approved deliverables  ",
            now: now,
            user: "example-admin"
        )

        XCTAssertEqual(request.note, "Export approved deliverables")
        XCTAssertEqual(request.expiresAt.timeIntervalSince(now), 900)
        XCTAssertThrowsError(try ExceptionRequest(volume: volume, duration: .fiveMinutes, note: ""))
    }
}
