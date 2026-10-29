import Foundation
import Combine

@MainActor
final class AccessModel: ObservableObject {
    @Published private(set) var volumes: [ExternalVolume] = []
    @Published var selectedVolumeID: String?
    @Published var duration: ExceptionDuration = .fifteenMinutes
    @Published var note = ""
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var helperStatus: HelperStatus = .notInstalled
    let currentUserIsAdmin: Bool

    private let discovery: DiskutilVolumeDiscovery
    private let service: any PrivilegedExceptionServicing

    init(
        discovery: DiskutilVolumeDiscovery = DiskutilVolumeDiscovery(),
        service: any PrivilegedExceptionServicing = DeferredPrivilegedExceptionService(),
        currentUserIsAdmin: Bool = AdminEligibility.currentUserIsAdmin()
    ) {
        self.discovery = discovery
        self.service = service
        self.currentUserIsAdmin = currentUserIsAdmin
    }

    var selectedVolume: ExternalVolume? {
        volumes.first { $0.id == selectedVolumeID }
    }

    var volumeSummary: String {
        switch volumes.count {
        case 0: "No mounted unencrypted external volumes found."
        case 1: "1 mounted unencrypted external volume found."
        default: "\(volumes.count) mounted unencrypted external volumes found."
        }
    }

    var validationMessage: String? {
        if selectedVolume == nil { return "Select one external volume." }
        if selectedVolume?.volumeUUID == nil { return "This volume has no stable UUID and cannot be safely excepted." }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "A reason is required for the audit record." }
        if note.count > 500 { return "Keep the reason to 500 characters or fewer." }
        if !currentUserIsAdmin { return "Only an administrator can request an exception." }
        if helperStatus != .ready { return "Privileged helper installation is required before disk access can change." }
        return nil
    }

    var canStartException: Bool { validationMessage == nil && !isRefreshing }

    func refreshVolumes() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            async let found = discovery.mountedUnencryptedExternalVolumes()
            async let status = service.status()
            let (newVolumes, newStatus) = try await (found, status)
            volumes = newVolumes
            helperStatus = newStatus
            if let selectedVolumeID, !volumes.contains(where: { $0.id == selectedVolumeID }) {
                self.selectedVolumeID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startException() async {
        guard let volume = selectedVolume else { return }
        do {
            let request = try ExceptionRequest(volume: volume, duration: duration, note: note)
            try await service.begin(request)
            note = ""
            await refreshVolumes()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
