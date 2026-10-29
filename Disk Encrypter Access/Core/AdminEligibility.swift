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

        guard let groups = supplementaryGroupIDs(
            username: username,
            primaryGroup: user.pointee.pw_gid
        ) else { return false }
        return containsAdminGroup(groups, adminGroupID: admin.pointee.gr_gid)
    }

    static func containsAdminGroup(_ groups: [gid_t], adminGroupID: gid_t) -> Bool {
        groups.contains(adminGroupID)
    }

    private static func supplementaryGroupIDs(
        username: String,
        primaryGroup: gid_t
    ) -> [gid_t]? {
        // On macOS, calling getgrouplist with a nil, zero-sized buffer can
        // succeed with a count of zero. Start with storage and grow it until
        // Directory Services can return the complete membership list.
        var capacity = 32
        while capacity <= 4096 {
            var count = Int32(capacity)
            var groups = [Int32](repeating: 0, count: capacity)
            if getgrouplist(username, Int32(primaryGroup), &groups, &count) >= 0 {
                return groups.prefix(Int(count)).map(gid_t.init)
            }
            capacity = max(capacity * 2, Int(count))
        }
        return nil
    }
}
