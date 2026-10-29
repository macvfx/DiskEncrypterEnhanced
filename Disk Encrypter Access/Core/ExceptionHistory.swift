import Foundation

struct ExceptionHistoryRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let events: [ExceptionAuditEvent]

    var firstEvent: ExceptionAuditEvent { events[0] }
    var latestEvent: ExceptionAuditEvent { events[events.count - 1] }
    var startedAt: Date { firstEvent.timestamp }
    var lastUpdatedAt: Date { latestEvent.timestamp }
    var action: ExceptionAuditAction { latestEvent.action }
    var volumeName: String { firstEvent.volumeName }
    var volumeUUID: String { firstEvent.volumeUUID }
    var bsdName: String { latestEvent.bsdName }
    var fileSystem: String { firstEvent.fileSystem }
    var durationMinutes: Int { firstEvent.durationMinutes }
    var expiresAt: Date { firstEvent.expiresAt }
    var requestedBy: String { firstEvent.requestedBy }
    var note: String { firstEvent.note }
    var cameraMediaStructureDetected: Bool { firstEvent.cameraMediaStructureDetected }

    static func records(from events: [ExceptionAuditEvent]) -> [ExceptionHistoryRecord] {
        Dictionary(grouping: events, by: \.requestID)
            .compactMap { requestID, groupedEvents in
                let sorted = groupedEvents.sorted { $0.timestamp < $1.timestamp }
                guard !sorted.isEmpty else { return nil }
                return ExceptionHistoryRecord(id: requestID, events: sorted)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
