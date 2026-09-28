import SwiftUI

/// Classic Wi-Fi analyzer view: each network is drawn across the frequencies it occupies,
/// with its height showing signal strength, so channel overlap is easy to spot.
struct ChannelMapView: View {
    let networks: [WiFiNetwork]
    let bands: [WiFiBand]
    @Binding var selection: WiFiNetwork.ID?

    /// Skip empty bands unless nothing at all is in range.
    private var visibleBands: [WiFiBand] {
        let populated = bands.filter { band in networks.contains { $0.band == band } }
        return populated.isEmpty ? bands : populated
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(visibleBands) { band in
                    let bandNetworks = networks.filter { $0.band == band }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(band.title).font(.headline)
                            Text("\(bandNetworks.count) access points")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ChannelChart(band: band, networks: bandNetworks, selection: $selection)
                            .frame(height: visibleBands.count == 1 ? 420 : 240)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct ChannelChart: View {
    let band: WiFiBand
    let networks: [WiFiNetwork]
    @Binding var selection: WiFiNetwork.ID?

    private let insets = EdgeInsets(top: 22, leading: 52, bottom: 26, trailing: 12)
    private let rssiRange = -100.0 ... -20.0

    var body: some View {
        GeometryReader { geometry in
            let plot = plotRect(in: geometry.size)
            Canvas { context, _ in
                drawGrid(in: &context, plot: plot)
                // Strongest first, so weaker (smaller) curves are drawn on top and stay visible.
                for network in networks.sorted(by: { $0.rssi > $1.rssi }) {
                    draw(network, in: &context, plot: plot)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                selection = hitTest(location, plot: plot)?.id
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 8))
        .overlay {
            if networks.isEmpty {
                Text("No networks on this band")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.default, value: networks)
    }

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: insets.leading,
            y: insets.top,
            width: max(size.width - insets.leading - insets.trailing, 1),
            height: max(size.height - insets.top - insets.bottom, 1)
        )
    }

    private func x(_ frequency: Double, _ plot: CGRect) -> CGFloat {
        let range = ChannelMath.displayRange(for: band)
        return plot.minX + CGFloat((frequency - range.lowerBound) / (range.upperBound - range.lowerBound)) * plot.width
    }

    private func y(_ rssi: Double, _ plot: CGRect) -> CGFloat {
        let clamped = min(max(rssi, rssiRange.lowerBound), rssiRange.upperBound)
        let t = (clamped - rssiRange.lowerBound) / (rssiRange.upperBound - rssiRange.lowerBound)
        return plot.maxY - CGFloat(t) * plot.height
    }

    private func drawGrid(in context: inout GraphicsContext, plot: CGRect) {
        let gridColor = Color.secondary.opacity(0.2)

        for level in stride(from: -90, through: -30, by: 10) {
            let yPos = y(Double(level), plot)
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: yPos))
            line.addLine(to: CGPoint(x: plot.maxX, y: yPos))
            context.stroke(line, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            let label = context.resolve(Text("\(level)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary))
            context.draw(label, at: CGPoint(x: plot.minX - 6, y: yPos), anchor: .trailing)
        }
        let unit = context.resolve(Text("dBm").font(.caption2).foregroundStyle(.tertiary))
        context.draw(unit, at: CGPoint(x: plot.minX - 6, y: plot.minY - 6), anchor: .trailing)

        var axis = Path()
        axis.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        axis.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        context.stroke(axis, with: .color(.secondary.opacity(0.6)), lineWidth: 1)

        var lastLabelX = -CGFloat.infinity
        for channel in ChannelMath.axisChannels(for: band) {
            guard let frequency = ChannelMath.centerFrequency(channel: channel, band: band) else { continue }
            let xPos = x(frequency, plot)
            var tick = Path()
            tick.move(to: CGPoint(x: xPos, y: plot.maxY))
            tick.addLine(to: CGPoint(x: xPos, y: plot.maxY + 4))
            context.stroke(tick, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            // Thin out labels when the chart is too narrow to fit them all.
            guard xPos - lastLabelX >= 26 else { continue }
            lastLabelX = xPos
            let label = context.resolve(Text("\(channel)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary))
            context.draw(label, at: CGPoint(x: xPos, y: plot.maxY + 6), anchor: .top)
        }
    }

    private func draw(_ network: WiFiNetwork, in context: inout GraphicsContext, plot: CGRect) {
        guard let span = ChannelMath.occupiedSpan(channel: network.channel, band: band, widthMHz: network.channelWidthMHz) else { return }
        let x0 = x(span.lowerBound, plot)
        let x1 = x(span.upperBound, plot)
        let top = y(Double(network.rssi), plot)
        let path = curve(x0: x0, x1: x1, top: top, bottom: plot.maxY)

        let isSelected = network.id == selection
        let color = network.identityColor
        let opacity = network.presenceOpacity

        context.fill(path, with: .color(color.opacity((isSelected ? 0.35 : 0.14) * opacity)))
        context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: isSelected ? 2.5 : 1.25)

        let text = Text(network.displayName)
            .font(.caption2.weight(isSelected || network.isConnected ? .bold : .regular))
            .foregroundStyle(color.opacity(opacity))
        context.draw(context.resolve(text), at: CGPoint(x: (x0 + x1) / 2, y: top - 3), anchor: .bottom)
    }

    /// A flat-topped hump spanning the occupied bandwidth.
    private func curve(x0: CGFloat, x1: CGFloat, top: CGFloat, bottom: CGFloat) -> Path {
        let shoulder = min((x1 - x0) * 0.2, 14)
        var path = Path()
        path.move(to: CGPoint(x: x0, y: bottom))
        path.addCurve(
            to: CGPoint(x: x0 + shoulder, y: top),
            control1: CGPoint(x: x0 + shoulder * 0.5, y: bottom),
            control2: CGPoint(x: x0 + shoulder * 0.3, y: top)
        )
        path.addLine(to: CGPoint(x: x1 - shoulder, y: top))
        path.addCurve(
            to: CGPoint(x: x1, y: bottom),
            control1: CGPoint(x: x1 - shoulder * 0.3, y: top),
            control2: CGPoint(x: x1 - shoulder * 0.5, y: bottom)
        )
        return path
    }

    /// Picks the weakest network under the pointer, since it's drawn in front.
    private func hitTest(_ point: CGPoint, plot: CGRect) -> WiFiNetwork? {
        networks
            .filter { network in
                guard let span = ChannelMath.occupiedSpan(channel: network.channel, band: band, widthMHz: network.channelWidthMHz) else { return false }
                return (x(span.lowerBound, plot)...x(span.upperBound, plot)).contains(point.x)
                    && point.y >= y(Double(network.rssi), plot) - 14
                    && point.y <= plot.maxY
            }
            .min { $0.rssi < $1.rssi }
    }
}
