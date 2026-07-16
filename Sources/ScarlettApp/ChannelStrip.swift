import SwiftUI
import ScarlettCore

/// A vertical mixer strip for one matrix channel in the currently selected bus.
/// Layout mirrors Focusrite Control 2: name + source + colored underline at top,
/// fader with dB scale and meter in the middle, M/S buttons at the bottom.
struct ChannelStrip: View {
    let channel: Int
    @Bindable var state: MixerState
    @State private var editingName: Bool = false
    @State private var nameDraft: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        let source = state.mixerSources[channel]
        let isMuted = state.mixerMutes[channel]
        let isSoloed = state.mixerSolos[channel]

        VStack(spacing: StripLayout.vSpacing) {
            header(source: source)
            inputSwitch(source: source)
                .frame(height: StripLayout.switchRowHeight)
            panSlider
                .frame(height: StripLayout.panRowHeight)
            fader
                .frame(height: StripLayout.faderHeight)
            peakReadout
                .frame(height: StripLayout.peakReadoutHeight)
            mutesolo(isMuted: isMuted, isSoloed: isSoloed)
                .frame(height: StripLayout.controlsHeight)
        }
        .frame(width: StripLayout.width)
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            // Subtle border to make linked pairs visually obvious.
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(state.isLinked(channel) ? Theme.muteActive.opacity(0.45) : .clear, lineWidth: 1)
        )
    }

    // MARK: - Contextual hardware-input switch
    //
    // When this strip's source is one of the 8i6's software-configurable
    // hardware inputs, surface the relevant switch right here on the strip
    // so the user doesn't have to navigate elsewhere.  Otherwise reserve
    // the same vertical space (an empty placeholder) to keep strip heights
    // consistent across the row.

    private func inputSwitch(source byte: UInt8) -> some View {
        let profile = state.device?.profile ?? .scarlett8i6
        let analogSources = profile.sources.filter { $0.category == .analog }
        guard let analogIdx = analogSources.firstIndex(where: { $0.byte == byte }) else {
            return AnyView(Color.clear.frame(height: StripLayout.switchRowHeight))
        }
        let hwChannel = analogIdx + 1
        if profile.impedanceChannels.contains(hwChannel) {
            return AnyView(ImpedanceSwitch(value: Binding(
                get: { hwChannel == 1 ? state.impedance1 : state.impedance2 },
                set: { state.userSetImpedance(channel: hwChannel, mode: $0) }
            )))
        }
        if profile.hiLoChannels.contains(hwChannel) {
            return AnyView(HiLoSwitch(value: Binding(
                get: { hwChannel == 3 ? state.hi3 : state.hi4 },
                set: { state.userSetHiLo(channel: hwChannel, hi: $0) }
            )))
        }
        return AnyView(Color.clear.frame(height: StripLayout.switchRowHeight))
    }

    // MARK: - Header

    @ViewBuilder
    private func header(source byte: UInt8) -> some View {
        let profile = state.device?.profile ?? .scarlett8i6
        let options = profile.matrixChannelSources
        let current = options.first(where: { $0.byte == byte })
            ?? profile.source(forByte: byte)
        VStack(spacing: 3) {
            nameField
            ThemedMenuPicker(
                options: options,
                displayName: { $0.displayName },
                selection: Binding(
                    get: { current },
                    set: { state.userSetMixerSource(channel: channel, sourceByte: $0.byte) }
                )
            )
            Rectangle()
                .fill(accentColor(forByte: byte, from: profile))
                .frame(height: 2)
                .padding(.horizontal, 2)
        }
    }

    private func accentColor(forByte byte: UInt8, from profile: DeviceProfile) -> Color {
        guard let sd = profile.sources.first(where: { $0.byte == byte }) else {
            return Theme.accentOther
        }
        switch sd.category {
        case .analog, .digital: return Theme.accentAnalog
        case .daw:              return Theme.accentPlayback
        case .mixOutput, .off:  return Theme.accentOther
        }
    }

    /// Channel name — defaults to "Ch N", double-click to rename.
    private var nameField: some View {
        let stored = state.mixerNames[channel]
        let displayed = stored.isEmpty ? "Ch \(channel + 1)" : stored
        return Group {
            if editingName {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onExitCommand { editingName = false }
                    .onAppear {
                        nameDraft = stored
                        nameFocused = true
                    }
            } else {
                Text(displayed)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        nameDraft = stored
                        editingName = true
                    }
                    .help("Double-click to rename")
            }
        }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        state.userSetChannelName(channel: channel, name: trimmed)
        editingName = false
    }

    // MARK: - Fader column

    private var fader: some View {
        let pair = state.selectedBusIndex / 2
        let level = state.mixerLevels[channel][pair]
        let source = state.mixerSources[channel]

        return HStack(alignment: .center, spacing: 4) {
            VerticalFader(db: Binding(
                get: { level },
                set: { state.userSetMixerLevel(channel: channel, pair: pair, level: $0) }
            ))
            .opacity(state.mixerMutes[channel] ? 0.4 : 1.0)
            .contextMenu {
                Button("Reset fader to 0 dB") {
                    state.userSetMixerLevel(channel: channel, pair: pair, level: 0)
                }
            }

            // Reads peaks/peaksHeld/peaksMax internally → isolated from the
            // outer strip body so 20 Hz meter updates only re-render this
            // small view, not the whole strip (faders, pickers, buttons, …).
            StripMeter(state: state, sourceByte: source)

            DbScale()
        }
        .frame(height: StripLayout.faderHeight)
        .overlay(alignment: .topTrailing) {
            Text(formatDb(level))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(state.mixerMutes[channel] ? Theme.muteActive : Theme.textSecondary)
                .padding(.top, -16)
        }
    }

    private var panSlider: some View {
        let pair = state.selectedBusIndex / 2
        let pan = state.mixerPans[channel][pair]
        return VStack(spacing: 1) {
            Slider(
                value: Binding(
                    get: { pan },
                    set: { state.userSetMixerPan(channel: channel, pair: pair, pan: $0) }
                ),
                in: -1...1
            )
            .controlSize(.mini)
            .contextMenu {
                Button("Reset pan to center") {
                    state.userSetMixerPan(channel: channel, pair: pair, pan: 0)
                }
            }
            Text(panLabel(pan))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func panLabel(_ pan: Double) -> String {
        if abs(pan) < 0.02 { return "C" }
        let pct = Int(round(abs(pan) * 100))
        return pan < 0 ? "L\(pct)" : "R\(pct)"
    }

    private var peakReadout: some View {
        let source = state.mixerSources[channel]
        return StripPeakReadout(state: state, sourceByte: source)
    }

    // MARK: - Mute / Solo

    private func mutesolo(isMuted: Bool, isSoloed: Bool) -> some View {
        HStack(spacing: 3) {
            Spacer(minLength: 0)
            StripButton(letter: "M", active: isMuted, activeColor: Theme.muteActive) {
                state.userToggleMixerMute(channel: channel)
            }
            StripButton(letter: "S", active: isSoloed, activeColor: Theme.soloActive) {
                state.userToggleMixerSolo(channel: channel)
            }
            LinkButton(active: state.isLinked(channel)) {
                state.userToggleLink(channel: channel)
            }
            Spacer(minLength: 0)
        }
    }

    private func formatDb(_ db: Double) -> String {
        if db <= -60 { return "−∞" }
        let r = Int(db.rounded())
        return r > 0 ? "+\(r)" : "\(r)"
    }
}

/// Compact Line/Instrument toggle for the combo-input strips (Analog 1, 2).
struct ImpedanceSwitch: View {
    @Binding var value: Impedance

    var body: some View {
        Picker("", selection: $value) {
            Text("Line").tag(Impedance.line)
            Text("Inst").tag(Impedance.instrument)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .frame(height: 22)
    }
}

/// Compact Lo/Hi gain toggle for the line-input strips (Analog 3, 4).
struct HiLoSwitch: View {
    @Binding var value: Bool

    var body: some View {
        Picker("", selection: $value) {
            Text("Lo").tag(false)
            Text("Hi").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .frame(height: 22)
    }
}

/// Live + peak-hold + max meter for one strip.  Isolated into its own struct
/// so that 20 Hz `peaks*` updates only re-render this view, not the parent
/// strip's fader / pickers / buttons / name field.
struct StripMeter: View {
    @Bindable var state: MixerState
    let sourceByte: UInt8
    var height: CGFloat = StripLayout.faderHeight

    var body: some View {
        let profile = state.device?.profile ?? .scarlett8i6
        let live = level(from: state.peaks, profile: profile)
        let held = level(from: state.peaksHeld, profile: profile)
        let max_ = level(from: state.peaksMax, profile: profile)
        VerticalMeter(db: live, peakDb: held, maxPeakDb: max_, height: height)
    }

    private func level(from peaks: PeakReading, profile: DeviceProfile) -> Double {
        peaks.level(forByte: sourceByte, profile: profile)
    }

    static func level(from peaks: PeakReading, byte: UInt8, profile: DeviceProfile) -> Double {
        peaks.level(forByte: byte, profile: profile)
    }
}

extension PeakReading {
    func level(forByte byte: UInt8, profile: DeviceProfile) -> Double {
        guard let slot = profile.peakSlot(forByte: byte) else { return -.infinity }
        switch slot {
        case .input(let i):  return inputs.indices.contains(i) ? inputs[i] : -.infinity
        case .daw(let i):    return daw.indices.contains(i) ? daw[i] : -.infinity
        case .mixer(let i):  return mixer.indices.contains(i) ? mixer[i] : -.infinity
        }
    }
}

/// Numeric "Pk" + clickable "Mx" peak readout. Isolated for the same reason
/// as `StripMeter` — only this view re-renders when the peak values change.
struct StripPeakReadout: View {
    @Bindable var state: MixerState
    let sourceByte: UInt8

    var body: some View {
        let profile = state.device?.profile ?? .scarlett8i6
        let peak = StripMeter.level(from: state.peaksHeld, byte: sourceByte, profile: profile)
        let max_ = StripMeter.level(from: state.peaksMax, byte: sourceByte, profile: profile)
        VStack(spacing: 1) {
            Text(formatPeak("Pk", peak))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Button {
                state.clearMaxPeak(forByte: sourceByte)
            } label: {
                Text(formatPeak("Mx", max_))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.meterHigh)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to reset this channel's max peak")
        }
        .frame(maxWidth: .infinity)
    }

    private func formatPeak(_ label: String, _ db: Double) -> String {
        if !db.isFinite || db <= -60 { return "\(label) −∞" }
        return String(format: "%@ %5.1f", label, db)
    }
}

/// Small button shown on each strip — toggles whether this channel is in a
/// linked stereo pair with its even/odd partner.  Active = paired.
struct LinkButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(active ? Theme.muteActive : Theme.panelRaised)
                .foregroundStyle(active ? .white : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help(active ? "Linked stereo pair (click to unlink)" : "Link with adjacent channel")
        .accessibilityLabel(active ? "Unlink stereo pair" : "Link with adjacent channel")
    }
}

struct StripButton: View {
    let letter: String
    let active: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 26, height: 22)
                .background(active ? activeColor : Theme.panelRaised)
                .foregroundStyle(active ? .white : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}
