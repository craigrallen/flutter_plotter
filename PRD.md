# PRD: FlutterPlotter — Touch-First Marine Chart Plotter
**Version**: 0.1  
**Date**: 2026-03-26  
**Status**: Draft

---

## 1. Problem

OpenCPN is the best open-source chart plotter available, but its Android port is a desktop app on a touchscreen — tiny buttons, complex menus, no touch-native interaction. Sailors using tablets or phones at the helm need something designed for touch from the ground up.

## 2. Goal

Build a touch-first, open-source marine chart plotter in Flutter. Feature parity with OpenCPN is not the goal. The goal is to cover the 80% of what sailors actually use underway, in a UI that works with one hand on a moving boat.

## 3. Target Users

- Recreational sailors and motor boaters
- Using a tablet or large phone at the helm
- Primarily coastal/inshore navigation (not offshore passage making)
- NMEA data available over WiFi (from a multiplexer like Yacht Devices, Vesper, or similar)

## 4. Out of Scope (v1)

- S57 vector ENC rendering
- Plugin/extension system
- Tides and currents
- Radar overlay
- GRIB weather files
- USB serial NMEA input (WiFi only for v1)
- Route optimization / weather routing
- Log book / passage recording

---

## 5. Features (v1)

### 5.1 Chart Display
- Raster nautical tile display via `flutter_map`
- Tile sources: OpenSeaMap (overlay), NOAA RNC (US waters), OpenStreetMap base
- Offline tile caching: user selects area + zoom range to download
- Smooth pan/pinch zoom
- North-up and course-up modes
- Scale bar

### 5.2 Own Vessel
- Position from device GPS (primary) or NMEA GLL/RMC sentences (preferred when available)
- SOG + COG from NMEA RMC or VTG
- Vessel icon on chart, rotates with COG
- "Centre on vessel" button
- GPS accuracy indicator

### 5.3 AIS Targets
- Parse NMEA VDM/VDO sentences (AIS messages type 1, 2, 3, 5, 18, 21, 24)
- Render targets as icons on chart — colour-coded by CPA/TCPA risk
- Tap target for vessel details: name, MMSI, COG, SOG, ship type
- Target list view (sortable by CPA)
- Stale target removal (configurable timeout, default 10 min)
- CPA/TCPA calculation with configurable alarm threshold

### 5.4 Routes & Waypoints
- Tap-and-hold on chart to place waypoint
- Connect waypoints into a route
- Route active/inactive state
- XTE (cross-track error) display when route active
- Distance + ETA to next waypoint (based on current SOG)
- Waypoints stored locally (SQLite)
- GPX import/export

### 5.5 Instrument Panel
- Collapsible overlay panel (slide up from bottom)
- Displays: SOG, COG, depth (DBT/DBS), wind speed/angle (MWV), heading (HDG/HDT), VMG
- Values parsed from NMEA stream
- Configurable which instruments show

### 5.6 NMEA Input
- TCP client mode: connect to IP:port (most multiplexers)
- UDP listen mode: for broadcast multiplexers
- NMEA 0183 sentence parsing
- Connection status indicator
- Raw NMEA debug view (toggleable)

### 5.7 Settings
- NMEA source configuration (host, port, protocol)
- AIS alarm thresholds (CPA distance, TCPA time)
- Chart tile source selection
- Offline cache management (view size, clear)
- Units (metric/imperial/nautical)
- Display: night mode (red-tinted for dark adaptation)

---

## 6. Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| UI framework | Flutter 3.x | Cross-platform, touch-native |
| Map | flutter_map 6.x | Actively maintained, flexible layers |
| Tile caching | flutter_map_tile_caching | MBTiles + bulk download |
| GPS | geolocator | Standard, well-maintained |
| Local DB | sqflite | Routes, waypoints, AIS history |
| State management | Riverpod | Clean, testable |
| NMEA | Custom Dart library | Simple enough, full control |
| AIS decoder | Custom Dart library | Port of known-good C logic |
| Nav math | Custom Dart library | Bearing, distance, CPA/TCPA, XTE |

---

## 7. Architecture

```
lib/
  core/
    nmea/
      sentence_parser.dart       ← splits raw stream into sentences
      sentences/                 ← typed sentence classes (RMC, VDM, DBT…)
    ais/
      decoder.dart               ← bit-unpacks AIS payload
      messages/                  ← typed message classes (type 1, 5, 18…)
      target_manager.dart        ← maintains AIS target state, staleness
    nav/
      geo.dart                   ← haversine, bearing, rhumb line
      cpa.dart                   ← CPA/TCPA calculation
      xte.dart                   ← cross-track error
    nmea_source/
      tcp_source.dart
      udp_source.dart
      nmea_stream.dart           ← unified stream from any source
  data/
    models/
      waypoint.dart
      route.dart
      ais_target.dart
      vessel_state.dart          ← own ship: position, sog, cog, heading
    repositories/
      waypoint_repository.dart
      route_repository.dart
    providers/                   ← Riverpod providers
  ui/
    chart/
      chart_screen.dart          ← main screen
      layers/
        vessel_layer.dart
        ais_layer.dart
        route_layer.dart
        waypoint_layer.dart
    instruments/
      instrument_panel.dart
      instrument_tile.dart
    routes/
      route_list_screen.dart
      route_editor_screen.dart
    ais/
      target_list_screen.dart
      target_detail_sheet.dart
    settings/
      settings_screen.dart
      nmea_config_screen.dart
      offline_tiles_screen.dart
    shared/
      night_mode.dart
      theme.dart
  main.dart
```

---

## 8. Build Plan

### Phase 1 — Foundation (Week 1-2)
**Goal: chart on screen with your position**

- [ ] Create Flutter project (`flutter_plotter`)
- [ ] Add flutter_map, geolocator, riverpod dependencies
- [ ] Implement tile layer: OpenSeaMap + base layer
- [ ] Implement `VesselLayer` — device GPS position on chart
- [ ] Pan/zoom working
- [ ] Course-up mode
- [ ] Scale bar
- [ ] Basic app shell (bottom nav: Chart / Routes / AIS / Settings)

**Deliverable**: app runs on device, shows chart, shows your position

---

### Phase 2 — NMEA + AIS (Week 3-4)
**Goal: AIS targets on chart**

- [ ] `NmeaSource` — TCP client + UDP listener
- [ ] `SentenceParser` — tokenise raw stream, identify sentence type
- [ ] Implement: GLL, RMC, VTG, HDT, DBT, MWV sentence parsers
- [ ] `VesselState` provider fed by NMEA (falls back to GPS)
- [ ] AIS decoder — bit-unpack NMEA VDM payload
- [ ] Message types: 1/2/3 (position), 18 (class B), 5 (static/voyage), 24 (part A/B)
- [ ] `AisTargetManager` — store, update, expire targets
- [ ] `AisLayer` — render targets on chart with COG vector
- [ ] CPA/TCPA calculation
- [ ] Tap target → detail sheet
- [ ] AIS target list screen

**Deliverable**: connect to WiFi NMEA source, see AIS traffic on chart

---

### Phase 3 — Routes & Waypoints (Week 5-6)
**Goal: plan and follow a route**

- [ ] SQLite schema + repository for waypoints + routes
- [ ] Tap-and-hold on chart to place waypoint
- [ ] Route editor: add/remove/reorder waypoints
- [ ] `RouteLayer` — draw route on chart
- [ ] Active route: highlight next waypoint
- [ ] XTE calculation + display
- [ ] Distance + bearing to next waypoint
- [ ] ETA based on current SOG
- [ ] GPX import/export

**Deliverable**: plan a route, activate it, get XTE guidance

---

### Phase 4 — Instruments + Polish (Week 7-8)
**Goal: usable at the helm**

- [ ] Instrument panel (slide-up)
- [ ] Instrument tiles: SOG, COG, depth, wind, heading, VMG
- [ ] Night mode (red-tinted UI)
- [ ] Offline tile download (area selection + zoom range)
- [ ] Settings screen — all config
- [ ] Raw NMEA debug view
- [ ] CPA alarm (sound + visual)
- [ ] Connection status + reconnect logic
- [ ] Performance pass — chart rendering at 60fps on mid-range tablet

**Deliverable**: full MVP, usable on the water

---

### Phase 5 — Release (Week 9-10)
- [ ] iOS + Android builds
- [ ] TestFlight + Play Store internal testing
- [ ] README + setup docs
- [ ] Basic onboarding flow (first-launch NMEA setup)

---

## 9. Repo

- **GitHub**: `craigrallen/flutter_plotter` (new repo — not inside OpenCPN fork)
- **Branch strategy**: `main` (stable), `dev` (active), feature branches

---

## 10. Open Questions

1. **Tile licensing**: NOAA tiles are US-only. For Swedish/European waters, best free source is OpenSeaMap vector overlay on top of OSM. Paid option: Navionics tile API (expensive). Decision needed before offline download is built.
2. **MMSI database**: For AIS vessel name lookup when type-5 message hasn't been received yet — use a public MMSI lookup API or bundle a local DB?
3. **Chart datum**: OpenSeaMap/OSM tiles are WGS84. NMEA GPS is WGS84. Should be fine but worth noting.
4. **iPad support**: flutter_map works fine on iPad. Side-by-side instrument panel layout for larger screens worth considering in Phase 4.
