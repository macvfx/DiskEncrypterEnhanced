import AppKit
import SwiftUI

enum AppWindowID {
    static let history = "exception-history"
    static let help = "app-help"
    static let about = "app-about"
}

struct DiskEncrypterAccessCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Disk Encrypter Access") {
                openWindow(id: AppWindowID.about)
            }
        }

        CommandMenu("History") {
            Button("Show Exception History") {
                openWindow(id: AppWindowID.history)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button("Disk Encrypter Access Help") {
                openWindow(id: AppWindowID.help)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

struct ExceptionHistoryView: View {
    @ObservedObject var model: AccessModel
    @State private var selection: UUID?

    private var records: [ExceptionHistoryRecord] {
        ExceptionHistoryRecord.records(from: model.auditEvents)
    }

    var body: some View {
        NavigationSplitView {
            historyList
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let selection,
               let record = records.first(where: { $0.id == selection }) {
                ExceptionHistoryDetail(record: record)
            } else {
                ContentUnavailableView(
                    "Select an exception",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Choose an exception to review its reason, disk identity, and audit events.")
                )
            }
        }
        .navigationTitle("Exception History")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingHistory)
            }
        }
        .task { await reload() }
    }

    @ViewBuilder
    private var historyList: some View {
        if model.isLoadingHistory && records.isEmpty {
            ProgressView("Reading protected history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.historyError, records.isEmpty {
            ContentUnavailableView(
                "History unavailable",
                systemImage: "exclamationmark.shield",
                description: Text(error)
            )
        } else if records.isEmpty {
            ContentUnavailableView(
                "No exceptions recorded",
                systemImage: "clock",
                description: Text("Completed and active exceptions will appear here after the first request.")
            )
        } else {
            List(records, selection: $selection) { record in
                ExceptionHistoryRow(record: record)
                    .tag(record.id)
            }
        }
    }

    private func reload() async {
        await model.loadAuditHistory()
        if selection == nil || !records.contains(where: { $0.id == selection }) {
            selection = records.first?.id
        }
    }
}

private struct ExceptionHistoryRow: View {
    let record: ExceptionHistoryRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: record.action.historyIcon)
                .foregroundStyle(record.action.historyColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.volumeName)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.action.historyTitle)
                    .font(.callout)
                    .foregroundStyle(record.action.historyColor)
                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ExceptionHistoryDetail: View {
    let record: ExceptionHistoryRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: record.action.historyIcon)
                        .font(.system(size: 30))
                        .foregroundStyle(record.action.historyColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.volumeName)
                            .font(.title2.bold())
                        Text(record.action.historyTitle)
                            .foregroundStyle(record.action.historyColor)
                    }
                }

                GroupBox("Exception") {
                    LabeledContent("Requested", value: record.startedAt.formatted(date: .long, time: .standard))
                    LabeledContent("Requested by", value: record.requestedBy)
                    LabeledContent("Duration", value: durationText)
                    LabeledContent("Scheduled expiry", value: record.expiresAt.formatted(date: .long, time: .standard))
                    LabeledContent("Camera media structure", value: record.cameraMediaStructureDetected ? "Detected" : "Not detected")
                }

                GroupBox("Disk identity") {
                    LabeledContent("Volume UUID", value: record.volumeUUID)
                        .textSelection(.enabled)
                    LabeledContent("BSD device", value: record.bsdName)
                    LabeledContent("Filesystem", value: record.fileSystem)
                }

                GroupBox("Reason") {
                    Text(record.note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }

                GroupBox("Audit events") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(record.events, id: \.eventID) { event in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: event.action.historyIcon)
                                    .foregroundStyle(event.action.historyColor)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(event.action.historyTitle)
                                            .font(.headline)
                                        Spacer()
                                        Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(event.detail)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var durationText: String {
        record.durationMinutes == 60 ? "1 hour" : "\(record.durationMinutes) minutes"
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("Disk Encrypter Access Help", systemImage: "externaldrive.badge.checkmark")
                    .font(.largeTitle.bold())

                HelpSection(title: "What this app does") {
                    Text("Disk Encrypter Access grants one administrator-approved, time-limited writing exception to one unencrypted external disk. DiskEncrypter stays active for every other disk.")
                }

                HelpSection(title: "Before you begin") {
                    HelpStep(number: 1, text: "Install the signed app in /Applications.")
                    HelpStep(number: 2, text: "Register and approve the privileged helper when prompted.")
                    HelpStep(number: 3, text: "Connect an unencrypted external disk with a stable Volume UUID.")
                }

                HelpSection(title: "Start a timed exception") {
                    HelpStep(number: 1, text: "Select the intended disk.")
                    HelpStep(number: 2, text: "Choose a duration and enter an audit reason of at least 10 characters.")
                    HelpStep(number: 3, text: "Select Start Timed Exception and wait for writable access to be confirmed.")
                    HelpStep(number: 4, text: "Use End Now when work is complete, or allow the timer to restore protection automatically.")
                }

                HelpSection(title: "Exception history") {
                    Text("Choose History > Show Exception History, or use the History button in the main window. The helper reads the protected audit log and shows each exception with its disk UUID, requester, reason, expiry, camera-media detection, and event timeline.")
                }

                HelpSection(title: "Safety behavior") {
                    Text("The helper never force-unmounts a busy disk. If files are still open at expiry, protection restoration remains pending and retries automatically. Close files using the disk and eject it normally if needed.")
                }

                HelpSection(title: "Troubleshooting") {
                    Text("If the helper is unavailable, confirm that the complete app is in /Applications and approve it in System Settings > General > Login Items & Extensions. History is available only while the approved helper can authenticate the administrator app.")
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
            content
                .foregroundStyle(.secondary)
        }
    }
}

private struct HelpStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.blue, in: Circle())
            Text(text)
        }
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Disk Encrypter Access")
                .font(.title2.bold())
            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)
            Text("Audited, time-limited writing access for one protected external disk.")
                .multilineTextAlignment(.center)
                .frame(width: 340)
            Text("© 2026 macVFX")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 420)
    }
}

private extension ExceptionAuditAction {
    var historyTitle: String {
        switch self {
        case .requested: "Requested"
        case .granted: "Granted"
        case .revoked: "Ended early"
        case .expired: "Expired"
        case .expirationPending: "Protection restoration pending"
        case .denied: "Denied"
        case .failed: "Failed"
        }
    }

    var historyIcon: String {
        switch self {
        case .requested: "person.badge.key"
        case .granted: "externaldrive.badge.checkmark"
        case .revoked: "stop.circle"
        case .expired: "clock.badge.checkmark"
        case .expirationPending: "exclamationmark.shield"
        case .denied: "hand.raised"
        case .failed: "xmark.octagon"
        }
    }

    var historyColor: Color {
        switch self {
        case .requested: .blue
        case .granted: .orange
        case .revoked, .expired: .green
        case .expirationPending: .red
        case .denied, .failed: .red
        }
    }
}
