import Foundation
import ScarlettCore

/// A complete snapshot of every user-controllable bit of state — exactly the
/// stuff a person would want to recall as "my podcast setup" or "tracking
/// drums today".  Persisted in UserDefaults (in-app preset list) and as
/// `.8i6` snapshot files via the File menu (Save / Open).
public struct ScarlettPreset: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var createdAt: Date

    /// Output routing: route raw value → MixBus raw value.
    public var routes: [UInt16: UInt8]

    /// Matrix mixer state (parallel to MixerState fields).
    public var mixerSources: [UInt8]    // 18 × SignalSource raw byte
    public var mixerLevels:  [[Double]] // 18 × busPairCount
    public var mixerPans:    [[Double]] // 18 × busPairCount
    public var mixerMutes:   [Bool]     // 18 (per-channel)
    public var mixerSolos:   [Bool]     // 18 (per-channel)
    public var mixerNames:   [String]   // 18

    /// Left-channel indices of linked stereo pairs.
    public var linkedLefts: [Int]

    /// Bus index (0..<mixBusCount) that was active when saved.
    public var selectedBus: UInt8
}
