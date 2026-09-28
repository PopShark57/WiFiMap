import SwiftUI

struct NetworkListView: View {
    let networks: [WiFiNetwork]
    @Binding var selection: WiFiNetwork.ID?

    var body: some View {
        let connected = networks.filter(\.isConnected)
        let nearby = networks.filter { !$0.isConnected }

        List(selection: $selection) {
            if !connected.isEmpty {
                Section("Connected") {
                    ForEach(connected) { NetworkRow(network: $0) }
                }
            }
            Section("Nearby") {
                ForEach(nearby) { NetworkRow(network: $0) }
            }
        }
        .overlay {
            if networks.isEmpty {
                Text("No matching networks")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NetworkRow: View {
    let network: WiFiNetwork

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi", variableValue: network.signalQuality)
                .foregroundStyle(network.band.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(network.displayName)
                    .italic(network.isHidden)
                    .fontWeight(network.isConnected ? .semibold : .regular)
                    .lineLimit(1)
                Text("Ch \(network.channel) · \(network.band.title) · \(network.channelWidthMHz) MHz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if network.isSecured {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(network.security)
            }
            Text("\(network.rssi)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .opacity(max(network.presenceOpacity, 0.5))
        .tag(network.id)
    }
}
