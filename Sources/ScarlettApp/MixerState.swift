import Foundation
import Observation
import AppKit
import CoreAudio
import IOKit
import ScarlettCore

/// High-level connection state of the Scarlett device.  Tracked separately from
/// the device handle so the UI can render meaningful "waiting" / "disconnected"
/// states distinct from "open but erroring on a single transfer".
public enum ConnectionState: Equatable {
    case waiting                          // App is up, nothing plugged in yet
    case connected                        // Device handle opened and last poll succeeded
    case disconnected(String)             // Was connected, lost — reason for display
    case unsupported(DeviceProfile)       // Found a Focusrite with no DeviceProfile match at all
}

// View model holding the live device handle, the latest peak meter reading,
// and the user's current slider/toggle positions. Writes to the device are
// only sent when the user changes a value — the model never tries to
// "sync" itself to the hardware on launch (we have no GET for most state).

@MainActor
@Observable
final class MixerState {
    // MARK: - Connection
    var device: ScarlettDevice?
    var connection: ConnectionState = .waiting
    var firmware: String = "—"
    var serial: String = "—"

    /// Convenience for the (very common) `is the device usable right now` check.
    var isConnected: Bool { connection == .connected }

    /// Back-compat: existing call sites read a single error string. Surfaces
    /// the most recent disconnect reason, otherwise nil.
    var connectionError: String? {
        if case .disconnected(let reason) = connection { return reason }
        return nil
    }

    /// Serial queue used to push USB writes off the main actor.  USB control
    /// transfers are fast (microseconds) but synchronous, and SwiftUI sliders
    /// fire ~60 updates/sec while dragging — running those on main causes
    /// visible jank.  All writes go through `writeAsync`.
    @ObservationIgnored
    private let usbQueue = DispatchQueue(label: "scarlett.usb-writes", qos: .userInitiated)

    nonisolated private func writeAsync(_ work: @escaping @Sendable () -> Void) {
        usbQueue.async(execute: work)
    }

    // MARK: - Meters
    var peaks: PeakReading = .empty
    /// Decayed peak-hold values per source. Updated on every poll: each value
    /// either keeps the new live reading (if higher) or decays the previous
    /// hold by `peakDecayDbPerSecond * elapsed`.
    var peaksHeld: PeakReading = .empty
    /// "All-time" peak per source — never decays automatically. Useful for
    /// gain staging: glance at the strip to see how loud each channel has
    /// peaked since you last cleared.  Reset via `clearMaxPeaks()`.
    var peaksMax: PeakReading = .empty
    var metersStale: Bool = false   // true if last poll failed
    @ObservationIgnored private let peakDecayDbPerSecond: Double = 6
    @ObservationIgnored private var syncPollAccumulator: TimeInterval = 0

    // MARK: - User-controlled values (defaults to "no change")
    //
    // Attenuation sliders: -60...0 dB range, default 0 = no attenuation.
    // We start sliders at 0 dB but DO NOT push that value to the device on
    // launch (the user might be running at -20 dB right now and we'd boost
    // them). First `userDidChange*` call sends the value.
    var monitorAtten: Double = 0
    var phonesAtten: Double  = 0
    var masterMuted: Bool    = false

    // Input switches — defaults are conservative (line / lo). Not pushed on launch.
    var impedance1: Impedance = .line
    var impedance2: Impedance = .line
    var hi3: Bool = false   // false = lo, true = hi
    var hi4: Bool = false

    // Routing — default "Off" displayed, not pushed on launch.
    // Key is physical-output wValue (0..<profile.physicalOutputs.count);
    // value is the source byte from profile.sources (0xff = write Off).
    var routes: [Int: UInt8] = [:]

    // Device config — default values shown, not pushed on launch.
    var clock: ClockSource = .internalClock
    var sampleRate: UInt32 = 48000
    var syncLocked: Bool = false

    // Dim: -20 dB attenuation overlay on monitor outputs. Stores the
    // pre-dim attenuation so we can restore it.
    var dimEnabled: Bool = false
    @ObservationIgnored private var preDimMonitorAtten: Double = 0

    /// Monitor Mono fold-down — when on, the device sums L+R into both
    /// monitor outputs.  Useful for mono-compatibility checks while mixing.
    var monitorMono: Bool = false

    // Per-side independent mutes (vs the global master mute).
    var monitorLMuted: Bool = false
    var monitorRMuted: Bool = false
    var phonesLMuted:  Bool = false
    var phonesRMuted:  Bool = false

    /// Per-USB-capture-channel routing — what the DAW sees on each of its
    /// input channels.  Key is capture-channel index, value is source byte.
    /// Persisted to UserDefaults like routes.
    var captureRoutes: [Int: UInt8] = [:]

    // Matrix mixer: 18 input channels × up to 8 mix buses (M1..M8).  The
    // user-facing knobs are `mixerLevels` + `mixerPans` + `mixerMutes` +
    // `mixerSolos`.  The per-cell gain actually sent to the device is
    // computed on demand by `effectiveGain(...)` from those four fields.
    // Storage uses raw source bytes (from DeviceProfile.sources) rather
    // than device-specific enums; views resolve display names through
    // DeviceProfile.source(forByte:).
    var mixerSources: [UInt8] = Array(repeating: 0xff, count: 18)
    /// One fader value per channel per stereo bus pair.  Inner dimension
    /// must be at least mixBusCount/2 (4 for 18i8, 3 for 8i6).  We size
    /// for the maximum so the model stays profile-agnostic.
    var mixerLevels: [[Double]] = Array(repeating: Array(repeating: 0, count: 4), count: 18)
    /// One pan position per channel per stereo bus pair.
    var mixerPans:   [[Double]] = Array(repeating: Array(repeating: 0, count: 4), count: 18)
    /// Per-channel mute — silences the channel's contribution to every
    /// mix bus.  Matches how M behaves on a real mixer / in MixControl.
    var mixerMutes: [Bool] = Array(repeating: false, count: 18)
    /// Per-channel solo.  When any channel is soloed, every non-soloed
    /// channel goes silent on every bus.
    var mixerSolos: [Bool] = Array(repeating: false, count: 18)
    /// User-set custom names per matrix channel. Empty string = use default "Ch N".
    var mixerNames: [String]   = Array(repeating: "", count: 18)
    /// Indices of the LEFT channel of each linked stereo pair.  Channels are
    /// grouped into fixed even/odd pairs: (0,1), (2,3), (4,5), …, (16,17).
    /// If `linkedPairs.contains(0)`, channels 0 and 1 are linked.
    var linkedPairs: Set<Int>  = []

    /// User-saved presets (full snapshots of routes + matrix + names + links).
    var presets: [ScarlettPreset] = []

    /// Set true once at startup if we detected a first launch (no
    /// UserDefaults state yet).  ContentView observes this and prompts
    /// the user with a choice between "apply default config" and "keep
    /// whatever's already on the device".  Cleared after either choice.
    var showFirstLaunchPrompt: Bool = false

    /// Capped event log — surfaced in the Device tab.  Newest first.
    var deviceEvents: [DeviceEvent] = []
    @ObservationIgnored private let maxEvents = 100
    @ObservationIgnored private var coreAudioListenerInstalled = false
    @ObservationIgnored private var lastCoreAudioPresence: Bool = false
    @ObservationIgnored private var didLaunchBackup = false
    var selectedBusIndex: Int = 0 {
        didSet { saveSelectedBus() }
    }

    init() {
        UserDefaults.standard.register(defaults: [
            "scarlett.autoBackupOnReset": true,
            "scarlett.autoBackupOnLaunch": false,
            "scarlett.autoBackupOnQuit": false,
        ])
        installCoreAudioListener()
        attemptConnect()
    }

    /// Formatter for auto-backup timestamps.
    private static let backupFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Save a snapshot with a descriptive auto-backup label and the
    /// current device profile name.  Checks the relevant UserDefaults
    /// toggle before saving — call only when the toggle is already known
    /// to be true, or use the convenience methods below.
    func userAutoSaveBackup(label: String) {
        let ts = Self.backupFormatter.string(from: Date())
        let tag: String
        if let name = device?.profile.displayName {
            tag = "\(name) "
        } else {
            tag = ""
        }
        userSavePreset(name: "Auto-saved \(label) – \(tag)\(ts)")
    }

    /// Try to (re-)open the device and refresh all state.  Idempotent.
    /// On success: switches to `.connected` and re-pushes persisted routes.
    /// On `deviceNotFound`: switches to `.waiting` (silent — happens at idle).
    /// On any other failure: switches to `.disconnected(reason)`.
    func attemptConnect() {
        let wasConnected = isConnected
        do {
            let dev = try ScarlettDevice()
            // Any DeviceProfile match is fair game: the profile-driven
            // protocol layer (Phase 1) and profile-keyed storage (Phase 2)
            // pick the right bytes per device.  `.unsupported` is now only
            // for PIDs with no DeviceProfile at all — which `ScarlettDevice`
            // itself throws `deviceNotFound` for, so this branch is
            // effectively dead code today but kept for forward-compat.
            self.device = dev
            if let bcd = dev.firmwareBCD() {
                let hi = (bcd >> 8) & 0xff
                let lo = bcd & 0xff
                let major = (hi >> 4) * 10 + (hi & 0xf)
                let minor = (lo >> 4) * 10 + (lo & 0xf)
                self.firmware = String(format: "v%d.%02d", major, minor)
            }
            self.serial = dev.serialNumber() ?? "—"
            refreshFromDevice()
            loadPersistedState()
            ensurePinnedDawChannels()
            // Push default routes so Mix M1 routing takes effect.
            pushDefaultRoutes()
            if !wasConnected {
                logEvent(.info, "Connection",
                         "Connected to \(dev.profile.displayName) (firmware \(firmware), serial \(serial))")
            }
            connection = .connected
            if !didLaunchBackup {
                didLaunchBackup = true
                if UserDefaults.standard.bool(forKey: "scarlett.autoBackupOnLaunch") {
                    userAutoSaveBackup(label: "at launch")
                    logEvent(.info, "Backup", "Auto-saved launch snapshot")
                }
            }
        } catch ScarlettError.deviceNotFound {
            self.device = nil
            // Clear meters so we don't show stale levels frozen from before.
            peaks = .empty
            peaksHeld = .empty
            if wasConnected {
                logEvent(.warning, "Connection", "Device went away")
                connection = .disconnected("Device not found")
            } else if connection != .waiting {
                // Came back from disconnect → return to waiting until we find it.
                connection = .waiting
            }
        } catch {
            self.device = nil
            peaks = .empty
            peaksHeld = .empty
            if connection != .disconnected("\(error)") {
                logEvent(.error, "Connection", "Open device failed: \(error)")
            }
            connection = .disconnected("\(error)")
        }
    }

    /// Returns true if the IOKit error code looks like a device that's gone
    /// (unplugged, hung, or otherwise un-talkable to).  Anything else is
    /// treated as a transient that we'll just retry.
    private static func isDisconnectError(_ err: Swift.Error) -> Bool {
        guard let e = err as? ScarlettError,
              case let .ioReturn(_, code) = e else { return false }
        return code == kIOReturnNoDevice
            || code == kIOReturnNotAttached
            || code == kIOReturnNotResponding
            || code == kIOReturnAborted
    }

    // MARK: - Event log

    func logEvent(_ severity: DeviceEvent.Severity, _ category: String, _ message: String) {
        let event = DeviceEvent(timestamp: Date(), severity: severity,
                                category: category, message: message)
        deviceEvents.insert(event, at: 0)
        if deviceEvents.count > maxEvents { deviceEvents.removeLast() }
    }

    func clearDeviceEvents() { deviceEvents = [] }

    // MARK: - Core Audio device presence

    /// Listen for the Scarlett appearing in or disappearing from Core Audio's
    /// device list. Independent from USB polling — even if USB transfers keep
    /// succeeding, this catches cases where macOS's audio HAL drops the
    /// device (or it shows up after a hot-plug).
    private func installCoreAudioListener() {
        guard !coreAudioListenerInstalled else { return }
        coreAudioListenerInstalled = true
        lastCoreAudioPresence = Self.scarlettPresentInCoreAudio()

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let present = Self.scarlettPresentInCoreAudio()
            Task { @MainActor in
                guard present != self.lastCoreAudioPresence else { return }
                self.lastCoreAudioPresence = present
                if present {
                    self.logEvent(.info, "Core Audio",
                                  "Scarlett visible to Core Audio")
                    // Device just appeared — kick a connect attempt so we
                    // don't wait the full 2 s for the polling loop's retry.
                    if !self.isConnected { self.attemptConnect() }
                } else {
                    self.logEvent(.warning, "Core Audio",
                                  "Scarlett disappeared from Core Audio device list")
                    if self.isConnected {
                        self.device = nil
                        self.connection = .disconnected("Removed from Core Audio")
                        self.peaks = .empty
                        self.peaksHeld = .empty
                    }
                }
            }
        }
        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, DispatchQueue.main, listener
        )
    }

    private static func scarlettPresentInCoreAudio() -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr, size > 0 else { return false }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
        ) == noErr else { return false }
        return ids.contains { deviceNameContainsScarlett($0) }
    }

    private static func deviceNameContainsScarlett(_ id: AudioDeviceID) -> Bool {
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let kr = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &size, ptr)
        }
        guard kr == noErr, let cfName = name?.takeRetainedValue() as String? else {
            return false
        }
        return cfName.lowercased().contains("scarlett")
    }

    // MARK: - UserDefaults persistence
    //
    // We only persist the values that aren't reliably readable from the
    // device — namely the output routing (firmware bug: GETs return 00 00
    // regardless of what was SET, see memory: project-routing-get-unreliable)
    // and the user's last-selected matrix bus tab (small UX win).
    //
    // Everything else (gains, mutes, atten, clock, etc.) is reliably read on
    // launch via refreshFromDevice and doesn't need to be saved.

    private static let routesKey            = "scarlett.routes.v1"
    private static let busTabKey            = "scarlett.selectedBus.v1"
    private static let matrixKey            = "scarlett.matrix.v1"
    private static let presetsKey           = "scarlett.presets.v1"
    private static let captureRoutesKey     = "scarlett.captureRoutes.v1"
    private static let monitorMonoKey       = "scarlett.monitorMono.v1"
    private static let firstLaunchDoneKey   = "scarlett.firstLaunchCompleted.v1"

    private struct PersistedMatrix: Codable {
        var levels: [[Double]]      // 18 × busPairCount, per-channel-per-pair
        var pans: [[Double]]        // 18 × busPairCount
        var mutes: [Bool]           // 18, per-channel
        var solos: [Bool]           // 18, per-channel
        var sources: [UInt8]        // 18, SignalSource.rawValue per channel
        var names: [String]         // 18
        var linkedLefts: [Int]      // left-channel indices of linked pairs
    }

    private func loadPersistedState() {
        let defaults = UserDefaults.standard

        // Routes — re-push to device so it actually honors them.
        if let data = defaults.data(forKey: Self.routesKey),
           let dict = try? JSONDecoder().decode([UInt16: UInt8].self, from: data) {
            for (wValue, sourceByte) in dict {
                routes[Int(wValue)] = sourceByte
                if let dev = device,
                   let output = dev.profile.physicalOutputs.first(where: { $0.wValue == wValue }) {
                    writeAsync { try? dev.setPhysicalRouteSource(output, sourceByte: sourceByte) }
                }
            }
        }

        // Capture routes — load from UserDefaults but do NOT push at launch.
        // Push only happens when the user actively changes one in the UI.
        // The device retains capture routing across power cycles, so the
        // first launch after a clean state will have the device's factory
        // defaults active (Analog/SPDIF → DAW captures) which is fine.
        if let data = defaults.data(forKey: Self.captureRoutesKey),
           let dict = try? JSONDecoder().decode([UInt16: UInt8].self, from: data) {
            for (ch, sourceByte) in dict {
                captureRoutes[Int(ch)] = sourceByte
            }
        }

        // Monitor Mono — load from UserDefaults but again do NOT push.  The
        // device remembers this across power cycles too.
        monitorMono = defaults.bool(forKey: Self.monitorMonoKey)

        // Selected bus tab — persisted as a plain UInt8 index (0..mixBusCount).
        if let raw = defaults.object(forKey: Self.busTabKey) as? UInt8,
           let p = device?.profile,
           raw < UInt8(p.mixBusCount) {
            selectedBusIndex = Int(raw)
        }

        // Matrix state: mute/solo/names/links/sources/levels/pans.
        //
        // Saved level + pan are the authoritative source — we re-push every
        // cell to the device after loading so the hardware reflects what
        // the UI says regardless of what state the device booted in.
        if let data = defaults.data(forKey: Self.matrixKey),
           let m = try? JSONDecoder().decode(PersistedMatrix.self, from: data),
           m.levels.count == 18, m.levels.allSatisfy({ $0.count >= 3 }),
           m.pans.count   == 18, m.pans.allSatisfy({ $0.count >= 3 }),
           m.mutes.count  == 18, m.solos.count == 18,
           m.sources.count == 18, m.names.count == 18
        {
            mixerLevels = m.levels.map { $0 + Array(repeating: 0, count: max(0, 4 - $0.count)) }
            mixerPans = m.pans.map { $0 + Array(repeating: 0, count: max(0, 4 - $0.count)) }
            mixerMutes = m.mutes
            mixerSolos = m.solos
            mixerNames = m.names
            linkedPairs = Set(m.linkedLefts)
            for ch in 0..<18 {
                mixerSources[ch] = m.sources[ch]
            }
            if let p = device?.profile {
                for ch in 0..<18 {
                    for bus in 0..<p.mixBusCount {
                        pushCellGainRaw(channel: ch, busIndex: bus)
                    }
                }
            }
        }

        // Presets list
        if let data = defaults.data(forKey: Self.presetsKey),
           let decoded = try? JSONDecoder().decode([ScarlettPreset].self, from: data) {
            presets = decoded
        }

        // First-launch detection: ask the user what to do.  We do NOT
        // auto-apply defaults — the device retains its full DSP state in
        // non-volatile flash across power cycles, and silently
        // overwriting that on first launch could wipe a setup the user
        // built with another tool (the original MixControl on older
        // macOS, for instance).  Instead, surface a choice via
        // `showFirstLaunchPrompt`; ContentView will present an alert
        // when the device is connected.
        if !defaults.bool(forKey: Self.firstLaunchDoneKey) {
            showFirstLaunchPrompt = true
        }
    }

    /// Called when the user picks "Apply defaults" from the first-launch
    /// prompt.  Marks the prompt as resolved either way.
    func userCompleteFirstLaunch(applyDefaults: Bool) {
        if applyDefaults {
            userResetRoutingAndMatrix()
        }
        UserDefaults.standard.set(true, forKey: Self.firstLaunchDoneKey)
        showFirstLaunchPrompt = false
    }

    private func saveRoutes() {
        let dict = Dictionary(uniqueKeysWithValues:
            routes.map { (UInt16($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.routesKey)
        }
    }

    private func saveCaptureRoutes() {
        let dict = Dictionary(uniqueKeysWithValues:
            captureRoutes.map { (UInt16($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.captureRoutesKey)
        }
    }

    private func saveMonitorMono() {
        UserDefaults.standard.set(monitorMono, forKey: Self.monitorMonoKey)
    }

    private func saveSelectedBus() {
        UserDefaults.standard.set(UInt8(selectedBusIndex), forKey: Self.busTabKey)
    }

    private func saveMatrix() {
        let m = PersistedMatrix(
            levels: mixerLevels,
            pans: mixerPans,
            mutes: mixerMutes,
            solos: mixerSolos,
            sources: mixerSources,
            names: mixerNames,
            linkedLefts: Array(linkedPairs)
        )
        if let data = try? JSONEncoder().encode(m) {
            UserDefaults.standard.set(data, forKey: Self.matrixKey)
        }
    }

    func savePresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.presetsKey)
        }
    }

    /// User-facing wrapper around `refreshFromDevice` — re-reads the
    /// device's matrix state into the view model and persists it.  Useful
    /// when another tool (or a power-cycle) has changed the device's
    /// flash and the UI is now out of sync.  Routing GETs always return
    /// 00 00 on the 1st-gen 8i6, so routes themselves aren't refreshed —
    /// only matrix sources / cell gains.
    func userLoadFromDevice() {
        guard device != nil else { return }
        refreshFromDevice()
        saveMatrix()
        logEvent(.info, "Refresh", "Matrix state reloaded from device")
    }

    /// Read all controls' current state from the device and update the
    /// view-model fields. Called on launch; can be called again to resync
    /// (e.g. after MixControl on Windows changed something out from under us).
    func refreshFromDevice() {
        guard let dev = device else { return }
        // Individual failures are swallowed — we keep the previously-stored
        // value for that field and continue. If everything fails the
        // connectionError will already have been raised by an earlier call.
        if let v = try? dev.getClockSource()              { clock = v }
        if let v = try? dev.getSampleRate()               { sampleRate = v }
        if let v = try? dev.getSyncLocked()               { syncLocked = v }
        if let v = try? dev.getImpedance(channel: 0)      { impedance1 = v }
        if let v = try? dev.getImpedance(channel: 1)      { impedance2 = v }
        if let v = try? dev.getHiLoGain(channel: 3)       { hi3 = v }
        if let v = try? dev.getHiLoGain(channel: 4)       { hi4 = v }
        if let v = try? dev.getMute(.master)              { masterMuted = v }
        if let v = try? dev.getMute(.monitorLeft)         { monitorLMuted = v }
        if let v = try? dev.getMute(.monitorRight)        { monitorRMuted = v }
        if let v = try? dev.getMute(.phonesLeft)          { phonesLMuted = v }
        if let v = try? dev.getMute(.phonesRight)         { phonesRMuted = v }
        // Use the average of L/R for the mono "Monitor" / "Phones" sliders.
        if let l = try? dev.getAttenuation(.monitorLeft),
           let r = try? dev.getAttenuation(.monitorRight) { monitorAtten = (l + r) / 2 }
        if let l = try? dev.getAttenuation(.phonesLeft),
           let r = try? dev.getAttenuation(.phonesRight)  { phonesAtten = (l + r) / 2 }
        // Routing GETs are still not trustworthy: byte 0x00 decodes to
        // .daw1, which is also what we'd get from a "null" 00 00 response.
        // We can't distinguish "device says DAW 1" from "device says
        // nothing" with a single read. Rely on UserDefaults to restore the
        // user's last routing — that's what loadPersistedState() does.
        // (A future protocol-fluency improvement: send a SET, read back, and
        // only trust GETs if the round-trip works.)

        // Matrix mixer reads correctly: 18 source reads + 18*6 = 108 gain
        // reads.  We pull them all into a local [[Double]] just long enough
        // to derive the user-facing level + pan model — there's no separate
        // persistent gains field.
        let mixBusCount = dev.profile.mixBusCount
        var snapshotGains: [[Double]] = Array(repeating: Array(repeating: 0, count: mixBusCount),
                                              count: 18)
        for ch in 0..<18 {
            if let v = try? dev.getMixerSourceByte(channel: ch) {
                mixerSources[ch] = v
            }
            for busIdx in 0..<mixBusCount {
                if let v = try? dev.getMixerGainRaw(channel: ch, busIndex: busIdx) {
                    snapshotGains[ch][busIdx] = v
                }
            }
        }
        for ch in 0..<18 {
            for pair in 0..<mixBusCount / 2 {
                let (level, pan) = Self.deriveLevelAndPan(
                    left:  snapshotGains[ch][pair * 2],
                    right: snapshotGains[ch][pair * 2 + 1]
                )
                mixerLevels[ch][pair] = level
                mixerPans[ch][pair] = pan
            }
        }
    }

    // MARK: - Meter polling

    func startMeterPolling() {
        Task { @MainActor [weak self] in
            var lastTick = Date()
            while !Task.isCancelled {
                guard let self else { return }

                // Not connected → periodically retry opening the device.
                guard let dev = self.device, self.isConnected else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.attemptConnect()
                    lastTick = Date()
                    continue
                }

                // Keep polling whenever the window is visible on screen —
                // even if our app isn't the frontmost — so a user can park
                // the meter window behind something else and still watch it.
                // Only back off when the window is genuinely hidden:
                // minimised to dock, or the app itself hidden (Cmd+H).
                let windowVisible = NSApp.windows.contains { win in
                    win.occlusionState.contains(.visible) && !win.isMiniaturized
                }
                if NSApp.isHidden || !windowVisible {
                    try? await Task.sleep(nanoseconds: 500_000_000)   // 2 Hz
                    lastTick = Date()
                    continue
                }
                let now = Date()
                let elapsed = now.timeIntervalSince(lastTick)
                lastTick = now
                let decay = self.peakDecayDbPerSecond * elapsed

                do {
                    let p = try dev.readPeaks()
                    if self.metersStale {
                        self.logEvent(.info, "USB", "Meter polling resumed")
                    }
                    self.peaks = p
                    // (no need to re-assign `connection` here — by the time
                    // we're successfully reading peaks we're already in
                    // .connected; `attemptConnect()` sets it.)

                    // Mutate in-place rather than allocating 6 new arrays per
                    // poll via zip+map. CoW means a single backing-store copy
                    // at most, and the SwiftUI @Observable notification fires
                    // once when we re-assign each top-level field.
                    var held = self.peaksHeld
                    var max_ = self.peaksMax
                    for i in 0..<held.inputs.count { held.inputs[i] = max(p.inputs[i], held.inputs[i] - decay) }
                    for i in 0..<held.daw.count    { held.daw[i]    = max(p.daw[i],    held.daw[i]    - decay) }
                    for i in 0..<held.mixer.count  { held.mixer[i]  = max(p.mixer[i],  held.mixer[i]  - decay) }
                    for i in 0..<max_.inputs.count { max_.inputs[i] = max(p.inputs[i], max_.inputs[i]) }
                    for i in 0..<max_.daw.count    { max_.daw[i]    = max(p.daw[i],    max_.daw[i]) }
                    for i in 0..<max_.mixer.count  { max_.mixer[i]  = max(p.mixer[i],  max_.mixer[i]) }
                    self.peaksHeld = held
                    self.peaksMax  = max_

                    self.metersStale = false
                } catch {
                    if !self.metersStale {
                        self.logEvent(.warning, "USB", "Meter polling failed: \(error)")
                    }
                    self.metersStale = true
                    if Self.isDisconnectError(error) {
                        self.logEvent(.error, "Connection", "Device disconnected during transfer")
                        self.device = nil
                        self.connection = .disconnected("\(error)")
                        self.peaks = .empty
                        self.peaksHeld = .empty
                        continue
                    }
                }

                // Re-read sync status roughly every second so the indicator
                // catches clock drops without doing a USB transfer every tick.
                self.syncPollAccumulator += elapsed
                if self.syncPollAccumulator >= 1.0 {
                    self.syncPollAccumulator = 0
                    if let s = try? dev.getSyncLocked() {
                        if s != self.syncLocked {
                            self.logEvent(
                                s ? .info : .warning,
                                "Clock",
                                s ? "Clock locked" : "Clock lost lock"
                            )
                        }
                        self.syncLocked = s
                    }
                }

                // 83 ms ≈ 12 Hz. Each readPeaks() does 3 USB control transfers
                // (inputs/DAW/mixer) which aren't free on macOS — kernel
                // transitions ~1-5 ms each — so polling alone is most of our
                // idle CPU. 12 Hz still looks smooth and roughly halves CPU
                // vs the 20 Hz default we started with.
                try? await Task.sleep(nanoseconds: 83_000_000)
            }
        }
    }

    // MARK: - User actions (every public mutator goes through here so we
    // can ignore programmatic updates and surface errors uniformly)

    func userSetMonitorAtten(_ db: Double) {
        monitorAtten = db
        guard let dev = device else { return }
        writeAsync {
            try? dev.setAttenuation(.monitorLeft,  db: db)
            try? dev.setAttenuation(.monitorRight, db: db)
        }
    }

    func userSetPhonesAtten(_ db: Double) {
        phonesAtten = db
        guard let dev = device else { return }
        writeAsync {
            try? dev.setAttenuation(.phonesLeft,  db: db)
            try? dev.setAttenuation(.phonesRight, db: db)
        }
    }

    func userSetMasterMute(_ muted: Bool) {
        masterMuted = muted
        guard let dev = device else { return }
        writeAsync { try? dev.setMute(.master, muted: muted) }
    }

    // MARK: - Input switches

    func userSetImpedance(channel: Int, mode: Impedance) {
        if channel == 1 { impedance1 = mode } else if channel == 2 { impedance2 = mode }
        guard let dev = device else { return }
        writeAsync { try? dev.setImpedance(channel: channel - 1, mode: mode) }
    }

    func userSetHiLo(channel: Int, hi: Bool) {
        if channel == 3 { hi3 = hi } else if channel == 4 { hi4 = hi }
        guard let dev = device else { return }
        writeAsync { try? dev.setHiLoGain(channel: channel, hi: hi) }
    }

    // MARK: - Routing

    func userSetRoute(wValue: Int, sourceByte: UInt8) {
        routes[wValue] = sourceByte
        saveRoutes()
        guard let dev = device,
              let output = dev.profile.physicalOutputs.first(where: { $0.wValue == UInt16(wValue) })
        else { return }
        writeAsync { try? dev.setPhysicalRouteSource(output, sourceByte: sourceByte) }
    }

    /// Set what the DAW sees on USB capture channel `channel`.
    /// Persists and pushes to the device.
    func userSetCaptureRoute(channel: Int, sourceByte: UInt8) {
        captureRoutes[channel] = sourceByte
        saveCaptureRoutes()
        guard let dev = device else { return }
        writeAsync { try? dev.setCaptureRouteSource(channel: channel, sourceByte: sourceByte) }
    }

    // MARK: - Monitor mono

    func userSetMonitorMono(_ enabled: Bool) {
        monitorMono = enabled
        saveMonitorMono()
        guard let dev = device else { return }
        // MixControl's setMonMono loops over 5 output pairs, writing the
        // user's desired value to pair 1 (the active one for Monitor) and
        // 0 to the rest.  We replicate the full sequence with a small
        // inter-write delay because the 1st-gen 8i6's firmware stalls if
        // it gets 5 control transfers in rapid succession.
        writeAsync {
            for pair in 1...5 {
                let value = (pair == 1) ? enabled : false
                try? dev.setMonitorMono(pair: pair, enabled: value)
                Thread.sleep(forTimeInterval: 0.02)   // 20 ms between writes
            }
        }
        logEvent(.info, "Mono", enabled ? "Monitor mono on" : "Monitor mono off")
    }


    // MARK: - Device config

    func userSetClock(_ src: ClockSource) {
        clock = src
        guard let dev = device else { return }
        writeAsync { try? dev.setClockSource(src) }
    }

    func userSetSampleRate(_ hz: UInt32) {
        sampleRate = hz
        guard let dev = device else { return }
        writeAsync { try? dev.setSampleRate(hz) }
    }

    // MARK: - Matrix mixer

    /// Computes the gain we actually want the device to apply for a cell,
    /// taking mute and solo into account.
    /// - Mute: cell is silenced (-128 dB).
    /// - Solo in bus: any cell soloed in this bus → all non-soloed cells in
    ///   the same bus are silenced.
    /// - Otherwise: derived from `mixerLevels` + `mixerPans` for the bus pair
    ///   this bus belongs to.
    func effectiveGain(channel: Int, busIdx: Int) -> Double {
        // Per-channel mute / solo: a single boolean per channel applies
        // to *every* bus this channel feeds.
        if mixerMutes[channel] { return -128 }
        let soloActive = mixerSolos.contains(true)
        if soloActive && !mixerSolos[channel] { return -128 }
        let pair = busIdx / 2
        let isLeft = busIdx % 2 == 0
        return Self.cellGain(level: mixerLevels[channel][pair],
                             pan: mixerPans[channel][pair],
                             isLeft: isLeft)
    }

    // MARK: - Level + pan math

    /// Convert a (level, pan, side) triple into the per-cell gain that the
    /// device's matrix mixer will use.  "Amp-style" pan law: at center both
    /// sides get the full level; panning hard to one side reduces the other
    /// to -∞ without attenuating the chosen side.
    static func cellGain(level: Double, pan: Double, isLeft: Bool) -> Double {
        let clamped = max(-1, min(1, pan))
        let factor: Double = isLeft
            ? (clamped <= 0 ? 1.0 : 1.0 - clamped)
            : (clamped >= 0 ? 1.0 : 1.0 + clamped)
        if factor <= 0.0001 { return -128 }
        return level + 20 * log10(factor)
    }

    /// Inverse of `cellGain` — recover a (level, pan) pair from the device's
    /// current L and R cell gains.  Used to migrate the matrix on launch.
    static func deriveLevelAndPan(left: Double, right: Double) -> (level: Double, pan: Double) {
        let safeL = left.isFinite  ? max(-128, left)  : -128
        let safeR = right.isFinite ? max(-128, right) : -128
        if abs(safeL - safeR) < 0.5 {
            return (max(safeL, safeR), 0)
        }
        if safeL > safeR {
            let level = safeL
            // pan in [-1, 0]: gain_R = level + 20·log10(1 + pan)
            let pan = pow(10, (safeR - level) / 20) - 1
            return (level, max(-1, pan))
        } else {
            let level = safeR
            // pan in (0, 1]: gain_L = level + 20·log10(1 - pan)
            let pan = 1 - pow(10, (safeL - level) / 20)
            return (level, min(1, pan))
        }
    }

    // Kept as static thunks for source compatibility with existing callers —
    // they just defer to MixBus's own computed properties.
    static func pairIndex(of bus: MixBus) -> Int { bus.stereoPairIndex ?? 0 }
    static func isLeftSide(of bus: MixBus) -> Bool { bus.isLeftOfPair }

    func userSetMixerSource(channel: Int, sourceByte: UInt8) {
        guard (0..<18).contains(channel) else { return }
        mixerSources[channel] = sourceByte
        guard let dev = device else { return }
        writeAsync { try? dev.setMixerSourceByte(channel: channel, sourceByte: sourceByte) }
    }

    // MARK: - Pinned DAW return
    //
    // Matrix channels 14 & 15 are reserved as the "DAW return" controlled by
    // `PinnedDawStrip` (the column pinned to the left of the matrix). They
    // are sourced from DAW 1 and DAW 2 respectively, hard-panned to opposite
    // sides of every bus pair, and marked as a linked stereo pair so fader /
    // mute changes on one mirror to the other automatically.
    //
    // Re-asserted on every successful connect — if the device was power-cycled
    // or somebody else changed those channels, we put them back the way the
    // UI expects.

    /// Channel indices of the pinned DAW pair.
    public static let pinnedDawLeftChannel: Int  = 14
    public static let pinnedDawRightChannel: Int = 15

    private func ensurePinnedDawChannels() {
        let l = Self.pinnedDawLeftChannel
        let r = Self.pinnedDawRightChannel

        // Per x42's docs, the device refuses to double-assign a source: if
        // DAW 1 is already wired to (say) ch 0 from the factory default, a
        // bare `setMixerSource(14, .daw1)` is silently rejected and ch 14
        // stays pointed at whatever it was sourced from before.  We have to
        // disconnect the existing owner with `0xff` (Off) first.
        assignPinnedSource(channel: l, sourceByte: 0x00)  // DAW 1
        assignPinnedSource(channel: r, sourceByte: 0x01)  // DAW 2

        let busPairs = min((device?.profile.mixBusCount ?? 6) / 2, mixerPans[l].count)
        for pair in 0..<busPairs {
            if mixerPans[l][pair] != -1 { userSetMixerPan(channel: l, pair: pair, pan: -1) }
            if mixerPans[r][pair] !=  1 { userSetMixerPan(channel: r, pair: pair, pan:  1) }
        }
        if !linkedPairs.contains(l) {
            linkedPairs.insert(l)
            saveMatrix()
        }
    }

    /// Helper for `ensurePinnedDawChannels`: claim a specific source for one
    /// channel, disconnecting it from any other channel that currently holds
    /// it.  Skips work if the target already has the desired source.
    private func assignPinnedSource(channel target: Int, sourceByte desired: UInt8) {
        guard (0..<18).contains(target) else { return }
        if mixerSources[target] == desired { return }

        // Disconnect any other channel that currently has this source —
        // otherwise the device won't reassign it to us.
        for ch in 0..<18 where ch != target && mixerSources[ch] == desired {
            userSetMixerSource(channel: ch, sourceByte: 0xff)
        }

        // Now claim it on the target.  These writes are queued on the same
        // serial USB queue, so the disconnect above lands before the new
        // assignment hits the device.
        userSetMixerSource(channel: target, sourceByte: desired)
    }

    // MARK: - Stereo link

    /// Fixed even/odd partner index for a given channel.
    private static func leftOfPair(_ ch: Int) -> Int { ch - (ch % 2) }

    func isLinked(_ ch: Int) -> Bool {
        linkedPairs.contains(Self.leftOfPair(ch))
    }

    func linkedPartner(_ ch: Int) -> Int? {
        guard isLinked(ch) else { return nil }
        return ch % 2 == 0 ? ch + 1 : ch - 1
    }

    func userToggleLink(channel ch: Int) {
        let left = Self.leftOfPair(ch)
        if linkedPairs.contains(left) {
            linkedPairs.remove(left)
            for pair in 0..<busPairCount {
                mixerPans[left][pair] = 0
                mixerPans[left + 1][pair] = 0
                pushBusPair(channel: left, pair: pair)
            }
        } else {
            linkedPairs.insert(left)
            for pair in 0..<busPairCount {
                mixerPans[left][pair] = -1
                mixerPans[left + 1][pair] = 1
                pushBusPair(channel: left, pair: pair)
            }
        }
        saveMatrix()
    }

    /// Number of stereo bus pairs (mixBusCount / 2).  Profile-driven so
    /// it's 3 on 8i6/18i6 and 4 on 18i8 without hardcoding.
    private var busPairCount: Int { (device?.profile.mixBusCount ?? 6) / 2 }

    /// Set the channel-level fader for one stereo bus pair. Pushes both cells
    /// (L and R) in that pair to the device.  If the channel is in a linked
    /// stereo pair, the partner's level for the same pair moves with it.
    func userSetMixerLevel(channel: Int, pair: Int, level: Double) {
        guard (0..<18).contains(channel), (0..<busPairCount).contains(pair) else { return }
        mixerLevels[channel][pair] = level
        pushBusPair(channel: channel, pair: pair)
        if let partner = linkedPartner(channel) {
            mixerLevels[partner][pair] = level
            pushBusPair(channel: partner, pair: pair)
        }
        saveMatrix()
    }

    /// Set the L↔R pan for one stereo bus pair on one channel. Snaps to
    /// center when within ±0.04.
    func userSetMixerPan(channel: Int, pair: Int, pan: Double) {
        guard (0..<18).contains(channel), (0..<busPairCount).contains(pair) else { return }
        let snapped = abs(pan) < 0.04 ? 0 : max(-1, min(1, pan))
        mixerPans[channel][pair] = snapped
        pushBusPair(channel: channel, pair: pair)
        if let partner = linkedPartner(channel) {
            let partnerPan = -snapped
            mixerPans[partner][pair] = partnerPan
            pushBusPair(channel: partner, pair: pair)
        }
        saveMatrix()
    }

    private func pushBusPair(channel: Int, pair: Int) {
        let leftIdx = pair * 2
        let rightIdx = pair * 2 + 1
        guard let p = device?.profile, leftIdx < p.mixBusCount, rightIdx < p.mixBusCount else { return }
        pushCellGainRaw(channel: channel, busIndex: leftIdx)
        pushCellGainRaw(channel: channel, busIndex: rightIdx)
    }

    func userSetChannelName(channel: Int, name: String) {
        guard (0..<18).contains(channel) else { return }
        mixerNames[channel] = name
        saveMatrix()
    }

    /// Reset the all-time max peaks for every source.
    func clearMaxPeaks() {
        peaksMax = .empty
    }

    /// Reset a single source's max-peak track (clicking "Mx" on a strip).
    func clearMaxPeak(forByte byte: UInt8) {
        guard let profile = device?.profile,
              let slot = profile.peakSlot(forByte: byte) else { return }
        switch slot {
        case .input(let i):  if peaksMax.inputs.indices.contains(i) { peaksMax.inputs[i] = -.infinity }
        case .daw(let i):    if peaksMax.daw.indices.contains(i)    { peaksMax.daw[i]    = -.infinity }
        case .mixer(let i):  if peaksMax.mixer.indices.contains(i)  { peaksMax.mixer[i]  = -.infinity }
        }
    }

    // MARK: - Presets

    func userSavePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let snapshot = ScarlettPreset(
            id: UUID(),
            name: trimmed,
            createdAt: Date(),
            routes: Dictionary(uniqueKeysWithValues:
                routes.map { (UInt16($0.key), $0.value) }),
            mixerSources: mixerSources,
            mixerLevels: mixerLevels,
            mixerPans: mixerPans,
            mixerMutes: mixerMutes,
            mixerSolos: mixerSolos,
            mixerNames: mixerNames,
            linkedLefts: Array(linkedPairs),
            selectedBus: UInt8(selectedBusIndex)
        )

        // Replace any preset with the same name; otherwise append.
        if let idx = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[idx] = snapshot
        } else {
            presets.append(snapshot)
        }
        savePresets()
    }

    func userLoadPreset(_ preset: ScarlettPreset) {
        guard let dev = device, let p = device?.profile else { return }

        // Routes
        for (routeRaw, busByte) in preset.routes {
            routes[Int(routeRaw)] = busByte
            if let output = p.physicalOutputs.first(where: { $0.wValue == routeRaw }) {
                writeAsync { try? dev.setPhysicalRouteSource(output, sourceByte: busByte) }
            }
        }
        saveRoutes()

        // Matrix sources
        if preset.mixerSources.count == 18 {
            for ch in 0..<18 {
                let byte = preset.mixerSources[ch]
                mixerSources[ch] = byte
                writeAsync { try? dev.setMixerSourceByte(channel: ch, sourceByte: byte) }
            }
        }

        // Apply mutes / solos / levels / pans / names / links before
        // pushing cells so `effectiveGain` sees the right state.
        if preset.mixerMutes.count == 18 { mixerMutes = preset.mixerMutes }
        if preset.mixerSolos.count == 18 { mixerSolos = preset.mixerSolos }
        if preset.mixerLevels.count == 18, preset.mixerLevels.allSatisfy({ $0.count >= 3 }) {
            mixerLevels = preset.mixerLevels.map { $0 + Array(repeating: 0, count: max(0, 4 - $0.count)) }
        }
        if preset.mixerPans.count == 18, preset.mixerPans.allSatisfy({ $0.count >= 3 }) {
            mixerPans = preset.mixerPans.map { $0 + Array(repeating: 0, count: max(0, 4 - $0.count)) }
        }
        if preset.mixerNames.count == 18 { mixerNames = preset.mixerNames }
        linkedPairs = Set(preset.linkedLefts)

        guard let p = device?.profile else { return }
        for ch in 0..<18 {
            for bus in 0..<p.mixBusCount {
                pushCellGainRaw(channel: ch, busIndex: bus)
            }
        }

        if preset.selectedBus < UInt8(p.mixBusCount) {
            selectedBusIndex = Int(preset.selectedBus)
        }

        saveMatrix()
    }

    func userDeletePreset(_ preset: ScarlettPreset) {
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }

    /// Build a snapshot of the current state in `ScarlettPreset` form.  The
    /// snapshot is identical in shape to what `userSavePreset` writes to
    /// the in-app list; the difference is just where it's persisted.
    func currentSnapshot(named name: String) -> ScarlettPreset {
        ScarlettPreset(
            id: UUID(),
            name: name,
            createdAt: Date(),
            routes: Dictionary(uniqueKeysWithValues:
                routes.map { (UInt16($0.key), $0.value) }),
            mixerSources: mixerSources,
            mixerLevels: mixerLevels,
            mixerPans: mixerPans,
            mixerMutes: mixerMutes,
            mixerSolos: mixerSolos,
            mixerNames: mixerNames,
            linkedLefts: Array(linkedPairs),
            selectedBus: UInt8(selectedBusIndex)
        )
    }

    /// Export the current state to a snapshot file at the given URL.  The file
    /// format is JSON-encoded `ScarlettPreset` for cross-compatibility with
    /// the in-app preset list (you can save a file, then load it back as a
    /// preset and vice versa).
    func userExportSnapshot(to url: URL) throws {
        let snapshot = currentSnapshot(named: url.deletingPathExtension().lastPathComponent)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url)
        logEvent(.info, "Export", "Exported snapshot to \(url.lastPathComponent)")
    }

    /// Import a snapshot file from the given URL and apply it
    /// (routes + matrix + sources) the same way `userLoadPreset` does.
    func userImportSnapshot(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let preset = try JSONDecoder().decode(ScarlettPreset.self, from: data)
        userLoadPreset(preset)
        logEvent(.info, "Import", "Imported snapshot \(url.lastPathComponent)")
    }

    // MARK: - Reset

    /// Apply a sensible "factory" default config:
    /// - Outputs (Monitor L/R + Phones L/R) routed direct from DAW 1/DAW 2 so
    ///   Mac audio is audible immediately.  S/PDIF outputs default Off.
    /// - Matrix mixer cleared: all levels 0 dB, all pans centered, no mutes/
    ///   solos/links.
    /// - Pinned DAW return (ch 14 + 15) re-established with DAW 1/2 sources
    ///   and hard L/R pans — ready to be brought up to mix DAW back through
    ///   the matrix if the user wants to.
    /// Hardware switches (impedance / hi-lo), clock, sample rate and master
    /// output attenuation are left alone.
    /// Push default routes (Monitor + Phones ← Mix M1) to the device.
    /// Called on every connect so the new routing takes effect regardless
    /// of old UserDefaults or flash state.
    func pushDefaultRoutes() {
        guard let dev = device else { return }
        let mixBuses = dev.profile.mixBusSources
        let m1 = mixBuses.count > 0 ? mixBuses[0].byte : 0xff
        let m2 = mixBuses.count > 1 ? mixBuses[1].byte : m1
        for output in dev.profile.physicalOutputs {
            let src: UInt8 = output.isLeft ? m1 : m2
            routes[Int(output.wValue)] = src
            writeAsync { try? dev.setPhysicalRouteSource(output, sourceByte: src) }
        }
        saveRoutes()
    }

    /// Push all output attenuators to 0 dB (unity gain).  Called on every
    /// connect because the device's flash may have atten at -inf from a
    /// previous session with MixControl or a factory reset.
    func pushDefaultAttenuation() {
        // Temporarily disabled — the 18i8 firmware brute-force was
        // disconnecting USB.  The device's factory flash may already
        // have output atten at 0 dB.  Revisit after probing the correct
        // register address for the 18i8's phones output.
    }

    func userResetRoutingAndMatrix() {
        guard let dev = device else { return }
        let mixBuses = dev.profile.mixBusSources
        let m1 = mixBuses.count > 0 ? mixBuses[0].byte : 0xff
        let m2 = mixBuses.count > 1 ? mixBuses[1].byte : m1
        for output in dev.profile.physicalOutputs {
            let src: UInt8 = output.isLeft ? m1 : m2
            routes[Int(output.wValue)] = src
            writeAsync { try? dev.setPhysicalRouteSource(output, sourceByte: src) }
        }
        saveRoutes()

        // Reset matrix levels / pans / mutes / solos to defaults.
        mixerLevels = Array(repeating: Array(repeating: 0, count: 4), count: 18)
        mixerPans   = Array(repeating: Array(repeating: 0, count: 4), count: 18)
        mixerMutes  = Array(repeating: false, count: 18)
        mixerSolos  = Array(repeating: false, count: 18)
        linkedPairs = []

        // Reset matrix sources to a sensible default: wires profile's first
        // few analog + digital sources to the first 6 matrix channels.
        // First pass: clear everything on the device so reassignment can't
        // hit the firmware's "source already wired" silent rejection.
        for ch in 0..<18 {
            mixerSources[ch] = 0xff  // Off byte
            if let dev = device {
                writeAsync { try? dev.setMixerSourceByte(channel: ch, sourceByte: 0xff) }
            }
        }
        // Second pass: assign the real defaults using source bytes from the
        // connected profile (or a reasonable fallback for 8i6).
        let p = device?.profile ?? .scarlett8i6
        let defaultBytes: [UInt8] = {
            let analogs = p.sources.filter { $0.category == .analog }.prefix(4).map(\.byte)
            let digitals = p.sources.filter { $0.category == .digital }.prefix(2).map(\.byte)
            let offs = [UInt8](repeating: 0xff, count: 12)
            return Array((analogs + digitals + offs).prefix(18))
        }()
        for ch in 0..<6 {
            let byte = defaultBytes[ch]
            mixerSources[ch] = byte
            if byte != 0xff, let dev = device {
                writeAsync { try? dev.setMixerSourceByte(channel: ch, sourceByte: byte) }
            }
        }

        // Re-assert the pinned DAW return (Ch 14/15 → DAW 1/2, hard panned).
        ensurePinnedDawChannels()

        // Push every cell to the device with the new state.
        for ch in 0..<18 {
            for bus in 0..<p.mixBusCount {
                pushCellGainRaw(channel: ch, busIndex: bus)
            }
        }

        // Capture routes back to factory: first 4 analog + first 2 digital.
        captureRoutes.removeAll(keepingCapacity: true)
        let capAnalogs = p.sources.filter { $0.category == .analog }.prefix(4)
        let capDigitals = p.sources.filter { $0.category == .digital }.prefix(2)
        for (ch, sd) in capAnalogs.enumerated() {
            captureRoutes[ch] = sd.byte
        }
        for (ch, sd) in capDigitals.enumerated() {
            captureRoutes[4 + ch] = sd.byte
        }
        if let dev = device {
            for (ch, byte) in captureRoutes {
                writeAsync { try? dev.setCaptureRouteSource(channel: ch, sourceByte: byte) }
            }
        }
        saveCaptureRoutes()

        // Monitor mono off.
        if monitorMono {
            userSetMonitorMono(false)
        }

        saveMatrix()
        logEvent(.info, "Reset", "Default config applied (outputs routed M1/M2 stereo)")
    }

    /// Set the channel-wide mute directly (no toggle, no link propagation).
    /// Used by callers that drive multiple channels in concert (`PinnedDawStrip`).
    func userSetMixerMute(channel: Int, muted: Bool) {
        guard (0..<18).contains(channel) else { return }
        mixerMutes[channel] = muted
        pushAllCells(forChannel: channel)
        saveMatrix()
    }

    /// Toggle the channel-wide mute, mirroring to the linked partner.
    /// Affects every bus the channel feeds — that's the standard mixer
    /// UX (M = silence this channel everywhere).
    func userToggleMixerMute(channel: Int) {
        guard (0..<18).contains(channel) else { return }
        let newValue = !mixerMutes[channel]
        mixerMutes[channel] = newValue
        pushAllCells(forChannel: channel)
        if let partner = linkedPartner(channel) {
            mixerMutes[partner] = newValue
            pushAllCells(forChannel: partner)
        }
        saveMatrix()
    }

    /// Toggle the channel-wide solo, mirroring to the linked partner.
    /// Solo affects the gain of *every* channel on *every* bus (any
    /// non-soloed channel goes silent globally), so we re-push the
    /// entire 18 × N matrix.
    func userToggleMixerSolo(channel: Int) {
        guard (0..<18).contains(channel) else { return }
        let newValue = !mixerSolos[channel]
        mixerSolos[channel] = newValue
        if let partner = linkedPartner(channel) {
            mixerSolos[partner] = newValue
        }
        // Solo affects effectiveGain for every channel.  Re-push all cells.
        for ch in 0..<18 {
            pushAllCells(forChannel: ch)
        }
        saveMatrix()
    }

    /// Helper: push gain for `channel` to every mix bus.  Used when a
    /// channel-wide field (mute / solo) changes — every bus this
    /// channel feeds needs the new effective gain.
    private func pushAllCells(forChannel channel: Int) {
        guard let p = device?.profile else { return }
        for bus in 0..<p.mixBusCount {
            pushCellGainRaw(channel: channel, busIndex: bus)
        }
    }

    private func pushCellGainRaw(channel: Int, busIndex: Int) {
        guard let dev = device else { return }
        let db = effectiveGain(channel: channel, busIdx: busIndex)
        writeAsync { try? dev.setMixerGainRaw(channel: channel, busIndex: busIndex, db: db) }
    }

    // MARK: - Copy mix to another bus

    /// Replicate the per-channel settings from one mix bus to another:
    /// for every matrix channel, copy that channel's level/pan/mute/solo for
    /// the source pair to the destination pair (and the cell-gains for the
    /// source bus to the destination bus).  Useful for "make M3+M4 = M1+M2".
    ///
    /// `from` and `to` are the bus's stereo pair (0 = M1+M2, 1 = M3+M4,
    /// 2 = M5+M6, 3 = M7+M8 on devices that have 8 buses).
    func userCopyMixPair(from sourcePair: Int, to destPair: Int) {
        guard sourcePair != destPair,
              (0..<busPairCount).contains(sourcePair),
              (0..<busPairCount).contains(destPair) else { return }
        // Mute and solo are now channel-wide, so copying a pair only
        // copies the per-pair level + pan into the destination.
        for ch in 0..<18 {
            mixerLevels[ch][destPair] = mixerLevels[ch][sourcePair]
            mixerPans[ch][destPair]   = mixerPans[ch][sourcePair]
            pushBusPair(channel: ch, pair: destPair)
        }
        saveMatrix()
        let srcName = "Mix M\(sourcePair*2 + 1)+M\(sourcePair*2 + 2)"
        let dstName = "Mix M\(destPair*2 + 1)+M\(destPair*2 + 2)"
        logEvent(.info, "Copy", "Copied \(srcName) → \(dstName)")
    }

    // MARK: - Master section helpers

    func userToggleDim() {
        dimEnabled.toggle()
        guard let dev = device else { return }
        if dimEnabled {
            preDimMonitorAtten = monitorAtten
            let dimmed = max(-128, monitorAtten - 20)
            monitorAtten = dimmed
            writeAsync {
                try? dev.setAttenuation(.monitorLeft,  db: dimmed)
                try? dev.setAttenuation(.monitorRight, db: dimmed)
            }
        } else {
            let restore = preDimMonitorAtten
            monitorAtten = restore
            writeAsync {
                try? dev.setAttenuation(.monitorLeft,  db: restore)
                try? dev.setAttenuation(.monitorRight, db: restore)
            }
        }
    }

    func userSetSideMute(bus: SignalOut, muted: Bool) {
        switch bus {
        case .monitorLeft:  monitorLMuted = muted
        case .monitorRight: monitorRMuted = muted
        case .phonesLeft:   phonesLMuted  = muted
        case .phonesRight:  phonesRMuted  = muted
        default: return
        }
        guard let dev = device else { return }
        writeAsync { try? dev.setMute(bus, muted: muted) }
    }

    // MARK: - Save

    func saveToFlash() {
        guard let dev = device else { return }
        writeAsync { try? dev.saveSettingsToHardware() }
    }
}
