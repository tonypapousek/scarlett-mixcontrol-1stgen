import SwiftUI

/// Vertical fader inspired by Focusrite Control 2's mixer strips.
///
/// Linear scale across `-60...+6` dB to match Control 2's visible range.
/// Drag anywhere along the column (or on the knob) to set the value.
/// We never write more than 200 Hz from the gesture path — SwiftUI itself
/// throttles drag events. The slot for the dB scale is rendered separately
/// by `DbScale`, so the same coordinate math drives both.
struct VerticalFader: View {
    @Binding var db: Double
    var height: CGFloat = StripLayout.faderHeight
    var dbRange: ClosedRange<Double> = Self.defaultRange

    static let defaultRange: ClosedRange<Double> = -60...6
    static var dbMin: Double { defaultRange.lowerBound }
    static var dbMax: Double { defaultRange.upperBound }

    private var dbMin: Double { dbRange.lowerBound }
    private var dbMax: Double { dbRange.upperBound }

    private let trackWidth: CGFloat = 4
    private let knobWidth: CGFloat = 30
    private let knobHeight: CGFloat = 14

    private var fillFraction: Double {
        let clamped = max(dbMin, min(dbMax, db))
        return (clamped - dbMin) / (dbMax - dbMin)
    }

    var body: some View {
        // Pre-compute everything: height is fixed via the outer .frame, so
        // we don't need a GeometryReader (which would force a layout pass
        // on every frame). Drag-gesture `.location.y` is already relative
        // to this view's local coordinate space.
        let usable = height - knobHeight
        let knobOffsetY = usable * (1 - fillFraction)

        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.faderTrack)
                .frame(width: trackWidth, height: height)
                .frame(maxWidth: .infinity)

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.faderTrackFill)
                .frame(width: trackWidth, height: max(0, height - knobOffsetY - knobHeight / 2))
                .frame(maxWidth: .infinity)
                .offset(y: knobOffsetY + knobHeight / 2)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.85), Theme.faderKnob, Color(white: 0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .frame(height: 1)
                )
                .frame(width: knobWidth, height: knobHeight)
                .shadow(color: Theme.faderKnobShadow, radius: 1.5, y: 1)
                .frame(maxWidth: .infinity)
                .offset(y: knobOffsetY)
        }
        .frame(width: knobWidth + 6, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let y = max(0, min(usable, drag.location.y - knobHeight / 2))
                    let frac = 1.0 - Double(y / usable)
                    db = dbMin + frac * (dbMax - dbMin)
                }
        )
    }
}

/// Static dB-scale tick column rendered beside the fader.
struct DbScale: View {
    var height: CGFloat = StripLayout.faderHeight
    var dbRange: ClosedRange<Double> = VerticalFader.defaultRange
    var marks: [Int] = [0, -6, -12, -18, -24, -30, -36, -48, -60]

    var body: some View {
        let usable = height - 14    // matches fader's `knobHeight`
        let knobHalf: CGFloat = 7
        let dbMin = dbRange.lowerBound
        let dbMax = dbRange.upperBound
        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { db in
                let frac = (Double(db) - dbMin) / (dbMax - dbMin)
                let y = knobHalf + usable * (1 - frac)
                HStack(spacing: 3) {
                    Rectangle()
                        .fill(Theme.textSecondary.opacity(0.65))
                        .frame(width: 3, height: 1)
                    Text("\(db)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                .position(x: 16, y: y)
            }
        }
        .frame(width: 28, height: height, alignment: .topLeading)
    }
}

/// Vertical peak meter rendered alongside a fader.
///
/// The thick gradient bar follows the live `db` value.  Two horizontal ticks
/// hover above it:
///  * `peakDb` (white): recent peak-hold value, decays at the rate set in
///    `MixerState.peakDecayDbPerSecond`.
///  * `maxPeakDb` (red): all-time max since the last "Clear peaks" — useful
///    for gain staging over a long take.
struct VerticalMeter: View {
    var db: Double
    var peakDb: Double = -.infinity
    var maxPeakDb: Double = -.infinity
    var height: CGFloat = StripLayout.faderHeight
    private let dbMin: Double = -60
    private let dbMax: Double = 0
    private let width: CGFloat = 6

    private func fraction(_ v: Double) -> Double {
        let value = v.isFinite ? v : dbMin
        let clamped = max(dbMin, min(dbMax, value))
        return (clamped - dbMin) / (dbMax - dbMin)
    }

    var body: some View {
        // Height is fixed via the outer frame — no GeometryReader needed.
        let h = height
        let currentFill = h * fraction(db)
        let peakOffset = h * (1 - fraction(peakDb))
        let maxOffset  = h * (1 - fraction(maxPeakDb))

        return ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Theme.faderTrack)
                .frame(width: width, height: h)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.meterHigh, Theme.meterMid, Theme.meterLow],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: width, height: max(0, currentFill))

            if peakDb.isFinite && peakDb > dbMin {
                Rectangle()
                    .fill(Theme.textPrimary)
                    .frame(width: width + 2, height: 1.5)
                    .position(x: (width + 2) / 2, y: peakOffset)
            }

            if maxPeakDb.isFinite && maxPeakDb > dbMin {
                Rectangle()
                    .fill(Theme.meterHigh)
                    .frame(width: width + 4, height: 1.5)
                    .position(x: (width + 2) / 2, y: maxOffset)
            }
        }
        .frame(width: width + 4, height: height)
    }
}
