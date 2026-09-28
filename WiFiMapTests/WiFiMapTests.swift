import CoreGraphics
import Testing
@testable import WiFiMap

struct ChannelMathTests {
    @Test func centerFrequencies() {
        #expect(ChannelMath.centerFrequency(channel: 1, band: .ghz2_4) == 2412)
        #expect(ChannelMath.centerFrequency(channel: 14, band: .ghz2_4) == 2484)
        #expect(ChannelMath.centerFrequency(channel: 36, band: .ghz5) == 5180)
        #expect(ChannelMath.centerFrequency(channel: 1, band: .ghz6) == 5955)
    }

    @Test(arguments: [
        (36, 80, 5170.0...5250.0),
        (44, 80, 5170.0...5250.0),
        (100, 160, 5490.0...5650.0),
        (153, 80, 5735.0...5815.0),
        (157, 40, 5775.0...5815.0),
    ])
    func bondedFiveGigahertzSpans(channel: Int, width: Int, expected: ClosedRange<Double>) {
        #expect(ChannelMath.occupiedSpan(channel: channel, band: .ghz5, widthMHz: width) == expected)
    }

    @Test func sixGigahertzBonding() {
        // Channels 1–13 form the first 80 MHz block, centered on channel 7 (5985 MHz).
        #expect(ChannelMath.occupiedSpan(channel: 5, band: .ghz6, widthMHz: 80) == 5945...6025)
    }

    @Test func twentyMegahertzIsCenteredOnPrimary() {
        #expect(ChannelMath.occupiedSpan(channel: 6, band: .ghz2_4, widthMHz: 20) == 2427...2447)
    }
}

struct RadarLayoutTests {
    @Test func strongerSignalsSitCloser() {
        let near = RadarLayout.radius(forRSSI: -40, maxRadius: 300)
        let far = RadarLayout.radius(forRSSI: -80, maxRadius: 300)
        #expect(near < far)
        #expect(RadarLayout.radius(forRSSI: -10, maxRadius: 300) == RadarLayout.innerRadius)
        #expect(RadarLayout.radius(forRSSI: -120, maxRadius: 300) == 300)
    }

    @Test func hashIsStable() {
        // Pinned value: positions must not change between launches.
        #expect(StableHash.fnv1a("") == 0xcbf2_9ce4_8422_2325)
        #expect(StableHash.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
    }
}
