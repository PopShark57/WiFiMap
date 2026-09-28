import SwiftUI

extension WiFiBand {
    var color: Color {
        switch self {
        case .ghz2_4: .orange
        case .ghz5: .blue
        case .ghz6: .purple
        case .unknown: .gray
        }
    }
}

extension WiFiNetwork {
    /// A stable per-network color, used where band color alone can't tell networks apart.
    var identityColor: Color {
        Color(hue: StableHash.unit(ssid ?? id), saturation: 0.7, brightness: 0.9)
    }

    /// Fades access points out as they keep missing scans.
    var presenceOpacity: Double {
        switch missedScans {
        case 0: 1
        case 1: 0.8
        case 2: 0.55
        default: 0.35
        }
    }
}

enum MapMode: String, CaseIterable, Identifiable {
    case radar = "Radar"
    case channels = "Channels"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .radar: "dot.radiowaves.left.and.right"
        case .channels: "chart.bar.xaxis"
        }
    }
}

enum BandFilter: String, CaseIterable, Identifiable {
    case all, ghz2_4, ghz5, ghz6

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All Bands"
        case .ghz2_4: WiFiBand.ghz2_4.title
        case .ghz5: WiFiBand.ghz5.title
        case .ghz6: WiFiBand.ghz6.title
        }
    }

    var bands: [WiFiBand] {
        switch self {
        case .all: [.ghz2_4, .ghz5, .ghz6]
        case .ghz2_4: [.ghz2_4]
        case .ghz5: [.ghz5]
        case .ghz6: [.ghz6]
        }
    }
}
