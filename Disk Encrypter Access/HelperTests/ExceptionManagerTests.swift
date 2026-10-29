import Foundation
import XCTest

final class ExceptionManagerTests: XCTestCase {
    func testHelperRejectsCraftedShortReason() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortReasonTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ExceptionStoragePaths(
            stateURL: root.appendingPathComponent("state/active-exception.plist"),
            auditURL: root.appendingPathComponent("logs/exceptions.jsonl")
        )
        let disk = FakeDiskController()
        let manager = ExceptionManager(
            store: ProtectedExceptionStore(paths: paths),
            audit: ProtectedAuditLog(paths: paths),
            disk: disk,
            requireRoot: false
        )
        let requestData = try JSONSerialization.data(withJSONObject: [
            "requestID": UUID().uuidString,
            "volumeUUID": try XCTUnwrap(disk.volume.volumeUUID),
            "bsdName": disk.volume.bsdName,
            "volumeName": disk.volume.name,
            "fileSystem": disk.volume.fileSystem,
            "note": "short",
            "durationMinutes": 5,
        ])
        let request = try JSONDecoder().decode(ExceptionRequest.self, from: requestData)
        let rejected = expectation(description: "short reason rejected")

        manager.begin(
            request: request,
            caller: AuthenticatedCaller(uid: 501, username: "example-admin")
        ) { result in
            switch result {
            case .success:
                XCTFail("The helper accepted a crafted short reason.")
            case .failure(let error):
                XCTAssertTrue(error.localizedDescription.contains("10"))
            }
            rejected.fulfill()
        }

        wait(for: [rejected], timeout: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.auditURL.path))
    }

    func testCameraMediaDetectorChecksOnlyKnownRootDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraMediaDetectorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        XCTAssertFalse(CameraMediaDetector.detect(at: root.path))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("DCIM", isDirectory: true),
            withIntermediateDirectories: false
        )
        XCTAssertTrue(CameraMediaDetector.detect(at: root.path))
    }

    func testDiskResolutionUsesDirectStableUUIDLookup() throws {
        let uuid = "11111111-2222-3333-4444-555555555555"
        let plist: [String: Any] = [
            "DeviceIdentifier": "disk8s1",
            "Internal": false,
            "WholeDisk": false,
            "BusProtocol": "USB",
            "MountPoint": "/Volumes/Example_Media",
            "VolumeName": "Example Media",
            "VolumeUUID": uuid,
            "FilesystemName": "ExFAT",
            "ParentWholeDisk": "disk8",
            "TotalSize": 64_000_000_000 as NSNumber,
            "Writable": false,
        ]
        let runner = RecordingDiskutilRunner(
            output: CommandOutput(
                status: 0,
                stdout: try PropertyListSerialization.data(
                    fromPropertyList: plist,
                    format: .xml,
                    options: 0
                ),
                stderr: Data()
            )
        )

        let resolved = try DiskMutationController(runner: runner).resolve(volumeUUID: uuid)

        XCTAssertEqual(resolved?.bsdName, "disk8s1")
        XCTAssertEqual(runner.requests, [["info", "-plist", uuid]])
    }

    func testGrantAndAutomaticExpiryRestoreReadOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskEncrypterAccessHelperTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ExceptionStoragePaths(
            stateURL: root.appendingPathComponent("state/active-exception.plist"),
            auditURL: root.appendingPathComponent("logs/exceptions.jsonl")
        )
        let store = ProtectedExceptionStore(paths: paths)
        let disk = FakeDiskController()
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let manager = ExceptionManager(
            store: store,
            audit: ProtectedAuditLog(paths: paths),
            disk: disk,
            now: { clock.date },
            requireRoot: false
        )
        let request = try ExceptionRequest(
            volume: disk.volume,
            duration: .fiveMinutes,
            note: "Export approved deliverables"
        )

        let granted = expectation(description: "granted")
        manager.begin(
            request: request,
            caller: AuthenticatedCaller(uid: 501, username: "example-admin")
        ) { result in
            XCTAssertEqual(try? result.get().activeException?.status, .active)
            granted.fulfill()
        }
        wait(for: [granted], timeout: 2)
        XCTAssertFalse(disk.volume.isReadOnly)
        XCTAssertNotNil(try store.read())

        clock.date = clock.date.addingTimeInterval(301)
        let expired = expectation(description: "expired")
        manager.reconcile { result in
            XCTAssertNil(try? result.get().activeException)
            expired.fulfill()
        }
        wait(for: [expired], timeout: 2)
        XCTAssertTrue(disk.volume.isReadOnly)
        XCTAssertNil(try store.read())

        let actions = try String(contentsOf: paths.auditURL, encoding: .utf8)
        XCTAssertTrue(actions.contains("\"action\":\"requested\""))
        XCTAssertTrue(actions.contains("\"action\":\"granted\""))
        XCTAssertTrue(actions.contains("\"action\":\"expired\""))
    }

    func testBusyDiskBecomesExpirationPendingWithoutLosingState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskEncrypterAccessHelperTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ExceptionStoragePaths(
            stateURL: root.appendingPathComponent("state/active-exception.plist"),
            auditURL: root.appendingPathComponent("logs/exceptions.jsonl")
        )
        let store = ProtectedExceptionStore(paths: paths)
        let disk = FakeDiskController()
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let manager = ExceptionManager(
            store: store,
            audit: ProtectedAuditLog(paths: paths),
            disk: disk,
            now: { clock.date },
            requireRoot: false
        )
        let request = try ExceptionRequest(
            volume: disk.volume,
            duration: .fiveMinutes,
            note: "Export approved deliverables"
        )

        let granted = expectation(description: "granted")
        manager.begin(
            request: request,
            caller: AuthenticatedCaller(uid: 501, username: "example-admin")
        ) { _ in granted.fulfill() }
        wait(for: [granted], timeout: 2)

        disk.failReadOnly = true
        clock.date = clock.date.addingTimeInterval(301)
        let pending = expectation(description: "pending")
        manager.reconcile { result in
            let active = try? result.get().activeException
            XCTAssertEqual(active?.status, .expirationPending)
            XCTAssertEqual(active?.retryCount, 1)
            pending.fulfill()
        }
        wait(for: [pending], timeout: 2)
        XCTAssertFalse(disk.volume.isReadOnly)
        XCTAssertNotNil(try store.read())
        XCTAssertTrue(try String(contentsOf: paths.auditURL, encoding: .utf8)
            .contains("\"action\":\"expirationPending\""))
    }

    func testProtectedAuditHistoryReturnsMostRecentBoundedEvents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuditHistoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ExceptionStoragePaths(
            stateURL: root.appendingPathComponent("state/active-exception.plist"),
            auditURL: root.appendingPathComponent("logs/exceptions.jsonl")
        )
        let audit = ProtectedAuditLog(paths: paths)
        let requestID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        for (offset, action) in [ExceptionAuditAction.requested, .granted, .revoked].enumerated() {
            try audit.append(ExceptionAuditEvent(
                eventID: UUID(),
                requestID: requestID,
                timestamp: base.addingTimeInterval(TimeInterval(offset)),
                action: action,
                volumeUUID: "11111111-2222-3333-4444-555555555555",
                volumeName: "Example Media",
                bsdName: "disk8s1",
                fileSystem: "ExFAT",
                durationMinutes: 15,
                expiresAt: base.addingTimeInterval(900),
                cameraMediaStructureDetected: false,
                requestedBy: "example-admin",
                requestingUID: 501,
                note: "Export approved deliverables",
                detail: "Example audit detail."
            ))
        }

        let recent = try audit.readRecent(limit: 2)
        XCTAssertEqual(recent.map(\.action), [.granted, .revoked])
    }
}

private final class RecordingDiskutilRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let output: CommandOutput
    private var storedRequests: [[String]] = []

    init(output: CommandOutput) {
        self.output = output
    }

    var requests: [[String]] { lock.withLock { storedRequests } }

    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        XCTAssertEqual(executable, "/usr/sbin/diskutil")
        lock.withLock { storedRequests.append(arguments) }
        return output
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDate: Date

    init(_ date: Date) { storedDate = date }

    var date: Date {
        get { lock.withLock { storedDate } }
        set { lock.withLock { storedDate = newValue } }
    }
}

private final class FakeDiskController: DiskControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var storedVolume = ExternalVolume(
        bsdName: "disk8s1",
        parentWholeDisk: "disk8",
        name: "Example Media",
        volumeUUID: "11111111-2222-3333-4444-555555555555",
        fileSystem: "ExFAT",
        mountPoint: "/Volumes/Example_Media",
        size: 64_000_000_000,
        isReadOnly: true
    )
    private var shouldFailReadOnly = false

    var volume: ExternalVolume { lock.withLock { storedVolume } }
    var failReadOnly: Bool {
        get { lock.withLock { shouldFailReadOnly } }
        set { lock.withLock { shouldFailReadOnly = newValue } }
    }

    func resolve(volumeUUID: String) throws -> ExternalVolume? {
        volume.volumeUUID == volumeUUID ? volume : nil
    }

    func remountWritable(volumeUUID: String) throws -> ExternalVolume {
        lock.withLock {
            storedVolume = replacingReadOnly(false)
            return storedVolume
        }
    }

    func remountReadOnly(volumeUUID: String) throws -> DiskProtectionResult {
        try lock.withLock {
            if shouldFailReadOnly { throw FakeDiskError.busy }
            storedVolume = replacingReadOnly(true)
            return .protected(storedVolume)
        }
    }

    private func replacingReadOnly(_ readOnly: Bool) -> ExternalVolume {
        ExternalVolume(
            bsdName: storedVolume.bsdName,
            parentWholeDisk: storedVolume.parentWholeDisk,
            name: storedVolume.name,
            volumeUUID: storedVolume.volumeUUID,
            fileSystem: storedVolume.fileSystem,
            mountPoint: storedVolume.mountPoint,
            size: storedVolume.size,
            isReadOnly: readOnly
        )
    }
}

private enum FakeDiskError: LocalizedError {
    case busy
    var errorDescription: String? { "The example volume is busy." }
}
