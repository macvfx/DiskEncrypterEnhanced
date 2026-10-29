import Darwin
import Foundation
import ServiceManagement

enum HelperStatus: Equatable, Sendable {
    case notInstalled
    case requiresApproval
    case unavailable(String)
    case ready
}

protocol PrivilegedExceptionServicing: Sendable {
    func status() async -> HelperStatus
    func register() async throws
    func openApprovalSettings() async
    func snapshot() async throws -> HelperSnapshot
    func begin(_ request: ExceptionRequest) async throws -> HelperSnapshot
    func revoke(requestID: UUID) async throws -> HelperSnapshot
}

final class XPCPrivilegedExceptionService: PrivilegedExceptionServicing, @unchecked Sendable {
    private let daemon = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)

    func status() async -> HelperStatus {
        if let bundleError = bundledComponentError() {
            return .unavailable(bundleError)
        }
        return switch daemon.status {
        case .enabled: .ready
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notInstalled
        case .notFound:
            // Some systems report notFound before the embedded daemon has
            // ever been registered. The bundle was verified above, so allow
            // registration and surface the detailed error from register().
            .notInstalled
        @unknown default: .unavailable("The privileged helper returned an unknown status.")
        }
    }

    func register() async throws {
        if let bundleError = bundledComponentError() {
            throw PrivilegedServiceError.registrationFailed(bundleError)
        }
        do {
            try daemon.register()
        } catch {
            throw Self.registrationError(from: error as NSError)
        }
    }

    func openApprovalSettings() async {
        SMAppService.openSystemSettingsLoginItems()
    }

    func snapshot() async throws -> HelperSnapshot {
        try await call { proxy, reply in proxy.snapshot(reply: reply) }
    }

    func begin(_ request: ExceptionRequest) async throws -> HelperSnapshot {
        let data = try Self.encoder.encode(request)
        return try await call { proxy, reply in proxy.begin(requestData: data, reply: reply) }
    }

    func revoke(requestID: UUID) async throws -> HelperSnapshot {
        try await call { proxy, reply in proxy.revoke(requestID: requestID.uuidString, reply: reply) }
    }

    private func bundledComponentError() -> String? {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let plist = contents
            .appendingPathComponent("Library/LaunchDaemons", isDirectory: true)
            .appendingPathComponent(HelperConstants.daemonPlistName)
        let helper = contents
            .appendingPathComponent("Library/LaunchServices", isDirectory: true)
            .appendingPathComponent(HelperConstants.machServiceName)
        guard FileManager.default.fileExists(atPath: plist.path) else {
            return "The installed app is missing its bundled LaunchDaemon plist. Recopy the complete app to /Applications."
        }
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return "The installed app is missing its bundled privileged helper executable. Recopy the complete app to /Applications."
        }
        return nil
    }

    static func registrationError(from error: NSError) -> PrivilegedServiceError {
        let operationNotPermitted = error.code == Int(EPERM)
        let serviceManagementPermission = error.domain == "SMAppServiceErrorDomain"
            && operationNotPermitted
        let posixPermission = error.domain == NSPOSIXErrorDomain
            && operationNotPermitted
        if serviceManagementPermission || posixPermission {
            return .approvalRequired
        }
        return .registrationFailed(
            "\(error.localizedDescription) [\(error.domain) code \(error.code)]"
        )
    }

    private func call(
        _ operation: @escaping (DiskEncrypterAccessHelperXPC, @escaping (Data?, String?) -> Void) -> Void
    ) async throws -> HelperSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            let once = ReplyOnce<HelperSnapshot>(continuation)
            let connection = NSXPCConnection(
                machServiceName: HelperConstants.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: DiskEncrypterAccessHelperXPC.self)
            connection.invalidationHandler = {
                once.resume(.failure(PrivilegedServiceError.connectionLost))
            }
            connection.interruptionHandler = {
                once.resume(.failure(PrivilegedServiceError.connectionLost))
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                once.resume(.failure(PrivilegedServiceError.helperFailed(error.localizedDescription)))
                connection.invalidate()
            }) as? DiskEncrypterAccessHelperXPC else {
                once.resume(.failure(PrivilegedServiceError.connectionLost))
                connection.invalidate()
                return
            }

            operation(proxy) { data, message in
                defer { connection.invalidate() }
                if let message {
                    once.resume(.failure(PrivilegedServiceError.helperFailed(message)))
                    return
                }
                guard let data else {
                    once.resume(.failure(PrivilegedServiceError.invalidReply))
                    return
                }
                do {
                    once.resume(.success(try Self.decoder.decode(HelperSnapshot.self, from: data)))
                } catch {
                    once.resume(.failure(PrivilegedServiceError.invalidReply))
                }
            }
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private final class ReplyOnce<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Value, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

enum PrivilegedServiceError: LocalizedError {
    case approvalRequired
    case registrationFailed(String)
    case connectionLost
    case helperFailed(String)
    case invalidReply

    var errorDescription: String? {
        switch self {
        case .approvalRequired:
            "Administrator approval is required in System Settings > General > Login Items & Extensions."
        case .registrationFailed(let detail): "Could not register the privileged helper: \(detail)"
        case .connectionLost: "The privileged helper is not running or the connection was interrupted."
        case .helperFailed(let detail): detail
        case .invalidReply: "The privileged helper returned an invalid response."
        }
    }
}
