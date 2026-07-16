import SwiftUI
import ScarlettCore

@MainActor
struct PresetsView: View {
    @Bindable var state: MixerState
    @State private var newPresetName: String = ""
    @State private var confirmDelete: ScarlettPreset?
    @State private var loadErrorMessage: String?
    @State private var renamingPresetID: UUID?
    @State private var renameText: String = ""
    @FocusState private var nameFocused: Bool

    @AppStorage("scarlett.autoBackupOnReset")  private var autoBackupOnReset = true
    @AppStorage("scarlett.autoBackupOnLaunch") private var autoBackupOnLaunch = false
    @AppStorage("scarlett.autoBackupOnQuit")   private var autoBackupOnQuit = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ConnectionOverlay(state: state) {
            presetsContent
        }
    }

    private var presetsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Panel(title: "Save current state") {
                    saveRow
                    Text("Captures: output routing, matrix sources / gains / mutes / solos, channel names, stereo-link state, and which bus is in view. Existing presets with the same name are overwritten.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }

                Panel(title: "Automatic backup") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Toggle("", isOn: $autoBackupOnLaunch)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                            Text("On launch").font(.caption)
                        }
                        HStack(spacing: 8) {
                            Toggle("", isOn: $autoBackupOnQuit)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                            Text("On quit").font(.caption)
                        }
                        HStack(spacing: 8) {
                            Toggle("", isOn: $autoBackupOnReset)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                            Text("Before reset").font(.caption)
                        }
                    }
                }

                Panel(title: "Saved presets") {
                    VStack(spacing: 4) {
                        defaultPresetRow
                        if !state.presets.isEmpty {
                            Divider().overlay(Theme.divider)
                            ForEach(state.presets.sorted(by: { $0.createdAt > $1.createdAt })) { preset in
                                presetRow(preset)
                            }
                        } else {
                            Text("No presets yet — save one above.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                                .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .confirmationDialog(
            "Delete preset?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let p = confirmDelete {
                Button("Delete \"\(p.name)\"", role: .destructive) {
                    state.userDeletePreset(p)
                    confirmDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        }
        .alert(
            "Couldn't load preset",
            isPresented: Binding(
                get: { loadErrorMessage != nil },
                set: { if !$0 { loadErrorMessage = nil } }
            )
        ) {
            Button("OK") { loadErrorMessage = nil }
        } message: {
            Text(loadErrorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Presets").font(.title2).bold().foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(state.presets.count + 1) saved")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private var saveRow: some View {
        HStack(spacing: 10) {
            TextField("Preset name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onSubmit { savePreset() }

            Button {
                savePreset()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11))
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.muteActive)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)

            Spacer(minLength: 0)
        }
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        state.userSavePreset(name: name)
        newPresetName = ""
    }

    private func commitRename(_ preset: ScarlettPreset) {
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, let idx = state.presets.firstIndex(where: { $0.id == preset.id }) else {
            renamingPresetID = nil
            return
        }
        var updated = preset
        updated.name = newName
        state.presets[idx] = updated
        state.savePresets()
        renamingPresetID = nil
    }

    private func applyDefault() {
        if autoBackupOnReset {
            state.userAutoSaveBackup(label: "before reset")
        }
        state.userResetRoutingAndMatrix()
    }

    private var defaultPresetRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Default").font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text("Factory defaults for \(state.profile.displayName)")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                applyDefault()
            } label: {
                Text("Reset")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.muteActive)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Theme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func presetRow(_ preset: ScarlettPreset) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if renamingPresetID == preset.id {
                TextField("Preset name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { commitRename(preset) }
                    .onExitCommand { renamingPresetID = nil }
                    .onAppear {
                        renameText = preset.name
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            nameFocused = true
                        }
                    }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                    Text(Self.dateFormatter.string(from: preset.createdAt))
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                    Text(state.presetDeviceLabel(preset))
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Button {
                do {
                    try state.userLoadPreset(preset)
                } catch {
                    loadErrorMessage = error.localizedDescription
                }
            } label: {
                Text("Load")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.panelRaised)
                    .foregroundStyle(Theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)

            Button {
                if renamingPresetID == preset.id {
                    commitRename(preset)
                } else {
                    renameText = preset.name
                    renamingPresetID = preset.id
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 22)
                    .background(Theme.panelRaised)
                    .foregroundStyle(Theme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .help("Rename preset")

            Button {
                confirmDelete = preset
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 22)
                    .background(Theme.panelRaised)
                    .foregroundStyle(Theme.meterHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .help("Delete preset")
            .accessibilityLabel("Delete preset \(preset.name)")
        }
        .padding(10)
        .background(Theme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
