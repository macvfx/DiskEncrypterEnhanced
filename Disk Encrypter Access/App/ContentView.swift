import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AccessModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            protectionNotice
            volumeSection
            exceptionSection
            footer
        }
        .padding(24)
        .task { await model.refreshVolumes() }
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
            }

            HStack {
                Label(
                    model.currentUserIsAdmin ? "Administrator account" : "Administrator account required",
                    systemImage: model.currentUserIsAdmin ? "person.badge.key.fill" : "person.crop.circle.badge.exclamationmark"
                )
                .font(.callout)
                .foregroundColor(model.currentUserIsAdmin ? Color.secondary : Color.red)

                Spacer()

                Button("Start Timed Exception") {
                    Task { await model.startException() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartException)
            }

            if model.helperStatus != .ready {
                Text("The signed privileged helper is not installed yet. Disk mutation stays disabled until caller validation, protected logging, and automatic recovery are complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
