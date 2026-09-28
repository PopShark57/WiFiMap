import AppKit
import CoreLocation
import Observation

/// macOS only reveals SSIDs and BSSIDs to apps that hold Location Services access.
@MainActor
@Observable
final class LocationAuthorization: NSObject, CLLocationManagerDelegate {
    private(set) var status: CLAuthorizationStatus
    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        status == .authorizedAlways
    }

    var canPrompt: Bool { status == .notDetermined }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        NSWorkspace.shared.open(url)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.status = status }
    }
}
