import Foundation

enum VolumeDiscoveryError: LocalizedError {
    case commandFailed(String)
    case invalidPropertyList

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): message
        case .invalidPropertyList: "diskutil returned data that could not be read."
        }
    }
}

struct CommandOutput {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> CommandOutput
}

struct ProcessCommandRunner: CommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> CommandOutput {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return CommandOutput(
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

struct DiskutilVolumeDiscovery: Sendable {
    private let runner: any CommandRunning

    init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    func mountedUnencryptedExternalVolumes() async throws -> [ExternalVolume] {
        try await Task.detached(priority: .userInitiated) {
            try mountedUnencryptedExternalVolumesSync()
        }.value
    }

    func mountedUnencryptedExternalVolumesSync() throws -> [ExternalVolume] {
            let listing = try runner.run("/usr/sbin/diskutil", arguments: ["list", "-plist", "external"])
            guard listing.status == 0 else {
                throw VolumeDiscoveryError.commandFailed(Self.message(from: listing.stderr))
            }
            guard let root = try PropertyListSerialization.propertyList(
                from: listing.stdout,
                options: [],
                format: nil
            ) as? [String: Any],
                  let identifiers = root["AllDisks"] as? [String] else {
                throw VolumeDiscoveryError.invalidPropertyList
            }

            return try identifiers.compactMap { identifier in
                let output = try runner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", identifier])
                guard output.status == 0,
                      let info = try? PropertyListSerialization.propertyList(
                        from: output.stdout,
                        options: [],
                        format: nil
                      ) as? [String: Any]
                else { return nil }
                return Self.parseVolumeInfo(info, identifier: identifier)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parseVolumeInfo(_ info: [String: Any], identifier: String) -> ExternalVolume? {
        guard bool(info["Internal"]) == false,
              bool(info["WholeDisk"]) == false,
              (info["BusProtocol"] as? String) != "Disk Image",
              let mountPoint = info["MountPoint"] as? String,
              mountPoint.hasPrefix("/Volumes/"),
              let name = info["VolumeName"] as? String,
              !name.isEmpty,
              let fileSystem = (info["FilesystemName"] ?? info["FilesystemType"]) as? String,
              !isEncrypted(info)
        else { return nil }

        let uuid = nonempty(info["VolumeUUID"] as? String)
        let parent = (info["ParentWholeDisk"] as? String) ?? identifier
        let size = (info["TotalSize"] as? NSNumber)?.int64Value
            ?? (info["Size"] as? NSNumber)?.int64Value
            ?? 0
        let writable = bool(info["Writable"]) ?? true

        return ExternalVolume(
            bsdName: identifier,
            parentWholeDisk: parent,
            name: name,
            volumeUUID: uuid,
            fileSystem: fileSystem,
            mountPoint: mountPoint,
            size: size,
            isReadOnly: !writable
        )
    }

    private static func isEncrypted(_ info: [String: Any]) -> Bool {
        ["FileVault", "Encrypted", "Encryption"].contains { bool(info[$0]) == true }
    }

    private static func bool(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func message(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text! : "diskutil failed."
    }
}
