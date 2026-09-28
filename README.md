# WiFiMap

A macOS app that scans nearby Wi-Fi access points with CoreWLAN and shows them as a map.

- **Radar**: this Mac sits at the center. Stronger signals plot closer to it. Scans carry no
  direction, so each network's angle is a stable hash of its SSID, and access points of the
  same network cluster together.
- **Channels**: the classic analyzer view. Each access point is drawn across the frequencies
  it occupies (bonded channels included), so overlap is easy to see.
- **Inspector**: RSSI, noise, SNR, channel/width, security, BSSID and an RSSI history chart.

## Build

Requires Xcode 16+ (macOS 15 deployment target) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
xcodebuild -scheme WiFiMap -derivedDataPath build build
open build/Build/Products/Debug/WiFiMap.app
```

`WiFiMap.xcodeproj` is generated from `project.yml`, so edit `project.yml` rather than the project.

The app icon is `WiFiMap/AppIcon.icon`, an Icon Composer document. Open it in Icon Composer
(bundled with Xcode) to edit it.

## Notes

- **Location Services is required.** macOS withholds SSIDs and BSSIDs from apps without it.
  The app asks on first launch. Without access, networks still appear but are unnamed.
- **Single scans are lossy.** One CoreWLAN scan usually catches only part of what's nearby.
  The app keeps an access point for 60 s after it was last seen, and fades it as it misses
  consecutive scans.
