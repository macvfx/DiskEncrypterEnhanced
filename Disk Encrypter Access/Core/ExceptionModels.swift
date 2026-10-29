import Foundation

enum ExceptionDuration: Int, CaseIterable, Codable, Identifiable, Sendable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case sixtyMinutes = 60

    var id: Int { rawValue }
    var title: String { rawValue == 60 ? "1 hour" : "\(rawValue) min" }
    var interval: TimeInterval { TimeInterval(rawValue * 60) }
}

struct ExceptionRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let volumeUUID: String
    let bsdName: String
    let volumeName: String
    let fileSystem: String
    let note: String
    let requestedBy: String
    let requestedAt: Date
    let expiresAt: Date

    init(volume: ExternalVolume, duration: ExceptionDuration, note: String, now: Date = Date(), user: String = NSUserName()) throws {
        guard let volumeUUID = volume.volumeUUID else { throw ExceptionValidationError.missingStableIdentifier }
        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ExceptionValidationError.missingNote }
        guard cleaned.count <= 500 else { throw ExceptionValidationError.noteTooLong }

        requestID = UUID()
        self.volumeUUID = volumeUUID
        bsdName = volume.bsdName
        volumeName = volume.name
        fileSystem = volume.fileSystem
        self.note = cleaned
        requestedBy = user
        requestedAt = now
        expiresAt = now.addingTimeInterval(duration.interval)
    }
}

enum ExceptionValidationError: LocalizedError {
    case missingStableIdentifier
    case missingNote
    case noteTooLong

    var errorDescription: String? {
        switch self {
        case .missingStableIdentifier: "The selected volume has no stable UUID and cannot receive an exception."
        case .missingNote: "Enter a reason for the exception."
        case .noteTooLong: "Keep the reason to 500 characters or fewer."
        }
    }
}

enum ExceptionAuditAction: String, Codable, Sendable {
    case requested
    case granted
    case revoked
    case expired
    case expirationPending
    case denied
    case failed
}

struct ExceptionAuditEvent: Codable, Sendable {
    let eventID: UUID
    let requestID: UUID
    let timestamp: Date
    let action: ExceptionAuditAction
    let volumeUUID: String
    let volumeName: String
    let requestedBy: String
    let note: String
    let detail: String
}
