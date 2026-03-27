# Floatilla

Touch-first, open-source marine chart plotter and social network for sailors, built with Flutter. Designed for sailors using a tablet or phone at the helm.

## Features

- **Chart display** — OpenStreetMap + OpenSeaMap overlay with course-up mode and scale bar
- **GPS tracking** — Real-time vessel position from device GPS
- **NMEA input** — TCP and UDP connections for heading, depth, wind, SOG/COG
- **AIS targets** — Decode AIS messages (types 1-5, 18, 19, 21), display on chart with CPA/TCPA alarm
- **Routes & waypoints** — Create, edit, navigate routes; GPX import/export
- **Instrument panel** — SOG, COG, heading, depth, wind speed/angle, XTE
- **Offline charts** — Download tile regions for use without internet
- **Night mode** — Red-tinted theme to preserve dark adaptation
- **Onboarding** — First-launch setup for NMEA and GPS permissions

## Requirements

- Flutter SDK 3.x (Dart SDK ^3.11.1)
- Android API 21+ / iOS 13+
- Xcode 15+ (for iOS builds)
- Android Studio or Android SDK command-line tools (for Android builds)

## Setup

```bash
# Clone the repository
git clone https://github.com/craigrallen/flutter_plotter.git
cd flutter_plotter

# Install dependencies
flutter pub get

# Run on connected device or emulator
flutter run

# Release builds
flutter build apk --release
flutter build ios --no-codesign
```

### iOS additional setup

```bash
cd ios && pod install && cd ..
```

## Connecting an NMEA Source

FlutterPlotter receives instrument data over TCP or UDP from your boat's NMEA multiplexer or Wi-Fi gateway.

1. **Find your multiplexer IP** — Common devices: Actisense, Yacht Devices, Digital Yacht. Check your network for the device IP (often `192.168.1.x` or `10.10.10.x`).
2. **Configure in app** — Go to Settings > NMEA Source, enter the host IP and port (default `10110`), select TCP or UDP.
3. **Supported sentences** — RMC, GLL, VTG, HDT, DBT, MWV, VDM/VDO (AIS)
4. **Testing** — Use the NMEA Debug screen (Settings > NMEA Debug) to verify sentences are arriving.

**Tip:** For testing without hardware, use tools like `kplex` or `gpsfeed+` to stream sample NMEA data to a TCP port.

## Downloading Offline Charts

1. Go to Settings > Offline Tiles
2. Pan/zoom the map to the region you want
3. Select zoom levels and tap Download
4. Downloaded tiles are stored locally and used automatically when offline

Tiles are sourced from OpenStreetMap with OpenSeaMap overlay. Please respect tile server usage policies.

## Architecture

```
lib/
├── main.dart                    Entry point, Riverpod setup, theme switching
├── core/
│   ├── ais/                     AIS bit-level decoder + message types (1-5, 18, 19, 21)
│   ├── gpx/                     GPX import/export (routes, waypoints)
│   ├── nav/                     Navigation math: haversine, bearing, XTE, route nav
│   └── nmea/                    NMEA sentence parsing, TCP/UDP sources
│       └── sentences/           Individual sentence parsers (RMC, GLL, VTG, HDT, DBT, MWV, VDM)
├── data/
│   ├── models/                  Data classes: VesselState, AisTarget, Route, Waypoint
│   ├── providers/               Riverpod providers: vessel, AIS, NMEA, settings, charts, routes
│   └── repositories/            SQLite persistence for routes and waypoints
└── ui/
    ├── ais/                     AIS target list screen
    ├── chart/                   Main chart screen + map layers (vessel, AIS, route, scale bar)
    ├── instruments/             Instrument panel with tiles (SOG, COG, depth, wind, etc.)
    ├── onboarding/              First-launch setup wizard
    ├── routes/                  Route list + route editor
    ├── settings/                Settings, NMEA debug, offline tiles
    └── shared/                  App shell (bottom nav), day/night themes
```

### Key design decisions

| Area | Choice | Rationale |
|---|---|---|
| State | Riverpod `StateNotifier` | Reactive, testable, no code-gen required |
| Maps | flutter_map 6.x | Open-source, raster tiles, layer compositing |
| Caching | flutter_map_tile_caching | MBTiles-backed offline tile storage |
| Persistence | SQLite + SharedPreferences | Routes/waypoints in SQLite, settings in prefs |
| NMEA | Raw TCP/UDP sockets | Direct connection to standard marine multiplexers |
| AIS | Custom bit-level decoder | Full control, no external dependency |

## Stack

| Layer | Technology |
|---|---|
| UI framework | Flutter 3.x / Material 3 |
| Map | flutter_map 6.x |
| Tile caching | flutter_map_tile_caching 9.x |
| GPS | geolocator 12.x |
| State management | flutter_riverpod 2.5.x |
| Persistence | sqflite 2.3.x / shared_preferences |
| Nav math | Custom Dart (haversine, bearing, XTE) |

## License

Open source. License TBD.
