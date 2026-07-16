import Foundation

// Protocol constants and command functions for the Focusrite Scarlett 1st-gen
// family (8i6 / 18i6). Ported from x42's scarlettmixer.py
// (https://github.com/x42/scarlettmixer/blob/master/scarlettmixer.py).
//
// All commands target USB interface 0 (Audio Control) via endpoint 0.
// bmRequestType encoding handled by ScarlettDevice.controlOut/controlIn.

// MARK: - Enums

public enum Impedance: UInt8, CaseIterable, Identifiable {
    case line = 0, instrument = 1
    public var id: UInt8 { rawValue }
    public var displayName: String { self == .line ? "Line" : "Instrument" }
}

public enum ClockSource: UInt8, CaseIterable, Identifiable {
    case internalClock = 1, spdif = 2, adat = 3
    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .internalClock: return "Internal"
        case .spdif: return "S/PDIF"
        case .adat: return "ADAT"
        }
    }
}

/// Signal sources that can be connected to matrix-mixer inputs.
///
/// Byte values reverse-engineered from the original MixControl 1.10.6 binary
/// (`_USB14Tracker_IpSigTab`).  Both x42's 18i6 mapping AND Linux's
/// `s8i6_info`-derived mapping were wrong for S/PDIF — Linux had it right
/// for Analog though.
///
///   0x00..0x05 → DAW 1..6
///   0x06..0x0b → DAW 7..12 (exposed but not wired to USB; silent on a real
///                            8i6 unless paired with a different host)
///   0x0c..0x0f → Analog 1..4
///   0x12..0x13 → S/PDIF 1..2   (NOT 0x10..0x11 — Linux is wrong)
///   0xff       → Off
public enum SignalSource: UInt8, CaseIterable, Identifiable, Hashable {
    case off = 0xff
    case daw1 = 0x00, daw2 = 0x01, daw3 = 0x02, daw4 = 0x03, daw5 = 0x04, daw6 = 0x05
    case daw7 = 0x06, daw8 = 0x07, daw9 = 0x08, daw10 = 0x09, daw11 = 0x0a, daw12 = 0x0b
    case analog1 = 0x0c, analog2 = 0x0d, analog3 = 0x0e, analog4 = 0x0f
    case spdif1 = 0x12, spdif2 = 0x13

    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .off:     return "Off"
        case .daw1:    return "DAW 1"
        case .daw2:    return "DAW 2"
        case .daw3:    return "DAW 3"
        case .daw4:    return "DAW 4"
        case .daw5:    return "DAW 5"
        case .daw6:    return "DAW 6"
        case .daw7:    return "DAW 7"
        case .daw8:    return "DAW 8"
        case .daw9:    return "DAW 9"
        case .daw10:   return "DAW 10"
        case .daw11:   return "DAW 11"
        case .daw12:   return "DAW 12"
        case .analog1: return "Analog 1"
        case .analog2: return "Analog 2"
        case .analog3: return "Analog 3"
        case .analog4: return "Analog 4"
        case .spdif1:  return "S/PDIF 1"
        case .spdif2:  return "S/PDIF 2"
        }
    }

    /// Useful sources on a real 8i6 — drops the DAW 7-12 slots that aren't
    /// wired to USB output streams (selecting one produces silence).
    public static let availableOn8i6: [SignalSource] = [
        .off,
        .daw1, .daw2, .daw3, .daw4, .daw5, .daw6,
        .analog1, .analog2, .analog3, .analog4,
        .spdif1, .spdif2,
    ]
}

/// Sources for the router — superset of SignalSource plus the 6 matrix-mixer outputs.
///
/// Byte values reverse-engineered from the original MixControl 1.10.6 binary
/// (`_USB14Tracker_IpSigTab`).  Same table as SignalSource: anywhere a
/// source can be selected (matrix-channel input via `setMixerSource`, or
/// physical-output input via `setRouteSource`), it uses these bytes.
///
/// 8i6 mapping:
///   0x00..0x0b → DAW 1..12 (only 1..6 are wired to USB)
///   0x0c..0x0f → Analog 1..4
///   0x12..0x13 → S/PDIF 1..2
///   0x14..0x19 → Mix M1..M6 (MixControl calls these "FromMix1..6" — the
///                              matrix's own outputs, usable as a feed to a
///                              physical output via the router)
///   0xff       → Off
///
/// Both x42 AND Linux were wrong about Mix-bus AND SPDIF bytes for the 8i6.
/// Linux's `s8i6_info` is the `/* untested... */` table — empirically wrong.
/// x42 reverse-engineered the 18i6, where the byte values differ.
public enum MixBus: UInt8, CaseIterable, Identifiable, Hashable {
    case off = 0xff
    case daw1 = 0x00, daw2 = 0x01, daw3 = 0x02, daw4 = 0x03, daw5 = 0x04, daw6 = 0x05
    case daw7 = 0x06, daw8 = 0x07, daw9 = 0x08, daw10 = 0x09, daw11 = 0x0a, daw12 = 0x0b
    case analog1 = 0x0c, analog2 = 0x0d, analog3 = 0x0e, analog4 = 0x0f
    case spdif1 = 0x12, spdif2 = 0x13
    case m1 = 0x14, m2 = 0x15, m3 = 0x16, m4 = 0x17, m5 = 0x18, m6 = 0x19

    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .off:     return "Off"
        case .daw1:    return "DAW 1"
        case .daw2:    return "DAW 2"
        case .daw3:    return "DAW 3"
        case .daw4:    return "DAW 4"
        case .daw5:    return "DAW 5"
        case .daw6:    return "DAW 6"
        case .daw7:    return "DAW 7"
        case .daw8:    return "DAW 8"
        case .daw9:    return "DAW 9"
        case .daw10:   return "DAW 10"
        case .daw11:   return "DAW 11"
        case .daw12:   return "DAW 12"
        case .analog1: return "Analog 1"
        case .analog2: return "Analog 2"
        case .analog3: return "Analog 3"
        case .analog4: return "Analog 4"
        case .spdif1:  return "S/PDIF 1"
        case .spdif2:  return "S/PDIF 2"
        case .m1:      return "Mix M1"
        case .m2:      return "Mix M2"
        case .m3:      return "Mix M3"
        case .m4:      return "Mix M4"
        case .m5:      return "Mix M5"
        case .m6:      return "Mix M6"
        }
    }

    /// Useful sources on a 1st-gen Scarlett 8i6.
    public static let availableOn8i6: [MixBus] = [
        .off,
        .daw1, .daw2, .daw3, .daw4, .daw5, .daw6,
        .analog1, .analog2, .analog3, .analog4,
        .spdif1, .spdif2,
        .m1, .m2, .m3, .m4, .m5, .m6,
    ]

    /// Just the 6 matrix-output buses (M1..M6), in order.
    public static let matrixOutputs: [MixBus] = [.m1, .m2, .m3, .m4, .m5, .m6]

    /// Index into the matrix (0..5) for the 6 mix-bus outputs. nil for any
    /// other MixBus case (it's only meaningful for `.m1..m6`).  Used by
    /// `setMixerGain` to compute the cell address.
    public var matrixIndex: Int? {
        switch self {
        case .m1: return 0; case .m2: return 1; case .m3: return 2
        case .m4: return 3; case .m5: return 4; case .m6: return 5
        default:  return nil
        }
    }

    /// Which stereo pair this mix bus belongs to: 0 = M1+M2, 1 = M3+M4,
    /// 2 = M5+M6. nil for non-matrix buses.
    public var stereoPairIndex: Int? {
        guard let idx = matrixIndex else { return nil }
        return idx / 2
    }

    /// True for the left side of a stereo pair (M1, M3, M5).
    public var isLeftOfPair: Bool {
        guard let idx = matrixIndex else { return false }
        return idx % 2 == 0
    }
}

/// Physical output route index (0..5).
public enum Route: UInt16, CaseIterable, Identifiable {
    case monitorLeft = 0, monitorRight = 1
    case phonesLeft = 2,  phonesRight = 3
    case spdifLeft  = 4,  spdifRight  = 5

    public var id: UInt16 { rawValue }
    public var displayName: String {
        switch self {
        case .monitorLeft:  return "Monitor L"
        case .monitorRight: return "Monitor R"
        case .phonesLeft:   return "Phones L"
        case .phonesRight:  return "Phones R"
        case .spdifLeft:    return "S/PDIF L"
        case .spdifRight:   return "S/PDIF R"
        }
    }
}

/// Post-routing gain stages (master + monitor L/R + phones L/R).
public enum SignalOut: UInt16 {
    case master = 0
    case monitorLeft = 1, monitorRight = 2
    case phonesLeft = 3,  phonesRight = 4
}

// MARK: - Gain encoding (matches x42 byte-for-byte)

/// Bus attenuation: -∞ .. 0 dB → 2 bytes LE.
/// Clamps at -128 dB and 0 dB.
public func attenuationBytes(db: Double) -> [UInt8] {
    if db <= -128 { return [0x00, 0x80] }
    if db >= 0    { return [0x00, 0x00] }
    let raw = Int(floor(65536.5 + 256.0 * db))
    return [UInt8(raw & 0xff), UInt8((raw >> 8) & 0xff)]
}

/// Mixer-matrix per-cell gain: -128 .. +6 dB → 2 bytes LE.
public func gainBytes(db: Double) -> [UInt8] {
    var v = Int(floor(db + 0.5))
    if v <= -128 { return [0x00, 0x80] }
    if v > 6     { return [0x00, 0x06] }
    if v >= 0    { return [0x00, UInt8(v)] }
    // negative: two's-complement-ish in the high byte
    v = 0x100 + v
    return [0x00, UInt8(v)]
}

let muteBytes:   [UInt8] = [0x01, 0x00]
let unmuteBytes: [UInt8] = [0x00, 0x00]

// MARK: - Peak readings

public struct PeakReading {
    public var inputs: [Double]   // 18 values (only first 8 meaningful on 8i6)
    public var daw: [Double]      // 6 values
    public var mixer: [Double]    // 8 values

    public init(inputs: [Double], daw: [Double], mixer: [Double]) {
        self.inputs = inputs
        self.daw = daw
        self.mixer = mixer
    }

    public static let empty = PeakReading(
        inputs: Array(repeating: -.infinity, count: 18),
        daw:    Array(repeating: -.infinity, count: 6),
        mixer:  Array(repeating: -.infinity, count: 8)
    )
}

// MARK: - Commands

extension ScarlettDevice {

    // ---- Switches ---------------------------------------------------------

    /// Set line/instrument impedance for channels 0 or 1 (the combo inputs).
    public func setImpedance(channel: Int, mode: Impedance) throws {
        guard (0...1).contains(channel) else { throw ScarlettError.invalidArgument("channel must be 0 or 1") }
        try controlOut(
            cmd: 0x01,
            value: 0x0901 + UInt16(channel),
            index: 0x0100,
            data: [mode.rawValue, 0x00]
        )
    }

    /// 8i6-specific: hi/lo gain switch for analog inputs 3 and 4.
    /// Channel 3 → wValue 0x0803, channel 4 → wValue 0x0804. (x42 sets [0,0] for "lo".)
    public func setHiLoGain(channel: Int, hi: Bool) throws {
        guard (3...4).contains(channel) else { throw ScarlettError.invalidArgument("hi/lo channel must be 3 or 4") }
        try controlOut(
            cmd: 0x01,
            value: 0x0800 + UInt16(channel),
            index: 0x0100,
            data: [hi ? 0x01 : 0x00, 0x00]
        )
    }

    /// Set device clock source.
    public func setClockSource(_ src: ClockSource) throws {
        try controlOut(cmd: 0x01, value: 0x0100, index: 0x2800, data: [src.rawValue])
    }

    /// Set sample rate in Hz (44100, 48000, 88200, 96000).
    /// CAUTION: changing rate while audio is streaming will glitch usbaudiod.
    public func setSampleRate(_ hz: UInt32) throws {
        let bytes: [UInt8] = [
            UInt8(hz & 0xff),
            UInt8((hz >> 8) & 0xff),
            UInt8((hz >> 16) & 0xff),
            UInt8((hz >> 24) & 0xff),
        ]
        try controlOut(cmd: 0x01, value: 0x0100, index: 0x2900, data: bytes)
    }

    // ---- Bus mute / attenuation -------------------------------------------

    /// Mute/unmute a post-routing bus (master, mon L/R, ph L/R).
    public func setMute(_ bus: SignalOut, muted: Bool) throws {
        try controlOut(
            cmd: 0x01,
            value: 0x0100 + bus.rawValue,
            index: 0x0a00,
            data: muted ? muteBytes : unmuteBytes
        )
    }

    /// Attenuate a post-routing bus (-∞ .. 0 dB).
    public func setAttenuation(_ bus: SignalOut, db: Double) throws {
        try controlOut(
            cmd: 0x01,
            value: 0x0200 + bus.rawValue,
            index: 0x0a00,
            data: attenuationBytes(db: db)
        )
    }

    /// Toggle stereo-to-mono fold-down on each output pair.  When mono is
    /// on for a pair, the device sums L+R into both physical outputs of
    /// that pair (useful for mono-compatibility checks while mixing).
    ///
    /// Bytes reverse-engineered from `MacHWDevice::setMonMono` in MixControl
    /// 1.10.6: bmRequestType=0x21, bRequest=0x01, wValue=0x0a01..0x0a05
    /// (one per output pair), wIndex=0x1400, wLength=1, data=[0 or 1].
    /// The original loops over 5 output pairs; on the 8i6 only the first
    /// pair (Monitor L+R) is physically present, but writing all 5 is
    /// harmless and matches what MixControl does.
    public func setMonitorMono(pair: Int, enabled: Bool) throws {
        guard (1...5).contains(pair) else {
            throw ScarlettError.invalidArgument("monitor-mono pair must be 1..5")
        }
        try controlOut(
            cmd: 0x01,
            value: 0x0a00 + UInt16(pair),
            index: 0x1400,
            data: [enabled ? 0x01 : 0x00]
        )
    }

    // ---- Matrix mixer -----------------------------------------------------

    /// Connect a signal source to a matrix-mixer input channel (0..17).
    /// Per x42: if a source is already wired to another channel, the device
    /// won't double-assign it — disconnect first with `.off` if needed.
    public func setMixerSource(channel: Int, source: SignalSource) throws {
        guard (0...17).contains(channel) else { throw ScarlettError.invalidArgument("mixer channel must be 0..17") }
        try controlOut(
            cmd: 0x01,
            value: 0x0600 + UInt16(channel),
            index: 0x3200,
            data: [source.rawValue, 0x00]
        )
    }

    /// Set matrix-mixer per-cell gain (channel × bus). -128 .. +6 dB.
    /// `bus` must be one of `.m1..m6` (anything else is a no-op).
    public func setMixerGain(channel: Int, bus: MixBus, db: Double) throws {
        guard (0...17).contains(channel) else { throw ScarlettError.invalidArgument("mixer channel must be 0..17") }
        guard let idx = bus.matrixIndex else { return }
        let mtx = UInt16(channel << 3) + UInt16(idx & 0x07)
        try controlOut(
            cmd: 0x01,
            value: 0x0100 + mtx,
            index: 0x3c00,
            data: gainBytes(db: db)
        )
    }

    // ---- Router -----------------------------------------------------------

    /// Connect a source to one of the 6 physical output routes.
    public func setRouteSource(_ route: Route, from source: MixBus) throws {
        try controlOut(
            cmd: 0x01,
            value: route.rawValue,
            index: 0x3300,
            data: [source.rawValue, 0x00]
        )
    }

    /// Connect a source to one of the USB capture channels — i.e. what the
    /// DAW sees when it reads input N from the device.  The 8i6 exposes 6
    /// capture channels indexed 0..5; channels 6..7 are addressable for
    /// loopback purposes on devices that support it (the 8i6 doesn't
    /// surface them as DAW inputs but the protocol accepts the writes).
    ///
    /// `wIndex=0x3400` — the same byte x42's `scarlettmixer.py` labels
    /// "?? clear assignments, disconnect matrix I/O ??" in `factory_reset`.
    /// Disassembling MixControl's `routeChannel` showed this is actually
    /// the third routing dimension (alongside `0x3200` matrix-source and
    /// `0x3300` physical-output routes): it sets what gets sent back to
    /// the host as a DAW input.
    public func setCaptureRoute(channel: Int, from source: MixBus) throws {
        guard (0...7).contains(channel) else {
            throw ScarlettError.invalidArgument("capture channel must be 0..7")
        }
        try controlOut(
            cmd: 0x01,
            value: UInt16(channel),
            index: 0x3400,
            data: [source.rawValue, 0x00]
        )
    }

    // ---- Reads (GET_CUR) --------------------------------------------------
    //
    // The 1st-gen 8i6 is USB Audio Class 2.0 (bInterfaceProtocol = 0x20 in
    // the descriptor), so reads use bRequest = UAC2_CS_CUR = 0x01 (same as
    // writes) with bmRequestType = 0xa1 to indicate IN direction. The wValue
    // and wIndex are the same values used to set the control; response
    // length matches the set payload.

    public func getRouteSource(_ route: Route) throws -> MixBus {
        let r = try controlIn(cmd: 0x01, value: route.rawValue, index: 0x3300, length: 2)
        return MixBus(rawValue: r[0]) ?? .off
    }

    public func getMute(_ bus: SignalOut) throws -> Bool {
        let r = try controlIn(cmd: 0x01, value: 0x0100 + bus.rawValue, index: 0x0a00, length: 2)
        return r[0] != 0
    }

    public func getAttenuation(_ bus: SignalOut) throws -> Double {
        let r = try controlIn(cmd: 0x01, value: 0x0200 + bus.rawValue, index: 0x0a00, length: 2)
        let raw = UInt16(r[0]) | (UInt16(r[1]) << 8)
        // Decoder is the inverse of `attenuationBytes`: signed Int16 / 256.
        // [0x00, 0x00] → 0 dB; [0x00, 0xff] → -1 dB; [0x00, 0x80] → -128 dB.
        return Double(Int16(bitPattern: raw)) / 256.0
    }

    public func getImpedance(channel: Int) throws -> Impedance {
        guard (0...1).contains(channel) else { throw ScarlettError.invalidArgument("channel must be 0 or 1") }
        let r = try controlIn(cmd: 0x01, value: 0x0901 + UInt16(channel), index: 0x0100, length: 2)
        return r[0] == 1 ? .instrument : .line
    }

    public func getHiLoGain(channel: Int) throws -> Bool {
        guard (3...4).contains(channel) else { throw ScarlettError.invalidArgument("hi/lo channel must be 3 or 4") }
        let r = try controlIn(cmd: 0x01, value: 0x0800 + UInt16(channel), index: 0x0100, length: 2)
        return r[0] != 0
    }

    public func getClockSource() throws -> ClockSource {
        let r = try controlIn(cmd: 0x01, value: 0x0100, index: 0x2800, length: 1)
        return ClockSource(rawValue: r[0]) ?? .internalClock
    }

    public func getSampleRate() throws -> UInt32 {
        let r = try controlIn(cmd: 0x01, value: 0x0100, index: 0x2900, length: 4)
        return UInt32(r[0]) | (UInt32(r[1]) << 8) | (UInt32(r[2]) << 16) | (UInt32(r[3]) << 24)
    }

    public func getMixerSource(channel: Int) throws -> SignalSource {
        guard (0...17).contains(channel) else { throw ScarlettError.invalidArgument("mixer channel must be 0..17") }
        let r = try controlIn(cmd: 0x01, value: 0x0600 + UInt16(channel), index: 0x3200, length: 2)
        return SignalSource(rawValue: r[0]) ?? .off
    }

    /// Read clock-sync status: true = device is locked to its current clock
    /// source, false = no lock (audio will glitch/silence).  Per x42's docs,
    /// reads from `wIndex=0x3c00` use `bRequest = UAC2_CS_MEM (0x03)` — the
    /// same path peak meters take — *not* the regular CS_CUR (0x01) used for
    /// other controls.
    public func getSyncLocked() throws -> Bool {
        let r = try controlIn(cmd: 0x03, value: 0x0002, index: 0x3c00, length: 1)
        return r.first == 0x01
    }

    public func getMixerGain(channel: Int, bus: MixBus) throws -> Double {
        guard (0...17).contains(channel) else { throw ScarlettError.invalidArgument("mixer channel must be 0..17") }
        guard let idx = bus.matrixIndex else { return -.infinity }
        let mtx = UInt16(channel << 3) + UInt16(idx & 0x07)
        let r = try controlIn(cmd: 0x01, value: 0x0100 + mtx, index: 0x3c00, length: 2)
        // gainBytes packs the dB value as a signed Int8 in the high byte.
        return Double(Int8(bitPattern: r[1]))
    }

    // ---- Save -------------------------------------------------------------

    /// Persist current mixer/routing state to the device's flash so it
    /// survives a power cycle. Writes to flash — don't call casually.
    public func saveSettingsToHardware() throws {
        try controlOut(cmd: 0x03, value: 0x005a, index: 0x3c00, data: [0xa5])
    }

    // ---- Peak meters ------------------------------------------------------

    public func readPeaks() throws -> PeakReading {
        let ins = try controlIn(cmd: 0x03, value: 0x0000, index: 0x3c00, length: 36)
        let daw = try controlIn(cmd: 0x03, value: 0x0003, index: 0x3c00, length: 12)
        let mix = try controlIn(cmd: 0x03, value: 0x0001, index: 0x3c00, length: 16)
        return PeakReading(
            inputs: decodePeaks(ins, count: 18),
            daw:    decodePeaks(daw, count: 6),
            mixer:  decodePeaks(mix, count: 8)
        )
    }

    // MARK: - Profile-driven raw-byte commands
    //
    // Phase 1 of the multi-device refactor: every per-device byte / wIndex /
    // wValue previously baked into the `SignalSource` / `MixBus` / `Route` /
    // `SignalOut` enums now lives in `DeviceProfile`.  These methods take
    // raw bytes and bus indices directly; call sites resolve them through
    // `self.profile` (the active `DeviceProfile`).
    //
    // These are *additive* overloads — the 8i6-enum methods above remain so
    // the existing `MixerState` / views still build.  Phase 2 will migrate
    // those call sites to these raw-byte methods and remove the enums.
    //
    // Channel / bus / capture bounds are enforced against `profile`
    // rather than baked into `0...17` / `m1..m6` / `0...7`.  `0xff`
    // remains the "Off" *write* byte — but on the 18i8 the device reads
    // back `0x22` after a `0xff` write (sentinel for "disconnected channel"),
    // so callers must never compare a GET result to `0xff` to detect Off.
    // Use `DeviceProfile.source(forByte:)` which falls back to "Off (0xXX)"
    // for any byte not in `sources`.

    /// Matrix-mixer source picker (`wIndex=0x3200`).
    /// `channel` is 0..<profile.matrixInputCount.  `sourceByte` is one of
    /// `profile.sources.map(\.byte)` (or `0xff` to disconnect).
    public func setMixerSourceByte(channel: Int, sourceByte: UInt8) throws {
        guard (0..<profile.matrixInputCount).contains(channel) else {
            throw ScarlettError.invalidArgument("mixer channel must be 0..<\(profile.matrixInputCount)")
        }
        try controlOut(
            cmd: 0x01,
            value: 0x0600 + UInt16(channel),
            index: 0x3200,
            data: [sourceByte, 0x00]
        )
    }

    public func getMixerSourceByte(channel: Int) throws -> UInt8 {
        guard (0..<profile.matrixInputCount).contains(channel) else {
            throw ScarlettError.invalidArgument("mixer channel must be 0..<\(profile.matrixInputCount)")
        }
        let r = try controlIn(cmd: 0x01, value: 0x0600 + UInt16(channel), index: 0x3200, length: 2)
        return r[0]
    }

    /// Matrix-mixer per-cell gain (`wIndex=0x3c00`, `mtx=(channel<<3)|(bus&7)`).
    /// `channel` is 0..<profile.matrixInputCount, `busIndex` is 0..<profile.mixBusCount.
    /// The wire format masks the bus index to 3 bits, so `mixBusCount` is
    /// limited to ≤ 8 regardless of device — see `18i8.md` (Phase 0 verdict).
    public func setMixerGainRaw(channel: Int, busIndex: Int, db: Double) throws {
        guard (0..<profile.matrixInputCount).contains(channel) else {
            throw ScarlettError.invalidArgument("mixer channel must be 0..<\(profile.matrixInputCount)")
        }
        guard (0..<profile.mixBusCount).contains(busIndex) else {
            throw ScarlettError.invalidArgument("mixer bus index must be 0..<\(profile.mixBusCount)")
        }
        let mtx = UInt16(channel << 3) + UInt16(busIndex & 0x07)
        try controlOut(
            cmd: 0x01,
            value: 0x0100 + mtx,
            index: 0x3c00,
            data: gainBytes(db: db)
        )
    }

    public func getMixerGainRaw(channel: Int, busIndex: Int) throws -> Double {
        guard (0..<profile.matrixInputCount).contains(channel) else {
            throw ScarlettError.invalidArgument("mixer channel must be 0..<\(profile.matrixInputCount)")
        }
        guard (0..<profile.mixBusCount).contains(busIndex) else {
            throw ScarlettError.invalidArgument("mixer bus index must be 0..<\(profile.mixBusCount)")
        }
        let mtx = UInt16(channel << 3) + UInt16(busIndex & 0x07)
        let r = try controlIn(cmd: 0x01, value: 0x0100 + mtx, index: 0x3c00, length: 2)
        return Double(Int8(bitPattern: r[1]))
    }

    /// Physical-output source picker (`wIndex=0x3300`).
    /// `output.wValue` comes from `profile.physicalOutputs`.
    public func setPhysicalRouteSource(_ output: PhysicalOutput, sourceByte: UInt8) throws {
        try controlOut(
            cmd: 0x01,
            value: output.wValue,
            index: 0x3300,
            data: [sourceByte, 0x00]
        )
    }

    public func getPhysicalRouteSource(_ output: PhysicalOutput) throws -> UInt8 {
        let r = try controlIn(cmd: 0x01, value: output.wValue, index: 0x3300, length: 2)
        return r[0]
    }

    /// USB-capture (ToHost / DAW-input) source picker (`wIndex=0x3400`).
    /// `channel` is 0..<profile.captureChannelCount + profile.loopbackChannelCount.
    public func setCaptureRouteSource(channel: Int, sourceByte: UInt8) throws {
        let upper = profile.captureChannelCount + profile.loopbackChannelCount
        guard (0..<upper).contains(channel) else {
            throw ScarlettError.invalidArgument("capture channel must be 0..<\(upper)")
        }
        try controlOut(
            cmd: 0x01,
            value: UInt16(channel),
            index: 0x3400,
            data: [sourceByte, 0x00]
        )
    }

    public func getCaptureRouteSource(channel: Int) throws -> UInt8 {
        let upper = profile.captureChannelCount + profile.loopbackChannelCount
        guard (0..<upper).contains(channel) else {
            throw ScarlettError.invalidArgument("capture channel must be 0..<\(upper)")
        }
        let r = try controlIn(cmd: 0x01, value: UInt16(channel), index: 0x3400, length: 2)
        return r[0]
    }

    /// Post-DAC output mute/unmute for a physical output (by its wValue).
    /// The wValue matches `PhysicalOutput.wValue` from the active profile.
    /// Use this instead of `setMute(_:muted:)` which is tied to 8i6's
    /// `SignalOut` enum mapping.
    public func setMuteRaw(outputWValue: UInt16, muted: Bool) throws {
        try controlOut(
            cmd: 0x01,
            value: 0x0100 + outputWValue + 1,
            index: 0x0a00,
            data: muted ? muteBytes : unmuteBytes
        )
    }

    /// Post-DAC output attenuation for a physical output (by its wValue).
    public func setAttenuationRaw(outputWValue: UInt16, db: Double) throws {
        try controlOut(
            cmd: 0x01,
            value: 0x0200 + outputWValue + 1,
            index: 0x0a00,
            data: attenuationBytes(db: db)
        )
    }
}

func val16ToDb(_ v: UInt16) -> Double {
    guard v > 0 else { return -.infinity }
    return 20.0 * log10(Double(v) / 65536.0)
}

func decodePeaks(_ bytes: [UInt8], count: Int) -> [Double] {
    (0..<count).map { i in
        let lo = UInt16(bytes[2*i])
        let hi = UInt16(bytes[2*i + 1])
        return val16ToDb((hi << 8) | lo)
    }
}
