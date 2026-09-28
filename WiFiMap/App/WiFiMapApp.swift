import SwiftUI

@main
struct WiFiMapApp: App {
    @State private var scanner = WiFiScanner()
    @State private var location = LocationAuthorization()

    var body: some Scene {
        Window("WiFiMap", id: "main") {
            ContentView()
                .environment(scanner)
                .environment(location)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Scan Now") {
                    Task { await scanner.scan() }
                }
                .keyboardShortcut("r")
                .disabled(scanner.isScanning)
            }
        }
    }
}
