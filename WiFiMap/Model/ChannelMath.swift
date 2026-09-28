import Foundation

enum ChannelMath {
    /// Center frequency in MHz of a single 20 MHz channel.
    static func centerFrequency(channel: Int, band: WiFiBand) -> Double? {
        switch band {
        case .ghz2_4: channel == 14 ? 2484 : Double(2407 + 5 * channel)
        case .ghz5: Double(5000 + 5 * channel)
        case .ghz6: Double(5950 + 5 * channel)
        case .unknown: nil
        }
    }

    /// Frequency range (MHz) occupied by a network, including bonded channels.
    ///
    /// CoreWLAN only reports the primary channel and the total width, so the
    /// bonded block is inferred from the standard channel plan.
    static func occupiedSpan(channel: Int, band: WiFiBand, widthMHz: Int) -> ClosedRange<Double>? {
        guard let primary = centerFrequency(channel: channel, band: band) else { return nil }
        let width = Double(max(widthMHz, 20))
        let center: Double

        switch band {
        case .ghz2_4:
            // HT40+ is conventional on low channels, HT40- on high ones.
            center = widthMHz >= 40 ? primary + (channel <= 7 ? 10 : -10) : primary
        case .ghz5, .ghz6:
            let base = band == .ghz6 ? 1 : (channel >= 149 ? 149 : 36)
            let group = max(widthMHz / 20, 1)
            if group > 1, channel >= base {
                let index = (channel - base) / 4
                let first = base + (index / group) * group * 4
                center = centerFrequency(channel: first + (group - 1) * 2, band: band) ?? primary
            } else {
                center = primary
            }
        case .unknown:
            return nil
        }
        return (center - width / 2)...(center + width / 2)
    }

    /// Frequency range (MHz) shown on the channel chart for a band.
    static func displayRange(for band: WiFiBand) -> ClosedRange<Double> {
        switch band {
        case .ghz2_4: 2395...2500
        case .ghz5: 5150...5895
        case .ghz6: 5925...7125
        case .unknown: 0...1
        }
    }

    /// Channels to label on the chart's x-axis.
    static func axisChannels(for band: WiFiBand) -> [Int] {
        switch band {
        case .ghz2_4: Array(1...14)
        case .ghz5: Array(stride(from: 36, through: 64, by: 4))
            + Array(stride(from: 100, through: 144, by: 4))
            + Array(stride(from: 149, through: 177, by: 4))
        case .ghz6: Array(stride(from: 1, through: 233, by: 16))
        case .unknown: []
        }
    }
}
