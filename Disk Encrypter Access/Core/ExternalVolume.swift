import Foundation

struct ExternalVolume: Identifiable, Hashable, Codable, Sendable {
    let bsdName: String
    let parentWholeDisk: String
    let name: String
    let volumeUUID: String?
    let fileSystem: String
    let mountPoint: String
    let size: Int64
    let isReadOnly: Bool

    var id: String { volumeUUID ?? bsdName }
    var isEligible: Bool { volumeUUID != nil }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
