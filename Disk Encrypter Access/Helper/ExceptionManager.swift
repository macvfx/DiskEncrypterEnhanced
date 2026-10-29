import Darwin
import Foundation
import os

struct AuthenticatedCaller: Sendable {
    let uid: uid_t
    let username: String
}

final class ExceptionManager: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macvfx.DiskEncrypterAccess.Helper.state")
    private let store: ProtectedExceptionStore
    private let audit: ProtectedAuditLog
    private let disk: any DiskControlling
    private let now: @Sendable () -> Date
    private let requireRoot: Bool
    private var timer: DispatchSourceTimer?

    init(
        store: ProtectedExceptionStore = ProtectedExceptionStore(),
        audit: ProtectedAuditLog = ProtectedAuditLog(),
        disk: any DiskControlling = DiskMutationController(),
        now: @escaping @Sendable () -> Date = { Date() },
        requireRoot: Bool = true
    ) {
        self.store = store
        self.audit = audit
        self.disk = disk
        self.now = now
        self.requireRoot = requireRoot
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.reconcileExpiration(trigger: "helper startup")
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 5, repeating: 10)
            timer.setEventHandler { [weak self] in
                self?.reconcileExpiration(trigger: "expiry timer")
            }
            timer.resume()
            self.timer = timer
        }
    }

    func snapshot(reply: @escaping (Result<HelperSnapshot, Error>) -> Void) {
        queue.async {
            self.reconcileExpiration(trigger: "status request")
            reply(Result { try self.makeSnapshot() })
        }
    }

    func auditHistory(
        limit: Int,
        reply: @escaping (Result<[ExceptionAuditEvent], Error>) -> Void
    ) {
        queue.async {
            reply(Result { try self.audit.readRecent(limit: limit) })
        }
    }

    func begin(
        request: ExceptionRequest,
        caller: AuthenticatedCaller,
        reply: @escaping (Result<HelperSnapshot, Error>) -> Void
    ) {
        queue.async {
            reply(Result { try self.beginLocked(request: request, caller: caller) })
        }
    }

    func revoke(
        requestID: UUID,
        caller: AuthenticatedCaller,
        reply: @escaping (Result<HelperSnapshot, Error>) -> Void
    ) {
        queue.async {
            reply(Result { try self.revokeLocked(requestID: requestID, caller: caller) })
        }
    }

    func reconcile(reply: @escaping (Result<HelperSnapshot, Error>) -> Void) {
        queue.async {
            self.reconcileExpiration(trigger: "explicit reconciliation")
            reply(Result { try self.makeSnapshot() })
        }
    }

    private func beginLocked(request: ExceptionRequest, caller: AuthenticatedCaller) throws -> HelperSnapshot {
        guard !requireRoot || geteuid() == 0 else { throw ExceptionManagerError.helperNotRoot }
        reconcileExpiration(trigger: "new request")
        if let existing = try store.read() {
            throw ExceptionManagerError.exceptionAlreadyActive(existing.volumeName)
        }
        guard [5, 15, 30, 60].contains(request.durationMinutes),
              request.durationMinutes <= HelperConstants.maximumDurationMinutes else {
            throw ExceptionManagerError.invalidDuration
        }
        let cleanedNote = request.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedNote.count >= HelperConstants.minimumReasonLength,
              cleanedNote.count <= 500 else {
            throw ExceptionManagerError.invalidNote
        }
        guard let volume = try disk.resolve(volumeUUID: request.volumeUUID) else {
            throw ExceptionManagerError.volumeChanged
        }

        let started = now()
        let expires = started.addingTimeInterval(TimeInterval(request.durationMinutes * 60))
        var active = ActiveException(
            requestID: request.requestID,
            volumeUUID: request.volumeUUID.uppercased(),
            bsdName: volume.bsdName,
            volumeName: volume.name,
            fileSystem: volume.fileSystem,
            note: cleanedNote,
            requestedBy: caller.username,
            requestingUID: caller.uid,
            startedAt: started,
            expiresAt: expires,
            expiresAtEpoch: Int64(expires.timeIntervalSince1970),
            status: .activating,
            retryCount: 0,
            lastRetryAt: nil,
            lastError: nil,
            cameraMediaStructureDetected: CameraMediaDetector.detect(at: volume.mountPoint)
        )

        try appendAudit(.requested, active: active, detail: "Administrator requested a timed write exception.")
        try store.write(active)

        do {
            let mounted = try disk.remountWritable(volumeUUID: active.volumeUUID)
            active.bsdName = mounted.bsdName
            active.status = .active
            try store.write(active)
            try appendAudit(.granted, active: active, detail: "Selected volume remounted writable; other volumes remain protected.")
            return try makeSnapshot()
        } catch {
            try? store.remove()
            _ = try? disk.remountReadOnly(volumeUUID: active.volumeUUID)
            try? appendAudit(.failed, active: active, detail: error.localizedDescription)
            throw error
        }
    }

    private func revokeLocked(
        requestID: UUID,
        caller: AuthenticatedCaller
    ) throws -> HelperSnapshot {
        guard var active = try store.read() else { return try makeSnapshot() }
        guard active.requestID == requestID else { throw ExceptionManagerError.requestMismatch }

        do {
            switch try disk.remountReadOnly(volumeUUID: active.volumeUUID) {
            case .protected:
                try store.remove()
                try appendAudit(.revoked, active: active, detail: "Exception ended early by \(caller.username); volume remounted read-only.")
            case .disconnected:
                try store.remove()
                try appendAudit(.revoked, active: active, detail: "Exception ended early after the volume was disconnected.")
            }
        } catch {
            active.status = .expirationPending
            active.retryCount += 1
            active.lastRetryAt = now()
            active.lastError = error.localizedDescription
            try store.write(active)
            try appendAudit(.expirationPending, active: active, detail: "Early revocation pending: \(error.localizedDescription)")
        }
        return try makeSnapshot()
    }

    private func reconcileExpiration(trigger: String) {
        do {
            guard var active = try store.read(), now() >= active.expiresAt else { return }
            if active.status == .expirationPending, let lastRetryAt = active.lastRetryAt {
                let interval: TimeInterval = active.retryCount < 10 ? 30 : 300
                guard now().timeIntervalSince(lastRetryAt) >= interval else { return }
            }
            do {
                switch try disk.remountReadOnly(volumeUUID: active.volumeUUID) {
                case .protected:
                    try store.remove()
                    try appendAudit(.expired, active: active, detail: "Timed exception expired; volume remounted read-only (\(trigger)).")
                case .disconnected:
                    try store.remove()
                    try appendAudit(.expired, active: active, detail: "Timed exception expired while the volume was disconnected (\(trigger)).")
                }
            } catch {
                active.status = .expirationPending
                active.retryCount += 1
                active.lastRetryAt = now()
                active.lastError = error.localizedDescription
                try store.write(active)
                try appendAudit(
                    .expirationPending,
                    active: active,
                    detail: "Protection retry \(active.retryCount) pending: \(error.localizedDescription)"
                )
            }
        } catch {
            Logger(subsystem: HelperConstants.machServiceName, category: "expiry")
                .error("Could not reconcile exception state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeSnapshot() throws -> HelperSnapshot {
        HelperSnapshot(activeException: try store.read(), auditLogPath: store.paths.auditURL.path)
    }

    private func appendAudit(
        _ action: ExceptionAuditAction,
        active: ActiveException,
        detail: String
    ) throws {
        try audit.append(ExceptionAuditEvent(
            eventID: UUID(),
            requestID: active.requestID,
            timestamp: now(),
            action: action,
            volumeUUID: active.volumeUUID,
            volumeName: active.volumeName,
            bsdName: active.bsdName,
            fileSystem: active.fileSystem,
            durationMinutes: Int(active.expiresAt.timeIntervalSince(active.startedAt) / 60),
            expiresAt: active.expiresAt,
            cameraMediaStructureDetected: active.cameraMediaStructureDetected ?? false,
            requestedBy: active.requestedBy,
            requestingUID: active.requestingUID,
            note: active.note,
            detail: detail
        ))
    }
}

enum ExceptionManagerError: LocalizedError {
    case helperNotRoot
    case exceptionAlreadyActive(String)
    case invalidDuration
    case invalidNote
    case volumeChanged
    case requestMismatch

    var errorDescription: String? {
        switch self {
        case .helperNotRoot: "The privileged helper is not running as root."
        case .exceptionAlreadyActive(let name): "An exception is already active for \(name)."
        case .invalidDuration: "The requested duration is not permitted."
        case .invalidNote: "A reason between \(HelperConstants.minimumReasonLength) and 500 characters is required."
        case .volumeChanged: "The selected volume is disconnected or its stable identity changed."
        case .requestMismatch: "The exception request identifier does not match the active exception."
        }
    }
}
