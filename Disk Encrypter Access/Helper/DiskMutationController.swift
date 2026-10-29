import Foundation

enum DiskProtectionResult: Sendable {
    case protected(ExternalVolume)
    case disconnected
}

protocol DiskControlling: Sendable {
    func resolve(volumeUUID: String) throws -> ExternalVolume?
    func remountWritable(volumeUUID: String) throws -> ExternalVolume
    func remountReadOnly(volumeUUID: String) throws -> DiskProtectionResult
}

struct DiskMutationController: DiskControlling {
    private let runner: any CommandRunning
    private let discovery: DiskutilVolumeDiscovery

    init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
        discovery = DiskutilVolumeDiscovery(runner: runner)
    }

    func resolve(volumeUUID: String) throws -> ExternalVolume? {
        try discovery.mountedUnencryptedExternalVolumesSync().first {
            $0.volumeUUID?.caseInsensitiveCompare(volumeUUID) == .orderedSame
        }
    }

    func remountWritable(volumeUUID: String) throws -> ExternalVolume {
        guard let volume = try resolve(volumeUUID: volumeUUID) else {
            throw DiskMutationError.volumeNotFound
        }
        try runDiskutil(["unmount", volume.bsdName], operation: "unmount")
        try runDiskutil(["mount", volume.bsdName], operation: "mount writable")
        guard let mounted = try resolve(volumeUUID: volumeUUID) else {
            throw DiskMutationError.volumeNotFoundAfterMount
        }
        guard !mounted.isReadOnly else { throw DiskMutationError.stillReadOnly }
        return mounted
    }

    func remountReadOnly(volumeUUID: String) throws -> DiskProtectionResult {
        guard let volume = try resolve(volumeUUID: volumeUUID) else { return .disconnected }
        try runDiskutil(["unmount", volume.bsdName], operation: "unmount")
        try runDiskutil(["mount", "readOnly", volume.bsdName], operation: "mount read-only")
        guard let mounted = try resolve(volumeUUID: volumeUUID) else {
            throw DiskMutationError.volumeNotFoundAfterMount
        }
        guard mounted.isReadOnly else { throw DiskMutationError.stillWritable }
        return .protected(mounted)
    }

    private func runDiskutil(_ arguments: [String], operation: String) throws {
        let output = try runner.run("/usr/sbin/diskutil", arguments: arguments)
        guard output.status == 0 else {
            let detail = String(data: output.stderr + output.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw DiskMutationError.commandFailed(operation, detail ?? "diskutil failed")
        }
    }
}

enum DiskMutationError: LocalizedError {
    case volumeNotFound
    case volumeNotFoundAfterMount
    case stillReadOnly
    case stillWritable
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .volumeNotFound: "The selected volume is no longer mounted."
        case .volumeNotFoundAfterMount: "The selected volume could not be verified after mounting."
        case .stillReadOnly: "The selected volume remained read-only after the exception was activated."
        case .stillWritable: "The selected volume remained writable when protection was restored."
        case .commandFailed(let operation, let detail): "Could not \(operation) the selected volume: \(detail)"
        }
    }
}
