import Foundation

enum WiFiBand: String, CaseIterable, Identifiable, Sendable {
    case ghz2_4
    case ghz5
    case ghz6
    case unknown

    var id: Self { self }

    var title: String {
        switch self {
        case .ghz2_4: "2.4 GHz"
        case .ghz5: "5 GHz"
        case .ghz6: "6 GHz"
        case .unknown: "Unknown"
        }
    }
}

/// A single access point (BSSID) seen during one or more scans.
struct WiFiNetwork: Identifiable, Hashable, Sendable {
    /// The BSSID when macOS reveals it, otherwise a best-effort synthetic key.
    let id: String
    var ssid: String?
    var bssid: String?
    var rssi: Int
    var noise: Int
    var channel: Int
    var band: WiFiBand
    var channelWidthMHz: Int
    var security: String
    var isSecured: Bool
    var beaconInterval: Int
    var countryCode: String?
    var isConnected: Bool
    var firstSeen: Date
    var lastSeen: Date
    /// Consecutive scans this access point was absent from. A single CoreWLAN
    /// scan routinely misses some nearby access points, so one miss is normal.
    var missedScans = 0
    /// Recent RSSI samples, oldest first.
    var rssiHistory: [Int]

    var displayName: String {
        guard let ssid, !ssid.isEmpty else { return "Hidden Network" }
        return ssid
    }

    var isHidden: Bool { ssid?.isEmpty ?? true }

    /// Signal-to-noise ratio in dB, if the driver reported a noise floor.
    var snr: Int? { noise < 0 ? rssi - noise : nil }

    /// 0...1, where -30 dBm or better is 1 and -90 dBm or worse is 0.
    var signalQuality: Double {
        min(max(Double(rssi + 90) / 60, 0), 1)
    }

    var frequencyMHz: Double? {
        ChannelMath.centerFrequency(channel: channel, band: band)
    }

    func matches(_ query: String) -> Bool {
        displayName.localizedCaseInsensitiveContains(query)
            || (bssid?.localizedCaseInsensitiveContains(query) ?? false)
            || String(channel) == query
    }
}

enum StableHash {
    /// FNV-1a. Unlike `Hasher`, this is identical across launches, so map positions stay put.
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// A stable value in 0..<1.
    static func unit(_ string: String) -> Double {
        Double(fnv1a(string) % 1_000_003) / 1_000_003
    }
}
