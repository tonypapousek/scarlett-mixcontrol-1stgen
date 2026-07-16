import Foundation
import ScarlettCore

// MARK: - Pretty-print helpers

func fmtDb(_ d: Double) -> String {
    d == -.infinity ? "  -inf" : String(format: "%6.1f", d)
}

func printPeaks(_ p: PeakReading) {
    // 8i6: analog inputs 1..6 (idx 0..5) + S/PDIF 1..2 (idx 8..9 in the 18i6 layout).
    // The 18i6's analog inputs 7/8 (idx 6,7) and ADAT (idx 10..17) read as zero on the 8i6.
    let analog = p.inputs[0..<6].map(fmtDb).joined(separator: " ")
    let spdif  = p.inputs[8..<10].map(fmtDb).joined(separator: " ")
    let daw    = p.daw.map(fmtDb).joined(separator: " ")
    let mix    = p.mixer.map(fmtDb).joined(separator: " ")
    print("  in 1..6:   \(analog)")
    print("  spdif L/R: \(spdif)")
    print("  daw 1..6:  \(daw)")
    print("  mix M1..8: \(mix)")
}

// MARK: - Argument parsing helpers

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    var description: String { switch self { case .usage(let s): return s } }
}

func need(_ args: [String], _ i: Int, _ what: String) throws -> String {
    guard i < args.count else { throw CLIError.usage("missing \(what)") }
    return args[i]
}

func parseDouble(_ s: String, _ what: String) throws -> Double {
    guard let v = Double(s) else { throw CLIError.usage("\(what): expected number, got '\(s)'") }
    return v
}

func parseInt(_ s: String, _ what: String) throws -> Int {
    guard let v = Int(s) else { throw CLIError.usage("\(what): expected integer, got '\(s)'") }
    return v
}

func parseSignalOut(_ s: String) throws -> SignalOut {
    switch s.lowercased() {
    case "master": return .master
    case "mon-l", "monitor-l", "monl": return .monitorLeft
    case "mon-r", "monitor-r", "monr": return .monitorRight
    case "ph-l", "phones-l", "phl":    return .phonesLeft
    case "ph-r", "phones-r", "phr":    return .phonesRight
    default: throw CLIError.usage("unknown output '\(s)' (expect master|mon-l|mon-r|ph-l|ph-r)")
    }
}

func parseRoute(_ s: String) throws -> Route {
    switch s.lowercased() {
    case "mon-l", "monitor-l": return .monitorLeft
    case "mon-r", "monitor-r": return .monitorRight
    case "ph-l",  "phones-l":  return .phonesLeft
    case "ph-r",  "phones-r":  return .phonesRight
    case "spdif-l":            return .spdifLeft
    case "spdif-r":            return .spdifRight
    default: throw CLIError.usage("unknown route '\(s)' (expect mon-l|mon-r|ph-l|ph-r|spdif-l|spdif-r)")
    }
}

func parseMixBus(_ s: String) throws -> MixBus {
    switch s.lowercased() {
    case "off":      return .off
    case "daw1":     return .daw1
    case "daw2":     return .daw2
    case "daw3":     return .daw3
    case "daw4":     return .daw4
    case "daw5":     return .daw5
    case "daw6":     return .daw6
    case "an1", "analog1": return .analog1
    case "an2", "analog2": return .analog2
    case "an3", "analog3": return .analog3
    case "an4", "analog4": return .analog4
    case "spdif1":   return .spdif1
    case "spdif2":   return .spdif2
    case "m1": return .m1
    case "m2": return .m2
    case "m3": return .m3
    case "m4": return .m4
    case "m5": return .m5
    case "m6": return .m6
    default: throw CLIError.usage("unknown source '\(s)'")
    }
}

func parseSignalSource(_ s: String) throws -> SignalSource {
    switch s.lowercased() {
    case "off":      return .off
    case "daw1":     return .daw1
    case "daw2":     return .daw2
    case "daw3":     return .daw3
    case "daw4":     return .daw4
    case "daw5":     return .daw5
    case "daw6":     return .daw6
    case "an1", "analog1": return .analog1
    case "an2", "analog2": return .analog2
    case "an3", "analog3": return .analog3
    case "an4", "analog4": return .analog4
    case "spdif1":   return .spdif1
    case "spdif2":   return .spdif2
    default: throw CLIError.usage("unknown source '\(s)'")
    }
}

func parseMixMat(_ s: String) throws -> MixBus {
    switch s.lowercased() {
    case "m1": return .m1; case "m2": return .m2; case "m3": return .m3
    case "m4": return .m4; case "m5": return .m5; case "m6": return .m6
    default: throw CLIError.usage("unknown matrix bus '\(s)' (expect m1..m6)")
    }
}

// MARK: - Commands

let usage = """
usage: scarlett-cli <command> [args]

  info
      Print device info (firmware version, serial).

  meters [--watch]
      Read input/DAW/mixer peak meters once, or poll every 50ms.

  set-impedance <1|2> <line|inst>
      Combo inputs 1 and 2 — line or instrument impedance.

  set-hilogain <3|4> <hi|lo>
      8i6 inputs 3 and 4 — hi/lo gain switch.

  set-clock <internal|spdif|adat>
      Clock source.

  set-rate <44100|48000|88200|96000>
      Sample rate. Caution: glitches active audio streams.

  set-mute <master|mon-l|mon-r|ph-l|ph-r> <on|off>
      Mute/unmute a post-routing bus.

  set-att <master|mon-l|mon-r|ph-l|ph-r> <db>
      Bus attenuation. db <= 0.

  set-route <mon-l|mon-r|ph-l|ph-r|spdif-l|spdif-r> <source>
      Wire a physical output to a source (DAWn, ANn, SPDIFn, Mn, off).

  set-mixsrc <chan 0..17> <source>
      Connect a signal to matrix-mixer input channel.

  set-mixgain <chan 0..17> <m1..m6> <db>
      Matrix-mixer per-cell gain. -128 <= db <= +6.

  save
      Persist current settings to device flash. Survives power cycle.

  probe-18i8
      One-shot raw dump for validating non-8i6 devices.  Reads peak
      bytes at multiple lengths, dumps matrix/route/capture state raw,
      and runs a SET→GET roundtrip on the matrix source picker.  Safe
      for any connected 1st-gen Scarlett — uses raw control transfers,
      no 8i6-specific enum assumptions.

  probe-sources
      Iterate every source byte 0x00..0x3F (plus 0xff) on the matrix
      source picker, printing the SET→GET roundtrip for each.  Finds
      hidden analog inputs and reveals which bytes the firmware treats
      as valid source IDs vs gap memory.  Safe, read-only at end.

  inspect
      Read-only dump of current device state: matrix sources, matrix
      gains, peaks, physical routes, attenuation.  Safe to run while
      the GUI is connected — no writes, just diagnostics.
"""

func main() throws {
    let raw = CommandLine.arguments
    guard raw.count > 1 else {
        print(usage)
        exit(2)
    }
    let cmd = raw[1]
    let args = Array(raw.dropFirst(2))

    let dev = try ScarlettDevice()

    switch cmd {
    case "test-route":
        // SET → GET roundtrip on S/PDIF L (route index 4) — safe to wiggle
        // since nothing is connected to the S/PDIF output.
        let route = Route.spdifLeft
        func readRaw() -> String {
            let r = (try? dev.controlIn(cmd: 0x01, value: route.rawValue, index: 0x3300, length: 2)) ?? []
            return r.map { String(format: "%02x", $0) }.joined(separator: " ")
        }
        let before = readRaw()
        print("baseline:               raw=\(before)")
        for src in [MixBus.daw4, .off, .m1, .analog2, .daw1] {
            try dev.setRouteSource(route, from: src)
            usleep(20_000)
            let raw = readRaw()
            print("set → \(src.displayName.padding(toLength: 10, withPad: " ", startingAt: 0))  raw=\(raw)  expect first byte 0x\(String(format: "%02x", src.rawValue))")
        }
        print("\nConclusion: if every raw read matches 'expect', GET works. If all 00 00, GET is unsupported.")

    case "state":
        // Probe all GET_CUR reads to see what the device reports.
        func tryRead<T>(_ label: String, _ block: () throws -> T) -> String {
            do { return "\(try block())" } catch { return "ERR (\(error))" }
        }
        print("Clock source:  \(tryRead("clock") { try dev.getClockSource() })")
        print("Sample rate:   \(tryRead("rate")  { try dev.getSampleRate() }) Hz")
        print()
        print("Impedance ch1: \(tryRead("imp1") { try dev.getImpedance(channel: 0) })")
        print("Impedance ch2: \(tryRead("imp2") { try dev.getImpedance(channel: 1) })")
        print("Hi/Lo ch3:     \(tryRead("hl3")  { try dev.getHiLoGain(channel: 3) ? "Hi" : "Lo" })")
        print("Hi/Lo ch4:     \(tryRead("hl4")  { try dev.getHiLoGain(channel: 4) ? "Hi" : "Lo" })")
        print()
        for bus in [SignalOut.master, .monitorLeft, .monitorRight, .phonesLeft, .phonesRight] {
            let m = tryRead("mute") { try dev.getMute(bus) ? "MUTED" : "unmuted" }
            let a = tryRead("att")  { String(format: "%.1f dB", try dev.getAttenuation(bus)) }
            print("\(String(describing: bus).padding(toLength: 14, withPad: " ", startingAt: 0))  \(m)  att=\(a)")
        }
        print()
        for r in Route.allCases {
            let raw = (try? dev.controlIn(cmd: 0x01, value: r.rawValue, index: 0x3300, length: 2)) ?? []
            let rawHex = raw.map { String(format: "%02x", $0) }.joined(separator: " ")
            let src = tryRead("route") { try dev.getRouteSource(r) }
            print("\(r.displayName.padding(toLength: 14, withPad: " ", startingAt: 0))  ← \(src)   [raw: \(rawHex)]")
        }
        print()
        print("Matrix mixer sources (channels 0..13):")
        for ch in 0..<14 {
            let raw = (try? dev.controlIn(cmd: 0x01, value: 0x0600 + UInt16(ch), index: 0x3200, length: 2)) ?? []
            let rawHex = raw.map { String(format: "%02x", $0) }.joined(separator: " ")
            let src = tryRead("msrc") { try dev.getMixerSource(channel: ch) }
            print("  ch\(String(format: "%2d", ch))  ← \(src)   [raw: \(rawHex)]")
        }
        print()
        print("Matrix mixer gains, channel 0 → M1..M6:")
        for bus in MixBus.matrixOutputs {
            guard let idx = bus.matrixIndex else { continue }
            let mtx = UInt16(0 << 3) + UInt16(idx)
            let raw = (try? dev.controlIn(cmd: 0x01, value: 0x0100 + mtx, index: 0x3c00, length: 2)) ?? []
            let rawHex = raw.map { String(format: "%02x", $0) }.joined(separator: " ")
            let g = tryRead("mgain") { String(format: "%.1f dB", try dev.getMixerGain(channel: 0, bus: bus)) }
            print("  \(bus)  \(g)   [raw: \(rawHex)]")
        }

    case "info":
        let fw = dev.firmwareBCD().map { bcd -> String in
            let hi = (bcd >> 8) & 0xff
            let lo = bcd & 0xff
            let major = (hi >> 4) * 10 + (hi & 0xf)
            let minor = (lo >> 4) * 10 + (lo & 0xf)
            return String(format: "v%d.%02d", major, minor)
        } ?? "?"
        let sn = dev.serialNumber() ?? "?"
        print("Scarlett 8i6 1st Gen (VID 0x1235 / PID 0x8002)")
        print("  firmware: \(fw)")
        print("  serial:   \(sn)")

    case "meters":
        let watch = args.contains("--watch")
        if watch {
            print("Polling peaks every 50ms — Ctrl-C to stop.\n")
            while true {
                let p = try dev.readPeaks()
                print("\u{001B}[2J\u{001B}[H", terminator: "")  // clear + home
                printPeaks(p)
                fflush(stdout)
                usleep(50_000)
            }
        } else {
            printPeaks(try dev.readPeaks())
        }

    case "set-impedance":
        let ch = try parseInt(need(args, 0, "channel"), "channel")
        guard ch == 1 || ch == 2 else { throw CLIError.usage("channel must be 1 or 2") }
        let mode = try need(args, 1, "mode").lowercased()
        let imp: Impedance
        switch mode {
        case "line":  imp = .line
        case "inst", "instrument": imp = .instrument
        default: throw CLIError.usage("mode must be 'line' or 'inst'")
        }
        try dev.setImpedance(channel: ch - 1, mode: imp)
        print("✓ ch\(ch) impedance → \(mode)")

    case "set-hilogain":
        let ch = try parseInt(need(args, 0, "channel"), "channel")
        guard ch == 3 || ch == 4 else { throw CLIError.usage("channel must be 3 or 4") }
        let g = try need(args, 1, "hi|lo").lowercased()
        let hi: Bool
        switch g {
        case "hi": hi = true
        case "lo": hi = false
        default: throw CLIError.usage("expect 'hi' or 'lo'")
        }
        try dev.setHiLoGain(channel: ch, hi: hi)
        print("✓ ch\(ch) gain → \(g)")

    case "set-clock":
        let s = try need(args, 0, "source").lowercased()
        let src: ClockSource
        switch s {
        case "internal", "int": src = .internalClock
        case "spdif":           src = .spdif
        case "adat":            src = .adat
        default: throw CLIError.usage("expect internal|spdif|adat")
        }
        try dev.setClockSource(src)
        print("✓ clock → \(s)")

    case "set-rate":
        let hz = try parseInt(need(args, 0, "rate"), "rate")
        try dev.setSampleRate(UInt32(hz))
        print("✓ sample rate → \(hz) Hz")

    case "set-mute":
        let bus = try parseSignalOut(try need(args, 0, "bus"))
        let on = try need(args, 1, "on|off").lowercased() == "on"
        try dev.setMute(bus, muted: on)
        print("✓ \(bus) → \(on ? "muted" : "unmuted")")

    case "set-att":
        let bus = try parseSignalOut(try need(args, 0, "bus"))
        let db  = try parseDouble(try need(args, 1, "db"), "db")
        try dev.setAttenuation(bus, db: db)
        print("✓ \(bus) → \(db) dB")

    case "set-route":
        let route = try parseRoute(try need(args, 0, "route"))
        let src   = try parseMixBus(try need(args, 1, "source"))
        try dev.setRouteSource(route, from: src)
        print("✓ route \(route) ← \(src)")

    case "set-mixsrc":
        let ch  = try parseInt(try need(args, 0, "channel"), "channel")
        let src = try parseSignalSource(try need(args, 1, "source"))
        try dev.setMixerSource(channel: ch, source: src)
        print("✓ mixer ch\(ch) ← \(src)")

    case "set-mixgain":
        let ch  = try parseInt(try need(args, 0, "channel"), "channel")
        let bus = try parseMixMat(try need(args, 1, "bus"))
        let db  = try parseDouble(try need(args, 2, "db"), "db")
        try dev.setMixerGain(channel: ch, bus: bus, db: db)
        print("✓ mixer ch\(ch) → \(bus) at \(db) dB")

    case "save":
        try dev.saveSettingsToHardware()
        print("✓ settings persisted to device flash")

    case "probe-sources":
        // Iterate every byte 0x00-0x3F as a matrix source picker value.
        // For each: SET → wait → GET → report.  The device's read-back
        // reveals which bytes the firmware accepts as source IDs and which
        // get transformed (e.g. 0xff → 0x22, certain high bytes → truncated).
        // This is how we find hidden analog inputs (rear line jacks) on 18i8.
        print("# probe-sources")
        print("# profile=\(dev.profile.internalName) pid=0x\(String(format: "%04x", dev.profile.productID))")
        print()
        print("# SET each byte to ch0, one per 500ms, then single read at end")
        let allBytes = Array(UInt8(0)...UInt8(0x3F)) + [UInt8(0xff)]
        for (i, byte) in allBytes.enumerated() {
            usleep(500_000)
            try dev.controlOut(cmd: 0x01, value: 0x0600, index: 0x3200, data: [byte, 0])
            if i % 8 == 7 || i == allBytes.count - 1 {
                print("  \(String(format: "0x%02x", byte)) [\(i+1)/\(allBytes.count)]")
            }
        }
        print("  ✓ all writes done, reading final state...")
        usleep(500_000)
        let r = try dev.controlIn(cmd: 0x01, value: 0x0600, index: 0x3200, length: 2)
        print(String(format: "  ch0 final: 0x%02x 0x%02x", r[0], r[1]))
        // Restore
        try dev.controlOut(cmd: 0x01, value: 0x0600, index: 0x3200, data: [0xff, 0])

    case "probe-18i8":
        // Pure raw IO dump — no 8i6 enum assumptions.  Used for Phase 0
        // validation of the 18i8 (Saffire18i8) byte tables.  All values
        // read here are raw USB bytes; the agent interprets them offline.
        let p = dev.profile
        print("# probe-18i8")
        print("# profile=\(p.internalName) pid=0x\(String(format: "%04x", p.productID)) display=\"\(p.displayName)\"")
        print("# matrixInputCount=\(p.matrixInputCount) mixBusCount=\(p.mixBusCount)")
        print("# captureChannelCount=\(p.captureChannelCount) loopbackChannelCount=\(p.loopbackChannelCount)")
        print()

        // 1. Raw peak bytes at multiple lengths for each of the 3 read groups.
        print("## rawPeaks (cmd=0x03 index=0x3c00)")
        for (label, wValue, length) in [
            ("inputs", UInt16(0x0000), UInt16(36)),
            ("inputs", UInt16(0x0000), UInt16(64)),
            ("daw",     UInt16(0x0003), UInt16(12)),
            ("daw",     UInt16(0x0003), UInt16(16)),
            ("daw",     UInt16(0x0003), UInt16(32)),
            ("mix",     UInt16(0x0001), UInt16(16)),
            ("mix",     UInt16(0x0001), UInt16(32)),
        ] as [(String, UInt16, UInt16)] {
            let r = (try? dev.controlIn(cmd: 0x03, value: wValue, index: 0x3c00, length: length)) ?? []
            let hex = r.map { String(format: "%02x", $0) }.joined(separator: " ")
            print("  group=\(label.padding(toLength: 6, withPad: " ", startingAt: 0)) value=0x\(String(format: "%04x", wValue)) length=\(String(format: "%2d", length)) -> [\(hex)]")
        }
        print()

        // 2. Matrix-mixer source reads, channel 0..<18 (we read raw 2 bytes).
        print("## matrixSources (cmd=0x01 value=0x0600+ch index=0x3200 length=2)")
        for ch in 0..<18 {
            let r = (try? dev.controlIn(cmd: 0x01, value: 0x0600 + UInt16(ch), index: 0x3200, length: 2)) ?? []
            let hex = r.count == 2 ? String(format: "%02x %02x", r[0], r[1]) : "<short>"
            print("  ch\(String(format: "%02d", ch))  raw=[\(hex)]")
        }
        print()

        // 3. Physical-output routes (wIndex 0x3300), probe wValues 0..<10 —
        // covers 8i6's 6 and 18i8's 8 plus extra headroom.
        print("## physicalRoutes (cmd=0x01 value=wValue index=0x3300 length=2)")
        for wv in 0..<10 {
            let r = (try? dev.controlIn(cmd: 0x01, value: UInt16(wv), index: 0x3300, length: 2)) ?? []
            let hex = r.count == 2 ? String(format: "%02x %02x", r[0], r[1]) : "<short>"
            print("  wValue=\(String(format: "%2d", wv))  raw=[\(hex)]")
        }
        print()

        // 4. USB-capture routes (wIndex 0x3400), channels 0..<16 — covers
        // 8i6's 6 + 18i8's 14 + 2 loopback plus headroom.
        print("## captureRoutes (cmd=0x01 value=ch index=0x3400 length=2)")
        for ch in 0..<16 {
            let r = (try? dev.controlIn(cmd: 0x01, value: UInt16(ch), index: 0x3400, length: 2)) ?? []
            let hex = r.count == 2 ? String(format: "%02x %02x", r[0], r[1]) : "<short>"
            print("  ch\(String(format: "%02d", ch))  raw=[\(hex)]")
        }
        print()

        // 5. Matrix-gain reads — channels 0..<6 × buses 0..<9 (ch << 3 masks
        // bus to 3 bits, so bus0 and bus8 collapse on the wire — see if
        // the device distinguishes them or returns the same data).
        print("## matrixGains (cmd=0x01 value=0x0100+mtx index=0x3c00 length=2)")
        for ch in 0..<6 {
            for bus in 0..<9 {
                let mtx = UInt16(ch << 3) + UInt16(bus & 0x07)
                let r = (try? dev.controlIn(cmd: 0x01, value: 0x0100 + mtx, index: 0x3c00, length: 2)) ?? []
                let hex = r.count == 2 ? String(format: "%02x %02x", r[0], r[1]) : "<short>"
                print("  ch\(ch) bus\(bus) (mtx=0x\(String(format: "%02x", mtx)))  raw=[\(hex)]")
            }
        }
        print()

        // 6. setMixerSourceByte / getMixerSource roundtrip — write each known
        // 18i8 source byte to channel 0 and read back.  Channel 0 is
        // restored to Off (0xff) afterward so we don't disturb the state.
        // This section uses the new typed-API setter (`setMixerSourceByte`)
        // to exercise the Phase 1 write path on hardware.  The read stays
        // as raw controlIn so we capture both bytes for the printout.
        print("## sourceRoundtrip (channel 0, via setMixerSourceByte, then raw GET)")
        let probes: [(UInt8, String)] = [
            (0x08, "Anlg In 1"),
            (0x10, "SPDIF L"),
            (0x12, "ADAT In 1"),
            (0x1a, "FromMix1"),
            (0xff, "Off"),
        ]
        for (byte, name) in probes {
            do {
                try dev.setMixerSourceByte(channel: 0, sourceByte: byte)
                usleep(30_000)
                let r = (try? dev.controlIn(cmd: 0x01, value: 0x0600, index: 0x3200, length: 2)) ?? []
                let hex = r.count == 2 ? String(format: "%02x %02x", r[0], r[1]) : "<short>"
                print("  set(0x\(String(format: "%02x", byte)) = \(name.padding(toLength: 10, withPad: " ", startingAt: 0))) -> read=\(hex)")
            } catch {
                print("  set(0x\(String(format: "%02x", byte))) error: \(error)")
            }
        }
        print()

        // 7. typedApi — regression check that the new profile-driven typed
        // getters (Phase 1 raw-byte API) return values consistent with the
        // raw reads above.  Sets are skipped here to avoid disturbing state;
        // we only read.
        print("## typedApi (new raw-byte getters, read-only)")
        if let firstMatrixByte = try? dev.getMixerSourceByte(channel: 0) {
            print("  getMixerSourceByte(0)       -> 0x\(String(format: "%02x", firstMatrixByte))")
        }
        if let secondMatrixByte = try? dev.getMixerSourceByte(channel: 1) {
            print("  getMixerSourceByte(1)       -> 0x\(String(format: "%02x", secondMatrixByte))")
        }
        if let gainCh0Bus0 = try? dev.getMixerGainRaw(channel: 0, busIndex: 0) {
            print("  getMixerGainRaw(0, bus0)    -> \(String(format: "%.1f dB", gainCh0Bus0))")
        }
        if !p.physicalOutputs.isEmpty {
            if let routeByte = try? dev.getPhysicalRouteSource(p.physicalOutputs[0]) {
                print("  getPhysicalRouteSource(Mon.L wValue=\(p.physicalOutputs[0].wValue)) -> 0x\(String(format: "%02x", routeByte))")
            }
        }
        if let capByte = try? dev.getCaptureRouteSource(channel: 0) {
            print("  getCaptureRouteSource(0)    -> 0x\(String(format: "%02x", capByte))")
        }
        print()

        // 8. Output attenuation registers — read every plausible wValue
        // using both formula variants to find which register controls the
        // 18i8's phones output.  Mute: value=0x0100+wv.  Atten: 0x0200+wv.
        // Also try with +1 offset.
        print("## outputAttenReads (wIndex=0x0a00, len=2)")
        let attenBase = UInt16(0x0a00)
        for label in ["mute", "atten"] {
            let baseV = label == "mute" ? UInt16(0x0100) : UInt16(0x0200)
            print("  # \(label) — value=\(String(format: "0x%04x", baseV))+wv → raw   (decoded)")
            for wv in UInt16(0)..<UInt16(10) {
                let val = baseV + wv
                let r = (try? dev.controlIn(cmd: 0x01, value: val, index: attenBase, length: 2)) ?? [0, 0]
                let raw = String(format: "%02x %02x", r[0], r[1])
                let decoded: String
                if label == "atten" {
                    let raw16 = UInt16(r[0]) | (UInt16(r[1]) << 8)
                    let db = Double(Int16(bitPattern: raw16)) / 256.0
                    decoded = String(format: "%6.1f dB", db)
                } else {
                    decoded = r[0] == 0 ? "unmuted" : "muted"
                }
                print("    0x\(String(format: "%04x", val))  [\(raw)]  \(decoded)")
            }
            // Gentle SET→GET: write 0dB to wv=0, read back, then restore
            let tv = baseV + 0
            let orig = (try? dev.controlIn(cmd: 0x01, value: tv, index: attenBase, length: 2)) ?? [0, 0]
            _ = try? dev.controlOut(cmd: 0x01, value: tv, index: attenBase, data: [0x00, 0x00])
            usleep(40_000)
            let after = (try? dev.controlIn(cmd: 0x01, value: tv, index: attenBase, length: 2)) ?? [0, 0]
            print("    SET→GET test at 0x\(String(format: "%04x", tv)): orig=[\(String(format: "%02x %02x", orig[0], orig[1]))] → set=00 00 → read=[\(String(format: "%02x %02x", after[0], after[1]))]")
            _ = try? dev.controlOut(cmd: 0x01, value: tv, index: attenBase, data: orig)
        }

        print()

        // 8. Output gate register: wIndex=0x1400, read-only.
        // Writes to this register return kIOUSBPipeStalled (0xe000404f) —
        // the 18i8 firmware (like the 8i6) rejects writes at this index.
        // The XML monset="1 1 1 1 1 1" configuration is applied by the
        // original app at a different level (likely kernel/firmware init).
        print("## outputGate reads (wIndex=0x1400 — read-only, writes stall)")
        for pair in UInt16(1)...UInt16(5) {
            let val = 0x0a00 + pair
            let r = (try? dev.controlIn(cmd: 0x01, value: val, index: 0x1400, length: 1)) ?? [0]
            print("  pair=\(pair) value=0x\(String(format: "%04x", val)) → [\(String(format: "%02x", r[0]))]")
        }

        // 10. (Direct route setup moved to section 1 — runs before reads.)

        // 11. Clock sync status
        let locked = (try? dev.getSyncLocked()) ?? false
        print()
        print("## clockSync")
        print("  locked=\(locked)")

        print()
        // 12. Device identifiers
        let fwBCD = dev.firmwareBCD() ?? 0
        let fwStr = String(format: "0x%04x", fwBCD)
        let sn = dev.serialNumber() ?? "?"
        print("## device")
        print("  bcdDevice(USB firmware)=\(fwStr)")
        print("  serial=\(sn)")

    case "inspect":
        let p = dev.profile
        print("# inspect")
        print("# profile=\(p.internalName) pid=0x\(String(format: "%04x", p.productID))")
        print()

        print("## matrixSources")
        for ch in 0..<p.matrixInputCount {
            if let r = try? dev.controlIn(cmd: 0x01, value: 0x0600 + UInt16(ch), index: 0x3200, length: 2), r.count >= 2 {
                let name = p.source(forByte: r[0]).displayName
                print("  ch\(String(format: "%02d", ch)): 0x\(String(format: "%02x", r[0])) \(String(format: "%02x", r[1]))  (\(name))")
            }
        }
        print()

        print("## matrixGains (non-zero only)")
        for ch in 0..<p.matrixInputCount {
            for bus in 0..<p.mixBusCount {
                if let db = try? dev.getMixerGainRaw(channel: ch, busIndex: bus), abs(db) > 0.5 {
                    print("  ch\(ch)→M\(bus+1): \(String(format: "%.1f dB", db))")
                }
            }
        }
        print()

        print("## peaks")
        let peaks = (try? dev.readPeaks()) ?? .empty
        print("  inputs: \(peaks.inputs.map { fmtDb($0) }.joined(separator: " "))")
        print("  daw:    \(peaks.daw.map { fmtDb($0) }.joined(separator: " "))")
        print("  mixer:  \(peaks.mixer.map { fmtDb($0) }.joined(separator: " "))")
        print()

        print("## physicalRoutes (wIndex=0x3300)")
        for wv in 0..<p.physicalOutputs.count {
            let out = p.physicalOutputs[wv]
            if let r = try? dev.controlIn(cmd: 0x01, value: out.wValue, index: 0x3300, length: 2), r.count >= 2 {
                let name = p.source(forByte: r[0]).displayName
                print("  \(out.displayName) (wValue=\(out.wValue)): 0x\(String(format: "%02x", r[0])) (\(name))")
            }
        }
        print()

        print("## outputAtten (wIndex=0x0a00)")
        for wv in 0..<p.physicalOutputs.count {
            let out = p.physicalOutputs[wv]
            do {
                let mute = try dev.controlIn(cmd: 0x01, value: 0x0100 + out.wValue + 1, index: 0x0a00, length: 2)
                let atten = try dev.controlIn(cmd: 0x01, value: 0x0200 + out.wValue + 1, index: 0x0a00, length: 2)
                let raw16 = UInt16(atten[0]) | (UInt16(atten[1]) << 8)
                let db = Double(Int16(bitPattern: raw16)) / 256.0
                let isMuted = mute[0] != 0
                print("  \(out.displayName): muted=\(isMuted ? "YES" : "no") atten=\(String(format: "%.1f dB", db))")
            } catch {
                print("  \(out.displayName): read error")
            }
        }
        print()
        print("  # End of inspect — run while GUI is connected for live state.")

    case "-h", "--help", "help":
        print(usage)

    default:
        print("unknown command '\(cmd)'\n")
        print(usage)
        exit(2)
    }
}

do {
    try main()
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
