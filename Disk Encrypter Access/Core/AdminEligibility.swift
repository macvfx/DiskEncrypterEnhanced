import Darwin
import Foundation

enum AdminEligibility {
    static func currentUserIsAdmin() -> Bool {
        isUserAdmin(uid: getuid())
    }

    static func username(uid: uid_t) -> String? {
        guard let user = getpwuid(uid), let name = user.pointee.pw_name else { return nil }
        return String(cString: name)
    }

    static func isUserAdmin(uid: uid_t) -> Bool {
        if uid == 0 { return true }
        guard let username = username(uid: uid),
              let user = getpwuid(uid),
              let admin = getgrnam("admin") else { return false }

        var count: Int32 = 0
        let primaryGroup = Int32(user.pointee.pw_gid)
        _ = getgrouplist(username, primaryGroup, nil, &count)
        guard count > 0 else { return false }

        var groups = [Int32](repeating: 0, count: Int(count))
        guard getgrouplist(username, primaryGroup, &groups, &count) >= 0 else { return false }
        return groups.prefix(Int(count)).contains(Int32(admin.pointee.gr_gid))
    }
}
