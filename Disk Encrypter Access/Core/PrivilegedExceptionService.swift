import Foundation

enum HelperStatus: Equatable, Sendable {
    case notInstalled
    case unavailable(String)
    case ready
}

protocol PrivilegedExceptionServicing: Sendable {
    func status() async -> HelperStatus
    func begin(_ request: ExceptionRequest) async throws
    func revoke(requestID: UUID) async throws
}

/// Safe default used until the signed privileged helper and its caller validation are installed.
/// It deliberately performs no launchd or disk mutation.
struct DeferredPrivilegedExceptionService: PrivilegedExceptionServicing {
    func status() async -> HelperStatus { .notInstalled }

    func begin(_ request: ExceptionRequest) async throws {
        throw PrivilegedServiceError.notInstalled
    }

    func revoke(requestID: UUID) async throws {
        throw PrivilegedServiceError.notInstalled
    }
}

enum PrivilegedServiceError: LocalizedError {
    case notInstalled

    var errorDescription: String? {
        "The signed Disk Encrypter Access privileged helper is not installed."
    }
}
