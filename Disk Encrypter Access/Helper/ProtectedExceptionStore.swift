import Darwin
import Foundation

struct ExceptionStoragePaths: Sendable {
    let stateURL: URL
    let auditURL: URL

    static let live = ExceptionStoragePaths(
        stateURL: URL(fileURLWithPath: "/var/db/DiskEncrypter/active-exception.plist"),
        auditURL: URL(fileURLWithPath: "/Library/Logs/DiskEncrypter/exceptions.jsonl")
    )
}

struct ProtectedExceptionStore: Sendable {
    let paths: ExceptionStoragePaths

    init(paths: ExceptionStoragePaths = .live) {
        self.paths = paths
    }

    func read() throws -> ActiveException? {
        guard FileManager.default.fileExists(atPath: paths.stateURL.path) else { return nil }
        return try PropertyListDecoder().decode(
            ActiveException.self,
            from: Data(contentsOf: paths.stateURL)
        )
    }

    func write(_ active: ActiveException) throws {
        try prepareDirectory(paths.stateURL.deletingLastPathComponent(), permissions: 0o700)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(active)
        let temporaryURL = paths.stateURL.deletingLastPathComponent()
            .appendingPathComponent(".active-exception-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard FileManager.default.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: protectedAttributes(permissions: 0o600)
        ) else {
            throw ProtectedStoreError.couldNotCreateState
        }
        try FileManager.default.setAttributes(
            protectedAttributes(permissions: 0o600),
            ofItemAtPath: temporaryURL.path
        )
        guard rename(temporaryURL.path, paths.stateURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: paths.stateURL.path) else { return }
        try FileManager.default.removeItem(at: paths.stateURL)
    }

    private func prepareDirectory(_ url: URL, permissions: NSNumber) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: permissions]
        )
        try FileManager.default.setAttributes(
            protectedAttributes(permissions: permissions),
            ofItemAtPath: url.path
        )
    }

    private func protectedAttributes(permissions: NSNumber) -> [FileAttributeKey: Any] {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: permissions]
        if geteuid() == 0 {
            attributes[.ownerAccountID] = 0
            attributes[.groupOwnerAccountID] = 0
        }
        return attributes
    }
}

enum ProtectedStoreError: LocalizedError {
    case couldNotCreateState
    var errorDescription: String? { "Could not create the protected active-exception state file." }
}

struct ProtectedAuditLog: Sendable {
    private static let maximumHistoryReadBytes: UInt64 = 2 * 1_024 * 1_024
    let paths: ExceptionStoragePaths

    init(paths: ExceptionStoragePaths = .live) {
        self.paths = paths
    }

    func append(_ event: ExceptionAuditEvent) throws {
        let directory = paths.auditURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o750]
        )
        try FileManager.default.setAttributes(
            protectedAttributes(permissions: 0o750),
            ofItemAtPath: directory.path
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(event)
        line.append(0x0A)

        if !FileManager.default.fileExists(atPath: paths.auditURL.path) {
            guard FileManager.default.createFile(
                atPath: paths.auditURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw AuditLogError.couldNotCreate
            }
        }

        let handle = try FileHandle(forWritingTo: paths.auditURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try FileManager.default.setAttributes(
            protectedAttributes(permissions: 0o600),
            ofItemAtPath: paths.auditURL.path
        )
    }

    func readRecent(limit: Int) throws -> [ExceptionAuditEvent] {
        let boundedLimit = min(max(limit, 1), 1_000)
        guard FileManager.default.fileExists(atPath: paths.auditURL.path) else { return [] }

        let handle = try FileHandle(forReadingFrom: paths.auditURL)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let start = size > Self.maximumHistoryReadBytes
            ? size - Self.maximumHistoryReadBytes
            : 0
        try handle.seek(toOffset: start)
        guard var data = try handle.readToEnd(), !data.isEmpty else { return [] }

        if start > 0, let firstNewline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex...firstNewline)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A, omittingEmptySubsequences: true)
            .suffix(boundedLimit)
            .compactMap { try? decoder.decode(ExceptionAuditEvent.self, from: Data($0)) }
    }

    private func protectedAttributes(permissions: NSNumber) -> [FileAttributeKey: Any] {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: permissions]
        if geteuid() == 0 {
            attributes[.ownerAccountID] = 0
            attributes[.groupOwnerAccountID] = 0
        }
        return attributes
    }
}

enum AuditLogError: LocalizedError {
    case couldNotCreate

    var errorDescription: String? { "Could not create the protected exception audit log." }
}
