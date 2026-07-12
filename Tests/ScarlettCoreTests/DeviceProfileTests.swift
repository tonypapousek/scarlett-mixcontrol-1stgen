import XCTest
@testable import ScarlettCore

final class DeviceProfileTests: XCTestCase {
    func testProfileIdentifiersAndDestinationsAreUnique() {
        XCTAssertEqual(Set(DeviceProfile.all.map(\.productID)).count, DeviceProfile.all.count)

        for profile in DeviceProfile.all {
            XCTAssertEqual(
                Set(profile.sources.map(\.byte)).count,
                profile.sources.count,
                "Duplicate source byte in \(profile.displayName)"
            )
            XCTAssertEqual(
                Set(profile.physicalOutputs.map(\.wValue)).count,
                profile.physicalOutputs.count,
                "Duplicate output destination in \(profile.displayName)"
            )
        }
    }

    func testEveryAdvertisedSourceRoundTripsThroughCanonicalValue() {
        for profile in DeviceProfile.all {
            for descriptor in profile.sources {
                let bus = profile.mixBus(fromWireByte: descriptor.byte)
                XCTAssertEqual(
                    profile.supportedWireByte(for: bus),
                    descriptor.byte,
                    "MixBus round-trip failed for \(descriptor.displayName) on \(profile.displayName)"
                )

                if descriptor.category != .mixOutput {
                    let source = profile.signalSource(fromWireByte: descriptor.byte)
                    XCTAssertEqual(
                        profile.supportedWireByte(for: source),
                        descriptor.byte,
                        "SignalSource round-trip failed for \(descriptor.displayName) on \(profile.displayName)"
                    )
                }
            }
        }
    }

    func testCaptureDefaultsAreCompleteAndSupported() {
        for profile in DeviceProfile.all {
            XCTAssertEqual(
                profile.defaultCaptureSources.count,
                profile.captureChannelCount,
                "Incomplete capture defaults for \(profile.displayName)"
            )
            for source in profile.defaultCaptureSources {
                XCTAssertNotNil(
                    profile.supportedWireByte(for: source),
                    "Unsupported capture default \(source.displayName) on \(profile.displayName)"
                )
            }
        }
    }

    func testConfirmed18i8CaptureOrderIsPreserved() {
        XCTAssertEqual(DeviceProfile.scarlett18i8.defaultCaptureSources, [
            .analog1, .analog2, .analog3, .analog4,
            .spdif1, .spdif2,
            .adat1, .adat2, .adat3, .adat4, .adat5, .adat6, .adat7, .adat8,
        ])
    }

    func testExtendedDawChannelsCannotLeakOntoSmallerProfiles() {
        XCTAssertNil(DeviceProfile.scarlett8i6.supportedWireByte(for: MixBus.daw13))
        XCTAssertNil(DeviceProfile.scarlett6i6.supportedWireByte(for: MixBus.daw13))
        XCTAssertNil(DeviceProfile.scarlett18i6.supportedWireByte(for: MixBus.daw13))
        XCTAssertNil(DeviceProfile.scarlett18i8.supportedWireByte(for: MixBus.daw13))

        XCTAssertEqual(DeviceProfile.scarlett18i20.supportedWireByte(for: MixBus.daw13), 0x0c)
        XCTAssertEqual(DeviceProfile.scarlett18i20.supportedWireByte(for: MixBus.daw20), 0x13)
    }

    func testExisting8i6CanonicalRawValuesRemainStable() {
        XCTAssertEqual(MixBus.daw1.rawValue, 0x00)
        XCTAssertEqual(MixBus.daw12.rawValue, 0x0b)
        XCTAssertEqual(MixBus.analog1.rawValue, 0x0c)
        XCTAssertEqual(MixBus.spdif1.rawValue, 0x12)
        XCTAssertEqual(MixBus.m1.rawValue, 0x14)
        XCTAssertEqual(MixBus.m6.rawValue, 0x19)
    }
}
