import Foundation
import XCTest

final class ExceptionManagerTests: XCTestCase {
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
