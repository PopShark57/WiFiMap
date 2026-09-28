import CoreWLAN
import Foundation
import Observation

enum ScanError: LocalizedError {
    case noInterface
    case poweredOff
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noInterface: "No Wi-Fi interface was found on this Mac."
        case .poweredOff: "Wi-Fi is turned off."
        case .failed(let reason): "Scan failed: \(reason)"
        }
    }
}

struct ScanResult: Sendable {
    var interfaceName: String?
    var networks: [WiFiNetwork]
}

@MainActor
@Observable
final class WiFiScanner {
    private(set) var networks: [WiFiNetwork] = []
    private(set) var isScanning = false
    private(set) var lastScanDate: Date?
    private(set) var lastError: String?
    private(set) var interfaceName: String?

    /// Access points missing from scans for longer than this are dropped.
    var staleInterval: TimeInterval = 60

    private static let historyLength = 40

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        do {
            // scanForNetworks blocks for a few seconds, so keep it off the main actor.
            let result = try await Task.detached(priority: .userInitiated) {
                try WiFiScanner.performScan()
            }.value
            merge(result)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        lastScanDate = .now
    }

    private func merge(_ result: ScanResult) {
        interfaceName = result.interfaceName
        let now = Date.now

        var byID = Dictionary(networks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in byID.keys { byID[id]?.missedScans += 1 }

        for var fresh in result.networks {
            if let previous = byID[fresh.id] {
                fresh.firstSeen = previous.firstSeen
                fresh.rssiHistory = Array((previous.rssiHistory + [fresh.rssi]).suffix(Self.historyLength))
            }
            byID[fresh.id] = fresh
        }

        networks = byID.values
            .filter { now.timeIntervalSince($0.lastSeen) <= staleInterval }
            .sorted { ($0.rssi, $0.id) > ($1.rssi, $1.id) }
    }

    nonisolated static func performScan() throws -> ScanResult {
        guard let interface = CWWiFiClient.shared().interface() else { throw ScanError.noInterface }
        guard interface.powerOn() else { throw ScanError.poweredOff }

        let found: Set<CWNetwork>
        do {
            found = try interface.scanForNetworks(withName: nil, includeHidden: true)
        } catch {
            throw ScanError.failed(error.localizedDescription)
        }

        let connectedBSSID = interface.bssid()?.lowercased()
        let connectedSSID = interface.ssid()
        let connectedChannel = interface.wlanChannel()?.channelNumber
        let now = Date.now

        let networks = found.enumerated().map { index, network in
            WiFiNetwork(
                network,
                fallbackIndex: index,
                connectedBSSID: connectedBSSID,
                connectedSSID: connectedSSID,
                connectedChannel: connectedChannel,
                seenAt: now
            )
        }
        return ScanResult(interfaceName: interface.interfaceName, networks: networks)
    }
}

private extension WiFiNetwork {
    init(
        _ network: CWNetwork,
        fallbackIndex: Int,
        connectedBSSID: String?,
        connectedSSID: String?,
        connectedChannel: Int?,
        seenAt date: Date
    ) {
        let bssid = network.bssid?.lowercased()
        let channel = network.wlanChannel
        let channelNumber = channel?.channelNumber ?? 0
        let band = WiFiBand(channel?.channelBand)
        let (security, isSecured) = Self.describeSecurity(of: network)

        let isConnected: Bool
        if let bssid, let connectedBSSID {
            isConnected = bssid == connectedBSSID
        } else {
            isConnected = network.ssid != nil
                && network.ssid == connectedSSID
                && channelNumber == connectedChannel
        }

        self.init(
            // Without Location Services macOS withholds the BSSID, so identity is best-effort.
            id: bssid ?? "unknown-\(band.rawValue)-\(channelNumber)-\(network.ssid ?? "")-\(fallbackIndex)",
            ssid: network.ssid,
            bssid: bssid,
            rssi: network.rssiValue,
            noise: network.noiseMeasurement,
            channel: channelNumber,
            band: band,
            channelWidthMHz: Self.widthMHz(channel?.channelWidth),
            security: security,
            isSecured: isSecured,
            beaconInterval: network.beaconInterval,
            countryCode: network.countryCode,
            isConnected: isConnected,
            firstSeen: date,
            lastSeen: date,
            rssiHistory: [network.rssiValue]
        )
    }

    static func widthMHz(_ width: CWChannelWidth?) -> Int {
        switch width {
        case .width40MHz: 40
        case .width80MHz: 80
        case .width160MHz: 160
        default: 20
        }
    }

    /// Strongest security mode the network advertises.
    static func describeSecurity(of network: CWNetwork) -> (String, Bool) {
        let modes: [(CWSecurity, String)] = [
            (.wpa3Enterprise, "WPA3 Enterprise"),
            (.wpa3Personal, "WPA3 Personal"),
            (.wpa3Transition, "WPA2/WPA3 Personal"),
            (.wpa2Enterprise, "WPA2 Enterprise"),
            (.wpa2Personal, "WPA2 Personal"),
            (.enterprise, "WPA/WPA2 Enterprise"),
            (.personal, "WPA/WPA2 Personal"),
            (.wpaEnterprise, "WPA Enterprise"),
            (.wpaPersonal, "WPA Personal"),
            (.dynamicWEP, "Dynamic WEP"),
            (.WEP, "WEP"),
            (.OWE, "Enhanced Open"),
            (.oweTransition, "Enhanced Open (Transition)"),
        ]
        for (mode, name) in modes where network.supportsSecurity(mode) {
            return (name, mode != .OWE && mode != .oweTransition)
        }
        return network.supportsSecurity(.none) ? ("Open", false) : ("Unknown", false)
    }
}

private extension WiFiBand {
    init(_ band: CWChannelBand?) {
        switch band {
        case .band2GHz: self = .ghz2_4
        case .band5GHz: self = .ghz5
        case .band6GHz: self = .ghz6
        default: self = .unknown
        }
    }
}
