import Foundation

enum HelperConstants {
    static let machServiceName = "com.macvfx.DiskEncrypterAccess.Helper"
    static let daemonPlistName = "com.macvfx.DiskEncrypterAccess.Helper.plist"
    static let appBundleIdentifier = "com.macvfx.DiskEncrypterAccess"
    static let minimumReasonLength = 10
    static let maximumDurationMinutes = 60
}

@objc protocol DiskEncrypterAccessHelperXPC {
    func snapshot(reply: @escaping (Data?, String?) -> Void)
    func begin(requestData: Data, reply: @escaping (Data?, String?) -> Void)
    func revoke(requestID: String, reply: @escaping (Data?, String?) -> Void)
}
