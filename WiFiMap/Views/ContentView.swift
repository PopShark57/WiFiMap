import SwiftUI

struct ContentView: View {
    @Environment(WiFiScanner.self) private var scanner
    @Environment(LocationAuthorization.self) private var location

    @State private var selection: WiFiNetwork.ID?
    @State private var searchText = ""
    @State private var showInspector = true
    @SceneStorage("mapMode") private var mode: MapMode = .radar
    @SceneStorage("bandFilter") private var bandFilter: BandFilter = .all
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("refreshInterval") private var refreshInterval = 10
    @AppStorage("showLabels") private var showLabels = true

    private var visibleNetworks: [WiFiNetwork] {
        scanner.networks.filter { network in
            (bandFilter == .all || bandFilter.bands.contains(network.band))
                && (searchText.isEmpty || network.matches(searchText))
        }
    }

    private var selectedNetwork: WiFiNetwork? {
        selection.flatMap { id in scanner.networks.first { $0.id == id } }
    }

    var body: some View {
        NavigationSplitView {
            NetworkListView(networks: visibleNetworks, selection: $selection)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 400)
        } detail: {
            VStack(spacing: 0) {
                banners
                map
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StatusBar(count: visibleNetworks.count, total: scanner.networks.count)
            }
            .inspector(isPresented: $showInspector) {
                NetworkDetailView(network: selectedNetwork)
                    .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
            }
        }
        .navigationTitle("WiFiMap")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Name, BSSID or channel")
        .toolbar { toolbar }
        .task(id: autoRefresh) { await scanLoop() }
        .onChange(of: location.isAuthorized) { _, authorized in
            if authorized { Task { await scanner.scan() } }
        }
        .onAppear {
            if location.canPrompt { location.request() }
        }
    }

    @ViewBuilder
    private var map: some View {
        if scanner.networks.isEmpty {
            if scanner.isScanning || scanner.lastScanDate == nil {
                ProgressView("Scanning for networks…")
            } else {
                ContentUnavailableView(
                    "No Networks Found",
                    systemImage: "wifi.slash",
                    description: Text(scanner.lastError ?? "Nothing is in range right now.")
                )
            }
        } else {
            switch mode {
            case .radar:
                RadarMapView(networks: visibleNetworks, selection: $selection, showLabels: showLabels)
            case .channels:
                ChannelMapView(networks: visibleNetworks, bands: bandFilter.bands, selection: $selection)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if !location.isAuthorized {
            Banner(
                systemImage: "location.slash.fill",
                tint: .yellow,
                title: "Network names are hidden",
                message: "macOS only reveals Wi-Fi names and BSSIDs to apps with Location Services access."
            ) {
                if location.canPrompt {
                    Button("Allow Access") { location.request() }
                } else {
                    Button("Open Privacy Settings…") { location.openPrivacySettings() }
                }
            }
        }
        if let error = scanner.lastError, !scanner.networks.isEmpty {
            Banner(systemImage: "exclamationmark.triangle.fill", tint: .red, title: "Last scan failed", message: error) {
                Button("Retry") { Task { await scanner.scan() } }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $mode) {
                ForEach(MapMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
        }
        ToolbarItemGroup {
            Picker("Band", selection: $bandFilter) {
                ForEach(BandFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .help("Filter by band")

            Menu {
                Toggle("Show Labels", isOn: $showLabels)
                Divider()
                Toggle("Scan Automatically", isOn: $autoRefresh)
                Picker("Scan Every", selection: $refreshInterval) {
                    ForEach([5, 10, 30, 60], id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .disabled(!autoRefresh)
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
            }
            .help("View and scan options")

            Button {
                Task { await scanner.scan() }
            } label: {
                if scanner.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Scan Now", systemImage: "arrow.clockwise")
                }
            }
            .disabled(scanner.isScanning)
            .help("Scan now (⌘R)")

            Button {
                showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide details")
        }
    }

    private func scanLoop() async {
        guard autoRefresh else {
            if scanner.lastScanDate == nil { await scanner.scan() }
            return
        }
        while !Task.isCancelled {
            await scanner.scan()
            try? await Task.sleep(for: .seconds(refreshInterval))
        }
    }
}

private struct Banner<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct StatusBar: View {
    @Environment(WiFiScanner.self) private var scanner
    let count: Int
    let total: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(count == total ? "\(total) access points" : "\(count) of \(total) access points")
            if let date = scanner.lastScanDate {
                Text("·")
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("Last scan \(date, format: .relative(presentation: .named))")
                }
            }
            Spacer()
            if let name = scanner.interfaceName {
                Label(name, systemImage: "wifi").labelStyle(.titleAndIcon)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
