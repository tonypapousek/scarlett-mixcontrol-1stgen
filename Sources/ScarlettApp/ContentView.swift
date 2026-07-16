import SwiftUI
import ScarlettCore

enum SampleRateOption: UInt32, CaseIterable, Identifiable {
    case hz44100 = 44100
    case hz48000 = 48000
    case hz88200 = 88200
    case hz96000 = 96000

    var id: UInt32 { rawValue }
    var displayName: String {
        switch self {
        case .hz44100: return "44.1 kHz"
        case .hz48000: return "48 kHz"
        case .hz88200: return "88.2 kHz"
        case .hz96000: return "96 kHz"
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case mixer, routing, presets, device

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mixer:   return "Mixer"
        case .routing: return "Routing"
        case .presets: return "Presets"
        case .device:  return "Device"
        }
    }
    var systemImage: String {
        switch self {
        case .mixer:   return "slider.vertical.3"
        case .routing: return "arrow.triangle.branch"
        case .presets: return "bookmark"
        case .device:  return "gearshape"
        }
    }
}

struct ContentView: View {
    @Bindable var state: MixerState
    @State private var tab: AppTab = .mixer
    @State private var sidebarCollapsed: Bool = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                // Vertical divider extends from the very top of the window
                // — including through the (transparent) title bar — so the
                // sidebar/main split is visually continuous.
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1)
                    .ignoresSafeArea(edges: .top)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.22), value: sidebarCollapsed)
            .background(Theme.background)
            .blur(radius: showFirstLaunchPrompt ? 6 : 0)

            if showFirstLaunchPrompt {
                Color.black.opacity(0.45).ignoresSafeArea()
                FirstLaunchCard(state: state)
            }
        }
        .preferredColorScheme(.dark)
        .task { state.startMeterPolling() }
    }

    /// Show the first-launch dialog only when the device is actually
    /// connected — that way the user knows their device is recognised
    /// before they have to decide whether to overwrite its state.
    private var showFirstLaunchPrompt: Bool {
        state.showFirstLaunchPrompt && state.isConnected
    }

    // The window's title bar shows "Scarlett MixControl" against the dark
    // window chrome; the sidebar (a lighter panel) needs to be wide enough
    // to cover the full title so the text doesn't get split across the two
    // background shades.
    private var sidebarWidth: CGFloat { sidebarCollapsed ? 56 : 250 }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            ForEach(AppTab.allCases) { item in
                sidebarRow(item)
            }
            Spacer(minLength: 0)
            sidebarFooter
        }
        .frame(width: sidebarWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        // The fill extends behind the now-transparent title bar (note the
        // .ignoresSafeArea on the background only — the sidebar's inner
        // content still respects the safe area so it sits below the traffic
        // lights).
        .background {
            Theme.panel.ignoresSafeArea(edges: .top)
        }
    }

    private var sidebarHeader: some View {
        HStack {
            if !sidebarCollapsed {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.device?.profile.modelName ?? "Scarlett MixControl")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("1st Gen")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Button {
                sidebarCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 22)
                    .background(Theme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help(sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
            .accessibilityLabel(sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
        }
        .padding(.horizontal, sidebarCollapsed ? 0 : 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
    }

    @ViewBuilder
    private var sidebarFooter: some View {
        if sidebarCollapsed {
            VStack(spacing: 8) {
                Image(systemName: connectionIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(connectionColor)
                    .help(connectionHelp)
                Image(systemName: state.syncLocked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(state.syncLocked ? .green : .orange)
                    .help(state.syncLocked ? "Clock locked" : "No clock lock")
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                statusBadge
                if state.isConnected {
                    Text("Firmware \(state.firmware)").font(.caption2).foregroundStyle(Theme.textSecondary)
                    Text("Serial \(state.serial)").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Text("App v\(AppInfo.version)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var connectionIcon: String {
        switch state.connection {
        case .connected:    return "checkmark.circle.fill"
        case .waiting:      return "antenna.radiowaves.left.and.right.slash"
        case .disconnected: return "xmark.circle.fill"
        case .unsupported:  return "exclamationmark.triangle.fill"
        }
    }
    private var connectionColor: Color {
        switch state.connection {
        case .connected:    return .green
        case .waiting:      return .orange
        case .disconnected: return .red
        case .unsupported:  return .yellow
        }
    }
    private var connectionHelp: String {
        switch state.connection {
        case .connected:           return "Connected"
        case .waiting:             return "Waiting for device"
        case .disconnected(let r): return "Disconnected — \(r)"
        case .unsupported(let p):  return "\(p.displayName) — unsupported"
        }
    }

    private func sidebarRow(_ item: AppTab) -> some View {
        let selected = tab == item
        return Button {
            tab = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 20)
                if !sidebarCollapsed {
                    Text(item.label)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, sidebarCollapsed ? 0 : 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
            .background(selected ? Theme.panelRaised : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())   // Make the whole pill clickable, not just the text.
            .padding(.horizontal, sidebarCollapsed ? 6 : 8)
        }
        .buttonStyle(.plain)
        .help(sidebarCollapsed ? item.label : "")
    }

    private var statusBadge: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(connectionStatusText, systemImage: connectionIcon)
                .font(.caption2)
                .foregroundStyle(connectionColor)
            if state.isConnected {
                Label(state.syncLocked ? "Clock locked" : "No clock lock",
                      systemImage: state.syncLocked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(state.syncLocked ? .green : .orange)
            }
        }
    }

    private var connectionStatusText: String {
        switch state.connection {
        case .connected:    return "Connected"
        case .waiting:      return "Waiting for device"
        case .disconnected: return "Disconnected"
        case .unsupported:  return "Unsupported device"
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .mixer:   MixerPaneView(state: state)
        case .routing: RoutingView(state: state)
        case .presets: PresetsView(state: state)
        case .device:  DeviceView(state: state)
        }
    }
}

// MARK: - Mixer pane

struct MixerPaneView: View {
    @Bindable var state: MixerState

    var body: some View {
        ConnectionOverlay(state: state) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MatrixMixerView(state: state)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
        }
    }
}

// MARK: - Routing pane

struct RoutingView: View {
    @Bindable var state: MixerState

    var body: some View {
        ConnectionOverlay(state: state) {
            routingContent
        }
    }

    private var routingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Routing").font(.title2).bold().foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("Each output picks ONE source. Combine sources first in the Mixer (M1–M6) and route those here.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 380)
                }

                Panel(title: "Output assignments") {
                    VStack(spacing: 8) {
                        let outputs = state.device?.profile.physicalOutputs ?? DeviceProfile.scarlett8i6.physicalOutputs
                        let pairs = Dictionary(grouping: outputs, by: { $0.pairLabel })
                            .values
                            .map { $0.sorted { $0.isLeft && !$1.isLeft } }
                            .sorted { $0[0].wValue < $1[0].wValue }
                            .filter { $0.count == 2 }
                        ForEach(pairs.indices, id: \.self) { idx in
                            let pair = pairs[idx]
                            let left = pair[0], right = pair[1]
                            stereoRouteRow(
                                title: left.pairLabel,
                                subtitle: "Outputs \(left.wValue + 1)+\(right.wValue + 1)",
                                left: left, right: right
                            )
                        }
                    }
                }

                Panel(title: "USB capture (what your DAW sees)") {
                    VStack(spacing: 8) {
                        let totalCh = (state.device?.profile.captureChannelCount ?? 6)
                                       + (state.device?.profile.loopbackChannelCount ?? 0)
                        let pairs = totalCh / 2
                        ForEach(0..<pairs, id: \.self) { pair in
                            stereoCaptureRow(
                                "DAW input \(pair*2 + 1)+\(pair*2 + 2)",
                                "Capture channels \(pair*2 + 1) (L) and \(pair*2 + 2) (R)",
                                pair*2, pair*2 + 1
                            )
                        }
                    }
                }

                Text("Tip: routing reads always return 00 00 on the 1st-gen Scarlett — this app remembers your last setup in UserDefaults and re-pushes it to the device on launch.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }
}

extension RoutingView {

    fileprivate func stereoRouteRow(title: String, subtitle: String, left: PhysicalOutput, right: PhysicalOutput) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 220, alignment: .leading)

            routePicker(label: "L", output: left)
            routePicker(label: "R", output: right)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    fileprivate func routePicker(label: String, output: PhysicalOutput) -> some View {
        let profile = state.device?.profile ?? .scarlett8i6
        HStack(spacing: 6) {
            Text(label).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 12)
            ThemedMenuPicker(
                options: profile.sources,
                displayName: { $0.displayName },
                selection: Binding(
                    get: { profile.source(forByte: state.routes[Int(output.wValue)] ?? 0xff) },
                    set: { state.userSetRoute(wValue: Int(output.wValue), sourceByte: $0.byte) }
                ),
                width: 150
            )
        }
    }

    fileprivate func stereoCaptureRow(_ title: String, _ subtitle: String, _ leftCh: Int, _ rightCh: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 220, alignment: .leading)
            capturePicker(label: "L", channel: leftCh)
            capturePicker(label: "R", channel: rightCh)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    fileprivate func capturePicker(label: String, channel: Int) -> some View {
        let profile = state.device?.profile ?? .scarlett8i6
        HStack(spacing: 6) {
            Text(label).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 12)
            ThemedMenuPicker(
                options: profile.sources,
                displayName: { $0.displayName },
                selection: Binding(
                    get: { profile.source(forByte: state.captureRoutes[channel] ?? 0xff) },
                    set: { state.userSetCaptureRoute(channel: channel, sourceByte: $0.byte) }
                ),
                width: 150
            )
        }
    }
}

// MARK: - Device pane

struct DeviceView: View {
    @Bindable var state: MixerState

    private func compatRow(symbol: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Device").font(.title2).bold().foregroundStyle(Theme.textPrimary)

                Panel(title: "Hardware") {
                    InfoGrid(rows: hardwareRows)
                }

                Panel(title: "Connection & driver") {
                    InfoGrid(rows: connectionRows)
                    Text("All 1st-gen Scarletts are USB Audio Class 2.0 — no Focusrite kernel driver, no installer. macOS's built-in usbaudiod claims the audio + MIDI interfaces; this app talks to endpoint 0 directly for DSP control transfers, which doesn't conflict.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .padding(.top, 6)
                }

                Panel(title: "Clock & sample rate") {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Clock source").font(.subheadline).foregroundStyle(Theme.textPrimary)
                            ThemedMenuPicker(
                                options: [ClockSource.internalClock, .spdif],
                                displayName: { $0.displayName },
                                selection: Binding(
                                    get: { state.clock },
                                    set: { state.userSetClock($0) }
                                ),
                                width: 160
                            )
                            .disabled(!state.isConnected)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sample rate").font(.subheadline).foregroundStyle(Theme.textPrimary)
                            ThemedMenuPicker(
                                options: SampleRateOption.allCases,
                                displayName: { $0.displayName },
                                selection: Binding(
                                    get: { SampleRateOption(rawValue: state.sampleRate) ?? .hz48000 },
                                    set: { state.userSetSampleRate($0.rawValue) }
                                ),
                                width: 160
                            )
                            .disabled(!state.isConnected)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sync status").font(.subheadline).foregroundStyle(Theme.textPrimary)
                            HStack(spacing: 6) {
                                Image(systemName: state.isConnected
                                      ? (state.syncLocked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                      : "questionmark.circle")
                                    .foregroundStyle(state.isConnected
                                        ? (state.syncLocked ? .green : .orange)
                                        : Theme.textSecondary)
                                Text(state.isConnected
                                     ? (state.syncLocked ? "Locked" : "No lock")
                                     : "Unknown")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.top, 2)
                        }
                        Spacer()
                    }
                    Text("Changing the sample rate while audio is streaming will interrupt usbaudiod and may glitch playback.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .padding(.top, 6)
                }

                Panel(title: "Persistence & reset") {
                    HStack(spacing: 10) {
                        Button("Save to hardware") { state.saveToFlash() }
                            .help("Writes current state to the device's flash so it survives a power cycle. Flash has finite write cycles; don't call this every change.")
                            .disabled(!state.isConnected)
                        Button("Load from device") { state.userLoadFromDevice() }
                            .help("Re-read the matrix state (sources + cell gains) from the device. Useful if another tool changed the device behind the app's back, or after a power cycle. Routing isn't refreshed — the firmware doesn't report routes back.")
                            .disabled(!state.isConnected)
                        Button("Reset routing & matrix", role: .destructive) {
                            state.userResetRoutingAndMatrix()
                        }
                        .help("Clear every output route to Off and reset all matrix channels (levels 0 / pans centered / unmuted / unsoloed / unlinked). The pinned DAW return is re-applied automatically. Hardware switches, clock, sample rate and output volumes are untouched.")
                        .disabled(!state.isConnected)
                        Spacer()
                    }
                }

                EventLogPanel(state: state)

                Panel(title: "About") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Scarlett MixControl — Community Edition")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.textPrimary)
                            Text("v\(AppInfo.version)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text("A community replacement for Focusrite's 32-bit MixControl, which doesn't run on modern macOS.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        Text("Built by @MarecekW.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .padding(.top, 4)

                        Divider().padding(.vertical, 6)

                        Text("Compatibility")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.textPrimary)
                        Text("Original MixControl supported six 1st-generation Scarlett interfaces. The 8i6 is fully supported (primary target) and the 18i8 has experimental support; the others share the protocol family but each has its own byte tables from the original binary.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            compatRow(symbol: "checkmark.circle.fill",
                                      color: .green,
                                      text: "Scarlett 8i6 — tested, primary target")
                            compatRow(symbol: "checkmark.circle.fill",
                                      color: .green,
                                      text: "Scarlett 18i8 — experimental support")
                            compatRow(symbol: "questionmark.circle",
                                      color: .orange,
                                      text: "Scarlett 6i6 — supported by original MixControl, not yet ported")
                            compatRow(symbol: "questionmark.circle",
                                      color: .orange,
                                      text: "Scarlett 16i8 — supported by original MixControl, not yet ported")
                            compatRow(symbol: "questionmark.circle",
                                      color: .orange,
                                      text: "Scarlett 18i6 — supported by original MixControl, not yet ported")
                            compatRow(symbol: "questionmark.circle",
                                      color: .orange,
                                      text: "Scarlett 18i20 — supported by original MixControl, not yet ported")
                            compatRow(symbol: "xmark.circle.fill",
                                      color: .red,
                                      text: "2nd / 3rd / 4th-gen Scarletts — different protocol, won't work")
                            compatRow(symbol: "xmark.circle.fill",
                                      color: .red,
                                      text: "Saffire / other Focusrite families — different USB layer entirely")
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private var hardwareRows: [InfoGrid.Row] {
        // Use the detected device's profile when one is connected, else
        // fall back to the 8i6 (the primary target).
        let profile = state.device?.profile ?? .scarlett8i6
        return [
            .init(label: "Model",        value: profile.displayName),
            .init(label: "Generation",   value: profile.isExperimental
                  ? "1st Gen — experimental support"
                  : "1st Gen (officially supported)"),
            .init(label: "Firmware",     value: state.firmware),
            .init(label: "Serial",       value: state.serial),
            .init(label: "Vendor",       value: "Focusrite (0x1235)"),
            .init(label: "Product",      value: String(format: "0x%04X", profile.productID)),
        ]
    }

    private var connectionRows: [InfoGrid.Row] {
        let conn: String
        if state.device == nil { conn = "Not found" }
        else if state.connectionError != nil { conn = "Error" }
        else { conn = "Connected via USB" }

        return [
            .init(label: "Status",       value: conn,
                  valueColor: state.device == nil || state.connectionError != nil ? .red : .green),
            .init(label: "Class",        value: "USB Audio Class 2.0 (vendor-extended)"),
            .init(label: "Audio path",   value: "Owned by macOS usbaudiod"),
            .init(label: "MIDI path",    value: "Owned by macOS MIDIServer"),
            .init(label: "DSP control",  value: "Endpoint 0 (this app)"),
            .init(label: "Error",        value: state.connectionError ?? "—",
                  valueColor: state.connectionError == nil ? Theme.textSecondary : .red),
        ]
    }
}

/// Wraps a pane's content. When `state.isConnected` is false, the content is
/// blurred + made non-interactive, and a centered card describes the state
/// with a Retry button.  Used by Mixer and Routing panes — Device and Presets
/// stay reachable so the user can inspect the event log / saved presets even
/// while the hardware is gone.
struct ConnectionOverlay<Content: View>: View {
    @Bindable var state: MixerState
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            content()
                .blur(radius: state.isConnected ? 0 : 6)
                .allowsHitTesting(state.isConnected)
                .animation(.easeInOut(duration: 0.18), value: state.isConnected)

            if !state.isConnected {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ConnectionOverlayCard(state: state)
                    .frame(maxWidth: 460)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.isConnected)
    }
}

struct ConnectionOverlayCard: View {
    @Bindable var state: MixerState

    var body: some View {
        let (color, icon, title, subtitle) = content
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(color)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            // Retry button only makes sense for waiting/disconnected.  For
            // "unsupported device" hammering Retry can't change the model
            // on the bus, so hide it.
            if case .unsupported = state.connection { EmptyView() } else {
                HStack(spacing: 10) {
                    Button {
                        state.attemptConnect()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Retry now")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.muteActive)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .background(Theme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 4)
    }

    private var content: (Color, String, String, String) {
        switch state.connection {
        case .connected:
            return (.green, "checkmark.circle.fill", "Connected", "")
        case .waiting:
            return (
                .orange,
                "antenna.radiowaves.left.and.right.slash",
                "Waiting for Scarlett",
                "Plug the device in via USB. The app will reconnect automatically."
            )
        case .disconnected(let reason):
            return (
                .red,
                "xmark.octagon.fill",
                "Device disconnected",
                "Reason: \(reason)\nThe app will keep trying to reconnect."
            )
        case .unsupported(let p):
            return (
                .yellow,
                "exclamationmark.triangle.fill",
                "\(p.displayName) detected — not yet supported",
                "This Community Edition supports the Scarlett 8i6 and 18i8 (1st gen). We've detected your \(p.displayName) on the bus but can't drive its mixer yet — the byte mappings differ between models.\n\nSupport for other 1st-gen Scarletts is on the roadmap. If you'd like to help, the project is open source and the byte tables can be extracted from the original MixControl binary the same way the 8i6 was — see the project README."
            )
        }
    }
}

/// First-launch welcome card — styled like `ConnectionOverlayCard` so the
/// app's modal language is consistent.  Asks the user whether to keep the
/// device's existing on-flash state or overwrite it with the app's sensible
/// defaults.
struct FirstLaunchCard: View {
    @Bindable var state: MixerState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.blue)
            VStack(spacing: 2) {
                Text("Scarlett MixControl")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Community Edition")
                    .font(.title3)            // regular weight — visual contrast with the bold title above
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("For the \(state.device?.profile.displayName ?? "Scarlett 8i6") (1st gen)")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("Your \(state.device?.profile.displayName ?? "Scarlett") keeps its routing and mixer state in flash. Keep what's already on the device, or start from a clean default config?")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            HStack(spacing: 10) {
                Button {
                    state.userCompleteFirstLaunch(applyDefaults: false)
                } label: {
                    Text("Keep existing")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.panelRaised)
                        .foregroundStyle(Theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                Button {
                    state.userCompleteFirstLaunch(applyDefaults: true)
                } label: {
                    Text("Apply defaults")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .background(Theme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.blue.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 4)
    }
}

/// Event log panel for the Device tab.  Lists recent USB, sync and
/// Core Audio events from `state.deviceEvents`, newest first.
struct EventLogPanel: View {
    @Bindable var state: MixerState

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        Panel(title: "Event log") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("USB transfers, sync changes, Core Audio device presence. Most recent first.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Clear") { state.clearDeviceEvents() }
                        .disabled(state.deviceEvents.isEmpty)
                }
                Divider().background(Theme.divider)
                if state.deviceEvents.isEmpty {
                    Text("No events yet.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(state.deviceEvents) { event in
                                EventRow(event: event)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }
    }
}

struct EventRow: View {
    let event: DeviceEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: event.severity.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(event.severity.color)
                .frame(width: 16)
            Text(EventLogPanel.formatTime(event.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(event.category)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(event.message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }
}

extension EventLogPanel {
    static func formatTime(_ d: Date) -> String { timeFormatter.string(from: d) }
}

/// Simple label-value table for the Device pane.
struct InfoGrid: View {
    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var valueColor: Color = Theme.textPrimary
    }
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 110, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(row.valueColor)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Shared components

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(16)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

