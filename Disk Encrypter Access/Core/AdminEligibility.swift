import Darwin
import Foundation

enum AdminEligibility {
    static func currentUserIsAdmin() -> Bool {
        let username = NSUserName()
        guard let user = getpwnam(username), let admin = getgrnam("admin") else { return false }

        var count: Int32 = 0
        let primaryGroup = Int32(user.pointee.pw_gid)
        _ = getgrouplist(username, primaryGroup, nil, &count)
        guard count > 0 else { return false }

        var groups = [Int32](repeating: 0, count: Int(count))
        guard getgrouplist(username, primaryGroup, &groups, &count) >= 0 else { return false }
        return groups.prefix(Int(count)).contains(Int32(admin.pointee.gr_gid))
    }
}
