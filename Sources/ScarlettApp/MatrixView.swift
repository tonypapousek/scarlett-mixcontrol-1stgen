import SwiftUI
import ScarlettCore

/// The matrix mixer view — Control 2 style.
///
/// Top bar: bus tabs (number from active DeviceProfile).
/// Below: two rows of horizontally scrolling `ChannelStrip`s.
struct MatrixMixerView: View {
    @Bindable var state: MixerState

    private var visibleChannels: Range<Int> {
        0..<(state.device?.profile.matrixInputCount ?? 18)
    }

    private var busCount: Int {
        state.device?.profile.mixBusCount ?? 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            busTabs
            strips
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mixer").font(.title3).bold().foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Pick a bus tab to set its per-channel gains. Use the strips' source pickers to wire signals in.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 320)
        }
    }

    private var busTabs: some View {
        let busCount = busCount
        return HStack(spacing: 4) {
            ForEach(0..<busCount, id: \.self) { idx in
                let selected = state.selectedBusIndex == idx
                Button {
                    state.selectedBusIndex = idx
                } label: {
                    Text("M\(idx + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 60, height: 28)
                        .background(selected ? Theme.muteActive : Theme.panelRaised)
                        .foregroundStyle(selected ? .white : Theme.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .contextMenu { copyMixMenuItems(targetBusIndex: idx) }
            }
            Spacer()
            actionButton(icon: "arrow.counterclockwise", label: "Clear peaks") {
                state.clearMaxPeaks()
            }
            .help("Reset the red max-peak tick on every strip.")

            actionButton(
                icon: state.masterMuted ? "speaker.slash.fill" : "speaker.wave.2",
                label: state.masterMuted ? "Master muted" : "Mute all",
                active: state.masterMuted,
                activeColor: Theme.muteActive
            ) {
                state.userSetMasterMute(!state.masterMuted)
            }
            .help("Mute every output bus on the device.")

            actionButton(icon: "internaldrive", label: "Save to hardware") {
                state.saveToFlash()
            }
            .disabled(!state.isConnected)
            .help("Persist current settings to device flash so they survive a power cycle.")
        }
    }

    @ViewBuilder
    private func copyMixMenuItems(targetBusIndex: Int) -> some View {
        let sourcePair = targetBusIndex / 2
        let busPairs = (busCount + 1) / 2
        let pairLabel: (Int) -> String = { p in "M\(p*2 + 1)+M\(p*2 + 2)" }
        ForEach(0..<busPairs, id: \.self) { dest in
            if dest != sourcePair {
                Button("Copy \(pairLabel(sourcePair)) → \(pairLabel(dest))") {
                    state.userCopyMixPair(from: sourcePair, to: dest)
                }
            }
        }
    }

    private func actionButton(
        icon: String, label: String,
        active: Bool = false, activeColor: Color = Theme.muteActive,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? activeColor : Theme.panelRaised)
            .foregroundStyle(active ? .white : Theme.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var strips: some View {
        let ch = visibleChannels
        let count = ch.count
        let mid = count / 2
        let topHalf = ch.lowerBound..<ch.lowerBound + mid
        let botHalf = ch.lowerBound + mid..<ch.upperBound
        return HStack(alignment: .top, spacing: 6) {
            VStack(spacing: StripLayout.vSpacing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(topHalf, id: \.self) { ch in
                            ChannelStrip(channel: ch, state: state)
                        }
                    }
                    .padding(.vertical, StripLayout.rowPaddingV)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(botHalf, id: \.self) { ch in
                            ChannelStrip(channel: ch, state: state)
                        }
                    }
                    .padding(.vertical, StripLayout.rowPaddingV)
                }
            }
            PinnedDawStrip(state: state)
            PinnedMasterStrip(state: state)
        }
    }
}
