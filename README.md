# FlutterPlotter

Touch-first, open-source marine chart plotter built with Flutter. Designed for sailors using a tablet or phone at the helm.

## Stack

| Layer | Choice |
|---|---|
| UI framework | Flutter 3.x |
| Map | flutter_map 6.x |
| Tile caching | flutter_map_tile_caching |
| GPS | geolocator |
| State management | Riverpod |
| Nav math | Custom Dart (haversine, bearing) |

## How to Run

```bash
# Install dependencies
flutter pub get

# Run on connected device or emulator
flutter run
```

Requires Flutter SDK 3.x. Targets Android and iOS.

## Phase Status

- [x] **Phase 1** — App shell, chart display (OpenSeaMap + OSM), GPS vessel position, course-up mode, scale bar
- [ ] **Phase 2** — NMEA input (TCP/UDP), AIS decoder, AIS targets on chart
- [ ] **Phase 3** — Routes & waypoints, GPX import/export
- [ ] **Phase 4** — Instrument panel, night mode, offline tiles, settings
- [ ] **Phase 5** — Release builds, TestFlight, Play Store

## Architecture

```
lib/
  core/nav/          — navigation math (haversine, bearing)
  data/models/       — vessel state, (future: AIS targets, waypoints)
  data/providers/    — Riverpod providers, tile provider abstraction
  ui/chart/          — main chart screen + layers (vessel, scale bar)
  ui/routes/         — route list (Phase 3)
  ui/ais/            — AIS target list (Phase 2)
  ui/settings/       — settings (Phase 4)
  ui/shared/         — themes, app shell
```

## License

Open source. License TBD.
