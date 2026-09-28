import SwiftUI

/// Places access points around "this Mac": stronger signals sit closer to the center.
///
/// The angle has no physical meaning (Wi-Fi scans carry no direction), so it is derived
/// from a stable hash of the SSID. Access points of the same network cluster together
/// and don't jump around between scans.
enum RadarLayout {
    static let strongestRSSI = -30.0
    static let weakestRSSI = -95.0
    static let innerRadius: CGFloat = 34
    static let ringLevels = [-40, -50, -60, -70, -80, -90]

    static func radius(forRSSI rssi: Double, maxRadius: CGFloat) -> CGFloat {
        let clamped = min(max(rssi, weakestRSSI), strongestRSSI)
        let t = (strongestRSSI - clamped) / (strongestRSSI - weakestRSSI)
        return innerRadius + CGFloat(t) * (maxRadius - innerRadius)
    }

    static func angle(for network: WiFiNetwork) -> Angle {
        let base = StableHash.unit(network.ssid.flatMap { $0.isEmpty ? nil : $0 } ?? network.id) * 2 * .pi
        let jitter = (StableHash.unit(network.id) - 0.5) * 0.4
        return .radians(base + jitter)
    }

    static func position(for network: WiFiNetwork, center: CGPoint, maxRadius: CGFloat) -> CGPoint {
        let r = radius(forRSSI: Double(network.rssi), maxRadius: maxRadius)
        let a = angle(for: network).radians
        return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    }
}

struct RadarMapView: View {
    let networks: [WiFiNetwork]
    @Binding var selection: WiFiNetwork.ID?
    var showLabels: Bool

    @State private var hovered: WiFiNetwork.ID?

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = max(min(geometry.size.width, geometry.size.height) / 2 - 40, RadarLayout.innerRadius + 20)

            ZStack {
                RadarBackground(center: center, maxRadius: maxRadius)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }

                // Draw weak signals first so strong, nearby ones stay on top.
                ForEach(networks.reversed()) { network in
                    let isFocused = network.id == selection || network.id == hovered
                    let position = RadarLayout.position(for: network, center: center, maxRadius: maxRadius)
                    NetworkNode(
                        network: network,
                        isSelected: network.id == selection,
                        isHovered: network.id == hovered,
                        showLabel: showLabels || isFocused || network.isConnected,
                        labelOnLeft: position.x > center.x + 1
                    )
                    .zIndex(isFocused ? 1 : 0)
                    .position(position)
                    .onTapGesture { selection = network.id }
                    .onHover { inside in
                        if inside { hovered = network.id } else if hovered == network.id { hovered = nil }
                    }
                    .help("\(network.displayName) · \(network.rssi) dBm · ch \(network.channel)")
                }

                ThisMacMarker().position(center)
            }
            .animation(.spring(duration: 0.9), value: networks)
        }
        .overlay(alignment: .bottomLeading) { Legend().padding(12) }
        .clipped()
    }
}

private struct RadarBackground: View {
    let center: CGPoint
    let maxRadius: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                drawRings(in: &context)
                drawSweep(in: &context, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .background(.background)
    }

    private func drawRings(in context: inout GraphicsContext) {
        let ringColor = Color.secondary.opacity(0.25)

        for level in RadarLayout.ringLevels {
            let r = RadarLayout.radius(forRSSI: Double(level), maxRadius: maxRadius)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(ringColor), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            let label = context.resolve(Text("\(level) dBm").font(.caption2).foregroundStyle(.tertiary))
            context.draw(label, at: CGPoint(x: center.x + 4, y: center.y - r - 2), anchor: .bottomLeading)
        }

        var crosshair = Path()
        crosshair.move(to: CGPoint(x: center.x - maxRadius, y: center.y))
        crosshair.addLine(to: CGPoint(x: center.x + maxRadius, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - maxRadius))
        crosshair.addLine(to: CGPoint(x: center.x, y: center.y + maxRadius))
        context.stroke(crosshair, with: .color(ringColor), lineWidth: 0.5)
    }

    private func drawSweep(in context: inout GraphicsContext, time: TimeInterval) {
        let period = 4.0
        let angle = Angle.degrees(time.truncatingRemainder(dividingBy: period) / period * 360)
        let rect = CGRect(x: center.x - maxRadius, y: center.y - maxRadius, width: maxRadius * 2, height: maxRadius * 2)
        let gradient = Gradient(stops: [
            .init(color: .accentColor.opacity(0), location: 0),
            .init(color: .accentColor.opacity(0), location: 0.82),
            .init(color: .accentColor.opacity(0.22), location: 1),
        ])
        context.fill(Path(ellipseIn: rect), with: .conicGradient(gradient, center: center, angle: angle))
    }
}

private struct NetworkNode: View {
    let network: WiFiNetwork
    let isSelected: Bool
    let isHovered: Bool
    let showLabel: Bool
    /// Keeps labels inside the view by pointing them away from the nearest edge.
    let labelOnLeft: Bool

    private var diameter: CGFloat {
        switch network.channelWidthMHz {
        case ..<40: 11
        case ..<80: 13
        case ..<160: 15
        default: 17
        }
    }

    var body: some View {
        Circle()
            .fill(network.band.color.gradient)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1)
            }
            .background {
                if network.isConnected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: diameter + 10, height: diameter + 10)
                }
            }
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.primary, lineWidth: 2)
                        .frame(width: diameter + 16, height: diameter + 16)
                }
            }
            .scaleEffect(isHovered ? 1.3 : 1)
            .shadow(color: network.band.color.opacity(0.5), radius: isHovered || isSelected ? 6 : 2)
            .overlay(alignment: labelOnLeft ? .trailing : .leading) {
                if showLabel {
                    label.offset(x: labelOnLeft ? -(diameter + 6) : diameter + 6)
                }
            }
            .opacity(network.presenceOpacity)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var label: some View {
        HStack(spacing: 3) {
            if network.isConnected && !labelOnLeft {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
            Text(network.displayName)
                .italic(network.isHidden)
            if network.isConnected && labelOnLeft {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
        }
        .font(.caption.weight(isSelected || network.isConnected ? .semibold : .regular))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: .capsule)
        .allowsHitTesting(false)
    }
}

private struct ThisMacMarker: View {
    var body: some View {
        Image(systemName: "laptopcomputer")
            .font(.system(size: 20))
            .foregroundStyle(.primary)
            .padding(10)
            .background(.thickMaterial, in: .circle)
            .overlay(Circle().strokeBorder(.separator))
            .help("This Mac")
    }
}

private struct Legend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([WiFiBand.ghz2_4, .ghz5, .ghz6]) { band in
                HStack(spacing: 6) {
                    Circle().fill(band.color.gradient).frame(width: 9, height: 9)
                    Text(band.title)
                }
            }
            Divider()
            Text("Closer to center = stronger signal")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .fixedSize()
    }
}
