import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AccessModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                accessStatus
                volumeSection
                exceptionSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .task { await model.refreshVolumes() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await model.refreshHelperState()
            }
        }
    }

    @ViewBuilder
    private var accessStatus: some View {
        if model.exceptionOperation == .starting, model.activeException == nil {
            OperationStatusCard(
                title: "Enabling writable access…",
                detail: "Disk Utility is remounting the selected volume. This can take a moment.",
                systemImage: "clock.arrow.circlepath"
            )
        } else if let active = model.activeException {
            ActiveExceptionCard(
                active: active,
                operation: model.exceptionOperation
            ) {
                Task { await model.revokeException() }
            }
        } else {
            protectionNotice
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 34))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Disk Encrypter Access")
                    .font(.title2.bold())
                Text("Request a short, audited writing exception for one disk.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var protectionNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.checkered")
                .foregroundStyle(.green)
            Text("DiskEncrypter remains active. Only the selected volume will be allowed, and every other external disk stays protected.")
                .font(.callout)
            Spacer()
        }
        .padding(12)
        .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private var volumeSection: some View {
        GroupBox("Unencrypted external volumes") {
            VStack(spacing: 10) {
                HStack {
                    Text(model.volumeSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await model.refreshVolumes() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
                }

                if model.isRefreshing && model.volumes.isEmpty {
                    ProgressView("Checking mounted volumes…")
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else if model.volumes.isEmpty {
                    ContentUnavailableView(
                        "No eligible volumes",
                        systemImage: "externaldrive",
                        description: Text("Connect and mount an unencrypted external disk, then refresh.")
                    )
                    .frame(minHeight: 120)
                } else {
                    List(model.volumes, selection: $model.selectedVolumeID) { volume in
                        VolumeRow(volume: volume)
                            .tag(volume.id)
                    }
                    .frame(minHeight: 150)
                }
            }
            .padding(.top, 6)
        }
    }

    private var exceptionSection: some View {
        GroupBox("Exception request") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Duration")
                    Picker("Duration", selection: $model.duration) {
                        ForEach(ExceptionDuration.allCases) { duration in
                            Text(duration.title).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                GridRow(alignment: .top) {
                    Text("Reason")
                    TextField("Example: Export approved camera deliverables", text: $model.note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .padding(.top, 6)

            if let validation = model.validationMessage {
                Label(validation, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            HStack {
                Label(
                    model.currentUserIsAdmin ? "Administrator account" : "Administrator account required",
                    systemImage: model.currentUserIsAdmin ? "person.badge.key.fill" : "person.crop.circle.badge.exclamationmark"
                )
                .font(.callout)
                .foregroundColor(model.currentUserIsAdmin ? Color.secondary : Color.red)

                Spacer()

                helperControls
            }

            Text(model.helperStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var helperControls: some View {
        switch model.helperStatus {
        case .notInstalled:
            Button("Register Privileged Helper") {
                Task { await model.registerHelper() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.currentUserIsAdmin)
        case .requiresApproval:
            Button("Open Approval Settings") {
                Task { await model.openApprovalSettings() }
            }
            .buttonStyle(.borderedProminent)
        case .unavailable:
            Button("Helper Unavailable") {}
                .disabled(true)
        case .ready:
            if let operation = model.exceptionOperation {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operation == .starting ? "Enabling access…" : "Restoring protection…")
                        .font(.callout)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button("Start Timed Exception") {
                    Task { await model.startException() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartException)
            }
        }
    }
}

private struct OperationStatusCard: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            ProgressView()
                .controlSize(.small)
        }
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ActiveExceptionCard: View {
    let active: ActiveException
    let operation: ExceptionOperation?
    let revoke: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusDetail(at: context.date))
                            .font(.callout)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 8)
                    if operation != nil || active.status == .activating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                HStack(alignment: .bottom, spacing: 12) {
                    Text(active.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    if operation == nil, active.status != .activating {
                        Button("End Now", role: .destructive, action: revoke)
                            .fixedSize()
                    }
                }
            }
            .padding(12)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var statusTitle: String {
        if operation == .ending { return "Restoring read-only protection…" }
        if operation == .starting { return "Enabling writable access…" }
        return switch active.status {
        case .activating: "Enabling writable access…"
        case .active: "Writing exception active"
        case .expirationPending: "Protection restoration pending"
        }
    }

    private var iconName: String {
        return switch active.status {
        case .activating: "clock.arrow.circlepath"
        case .active: "clock.badge.checkmark.fill"
        case .expirationPending: "exclamationmark.shield.fill"
        }
    }

    private var iconColor: Color {
        active.status == .expirationPending ? .red : .orange
    }

    private func statusDetail(at date: Date) -> String {
        if operation != nil { return "\(active.volumeName) • Please wait" }
        return switch active.status {
        case .activating: "\(active.volumeName) • Please wait"
        case .active, .expirationPending: "\(active.volumeName) • \(remaining(at: date))"
        }
    }

    private func remaining(at date: Date) -> String {
        let seconds = max(0, Int(active.expiresAt.timeIntervalSince(date)))
        if seconds == 0 { return "expiring now" }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60)) remaining"
    }
}

private struct VolumeRow: View {
    let volume: ExternalVolume

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: volume.isReadOnly ? "externaldrive.badge.lock" : "externaldrive.fill")
                .font(.title3)
                .foregroundStyle(volume.isReadOnly ? .orange : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.headline)
                Text("\(volume.fileSystem) • \(volume.bsdName) • \(volume.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if volume.isReadOnly {
                Text("Read-only")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            if volume.volumeUUID == nil {
                Text("No stable UUID")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
    }
}
