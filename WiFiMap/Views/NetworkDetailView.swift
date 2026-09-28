import Charts
import SwiftUI

struct NetworkDetailView: View {
    let network: WiFiNetwork?

    var body: some View {
        if let network {
            Form {
                Section {
                    header(network)
                }
                Section("Signal") {
                    LabeledContent("RSSI", value: "\(network.rssi) dBm")
                    LabeledContent("Noise", value: network.noise < 0 ? "\(network.noise) dBm" : "—")
                    LabeledContent("SNR", value: network.snr.map { "\($0) dB" } ?? "—")
                    Gauge(value: network.signalQuality) {
                        Text("Quality")
                    } currentValueLabel: {
                        Text(network.signalQuality, format: .percent.precision(.fractionLength(0)))
                    }
                    .tint(qualityColor(network.signalQuality))
                }
                Section("History") {
                    RSSIHistoryChart(samples: network.rssiHistory, color: network.band.color)
                        .frame(height: 110)
                }
                Section("Radio") {
                    LabeledContent("Channel", value: "\(network.channel)")
                    LabeledContent("Band", value: network.band.title)
                    LabeledContent("Width", value: "\(network.channelWidthMHz) MHz")
                    if let frequency = network.frequencyMHz {
                        LabeledContent("Frequency", value: "\(Int(frequency)) MHz")
                    }
                    LabeledContent("Beacon Interval", value: "\(network.beaconInterval) TU")
                    if let country = network.countryCode {
                        LabeledContent("Country", value: country)
                    }
                }
                Section("Identity") {
                    LabeledContent("SSID") {
                        Text(network.ssid.flatMap { $0.isEmpty ? nil : $0 } ?? "Hidden").textSelection(.enabled)
                    }
                    LabeledContent("BSSID") {
                        Text(network.bssid ?? "Unavailable").monospaced().textSelection(.enabled)
                    }
                    LabeledContent("Security", value: network.security)
                }
                Section("Seen") {
                    LabeledContent("First Seen") { Text(network.firstSeen, style: .time) }
                    LabeledContent("Last Seen") { Text(network.lastSeen, style: .time) }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "No Network Selected",
                systemImage: "wifi",
                description: Text("Select a network on the map or in the list.")
            )
        }
    }

    private func qualityColor(_ quality: Double) -> Color {
        switch quality {
        case 0.66...: .green
        case 0.4...: .yellow
        case 0.2...: .orange
        default: .red
        }
    }

    private func header(_ network: WiFiNetwork) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi", variableValue: network.signalQuality)
                .font(.title)
                .foregroundStyle(network.band.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(network.displayName)
                    .font(.title3.weight(.semibold))
                    .italic(network.isHidden)
                if network.isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                } else if network.missedScans > 1 {
                    Text("Missed the last \(network.missedScans) scans")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RSSIHistoryChart: View {
    let samples: [Int]
    let color: Color

    var body: some View {
        if samples.count < 2 {
            Text("Collecting samples…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(Array(samples.enumerated()), id: \.offset) { index, rssi in
                AreaMark(x: .value("Scan", index), yStart: .value("Floor", -100), yEnd: .value("RSSI", rssi))
                    .foregroundStyle(color.opacity(0.15).gradient)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Scan", index), y: .value("RSSI", rssi))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: -100 ... -20)
            .chartYAxis {
                AxisMarks(values: [-90, -70, -50, -30])
            }
        }
    }
}
