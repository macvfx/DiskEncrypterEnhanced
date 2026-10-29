import Foundation
import Security

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let manager: ExceptionManager

    init(manager: ExceptionManager) {
        self.manager = manager
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let uid = connection.effectiveUserIdentifier
        guard geteuid() == 0,
              AdminEligibility.isUserAdmin(uid: uid),
              let username = AdminEligibility.username(uid: uid),
              CodeSignatureValidator.isTrustedApp(processIdentifier: connection.processIdentifier)
        else { return false }

        connection.exportedInterface = NSXPCInterface(with: DiskEncrypterAccessHelperXPC.self)
        connection.exportedObject = HelperEndpoint(
            manager: manager,
            caller: AuthenticatedCaller(uid: uid, username: username)
        )
        connection.resume()
        return true
    }
}

private final class HelperEndpoint: NSObject, DiskEncrypterAccessHelperXPC {
    private let manager: ExceptionManager
    private let caller: AuthenticatedCaller

    init(manager: ExceptionManager, caller: AuthenticatedCaller) {
        self.manager = manager
        self.caller = caller
    }

    func snapshot(reply: @escaping (Data?, String?) -> Void) {
        manager.snapshot { result in Self.reply(result, to: reply) }
    }

    func begin(requestData: Data, reply: @escaping (Data?, String?) -> Void) {
        do {
            let request = try Self.decoder.decode(ExceptionRequest.self, from: requestData)
            manager.begin(request: request, caller: caller) { result in Self.reply(result, to: reply) }
        } catch {
            reply(nil, "The exception request could not be decoded.")
        }
    }

    func revoke(requestID: String, reply: @escaping (Data?, String?) -> Void) {
        guard let id = UUID(uuidString: requestID) else {
            reply(nil, "The exception request identifier is invalid.")
            return
        }
        manager.revoke(requestID: id, caller: caller) { result in Self.reply(result, to: reply) }
    }

    private static func reply(
        _ result: Result<HelperSnapshot, Error>,
        to callback: @escaping (Data?, String?) -> Void
    ) {
        switch result {
        case .success(let snapshot):
            do { callback(try encoder.encode(snapshot), nil) }
            catch { callback(nil, "The helper response could not be encoded.") }
        case .failure(let error):
            callback(nil, error.localizedDescription)
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

enum CodeSignatureValidator {
    static func isTrustedApp(processIdentifier: pid_t) -> Bool {
        guard let helperInfo = signingInformation(for: nil),
              let helperTeam = helperInfo[kSecCodeInfoTeamIdentifier as String] as? String,
              !helperTeam.isEmpty,
              let guest = guestCode(processIdentifier: processIdentifier),
              SecCodeCheckValidity(guest, SecCSFlags(rawValue: 1 << 4), nil) == errSecSuccess,
              let guestInfo = signingInformation(for: guest),
              guestInfo[kSecCodeInfoIdentifier as String] as? String == HelperConstants.appBundleIdentifier,
              guestInfo[kSecCodeInfoTeamIdentifier as String] as? String == helperTeam
        else { return false }
        return true
    }

    private static func guestCode(processIdentifier: pid_t) -> SecCode? {
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: processIdentifier)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else { return nil }
        return code
    }

    private static func signingInformation(for code: SecCode?) -> [String: Any]? {
        var dynamicCode = code
        if dynamicCode == nil {
            var selfCode: SecCode?
            guard SecCodeCopySelf([], &selfCode) == errSecSuccess else { return nil }
            dynamicCode = selfCode
        }
        guard let dynamicCode else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: 1 << 1),
            &information
        ) == errSecSuccess else {
            return nil
        }
        return information as? [String: Any]
    }
}
