import Foundation
import Combine

enum ExceptionOperation: Equatable {
    case starting
    case ending
}

@MainActor
final class AccessModel: ObservableObject {
    @Published private(set) var volumes: [ExternalVolume] = []
    @Published var selectedVolumeID: String?
    @Published var duration: ExceptionDuration = .fifteenMinutes
    @Published var note = ""
    @Published private(set) var isRefreshing = false
    @Published private(set) var exceptionOperation: ExceptionOperation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var helperStatus: HelperStatus = .notInstalled
    @Published private(set) var activeException: ActiveException?
    let currentUserIsAdmin: Bool

    private let discovery: DiskutilVolumeDiscovery
    private let service: any PrivilegedExceptionServicing

    init(
        discovery: DiskutilVolumeDiscovery = DiskutilVolumeDiscovery(),
        service: any PrivilegedExceptionServicing = XPCPrivilegedExceptionService(),
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
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedNote.isEmpty { return "A reason is required for the audit record." }
        if cleanedNote.count < HelperConstants.minimumReasonLength {
            return "Enter at least \(HelperConstants.minimumReasonLength) characters for the reason."
        }
        if cleanedNote.count > 500 { return "Keep the reason to 500 characters or fewer." }
        if !currentUserIsAdmin { return "Only an administrator can request an exception." }
        if activeException != nil { return "End the current exception before requesting another one." }
        if helperStatus != .ready { return "Privileged helper approval is required before disk access can change." }
        return nil
    }

    var canStartException: Bool {
        validationMessage == nil && !isRefreshing && exceptionOperation == nil
    }

    var helperStatusText: String {
        switch helperStatus {
        case .notInstalled:
            "The bundled root helper must be registered before disk access can change."
        case .requiresApproval:
            "An administrator must approve the helper in System Settings > General > Login Items & Extensions."
        case .unavailable(let detail):
            detail
        case .ready:
            "The signed helper is approved. Requests are validated and recorded in the protected audit log."
        }
    }

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
            if newStatus == .ready {
                activeException = try await service.snapshot().activeException
            } else {
                activeException = nil
            }
            if let selectedVolumeID, !volumes.contains(where: { $0.id == selectedVolumeID }) {
                self.selectedVolumeID = nil
            }
            if selectedVolumeID == nil, volumes.count == 1 {
                selectedVolumeID = volumes[0].id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHelperState() async {
        let previous = activeException
        let status = await service.status()
        helperStatus = status
        guard status == .ready else {
            activeException = nil
            return
        }
        do {
            activeException = try await service.snapshot().activeException
            if previous != nil, activeException == nil {
                volumes = try await discovery.mountedUnencryptedExternalVolumes()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startException() async {
        guard let volume = selectedVolume else { return }
        errorMessage = nil
        exceptionOperation = .starting
        defer { exceptionOperation = nil }
        do {
            let request = try ExceptionRequest(volume: volume, duration: duration, note: note)
            activeException = try await service.begin(request).activeException
            note = ""
            await refreshVolumes()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func registerHelper() async {
        errorMessage = nil
        do {
            try await service.register()
            helperStatus = await service.status()
        } catch PrivilegedServiceError.approvalRequired {
            helperStatus = .requiresApproval
            await service.openApprovalSettings()
        } catch {
            errorMessage = error.localizedDescription
            helperStatus = await service.status()
        }
    }

    func openApprovalSettings() async {
        await service.openApprovalSettings()
    }

    func revokeException() async {
        guard let activeException else { return }
        errorMessage = nil
        exceptionOperation = .ending
        defer { exceptionOperation = nil }
        do {
            self.activeException = try await service.revoke(requestID: activeException.requestID).activeException
            await refreshVolumes()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
