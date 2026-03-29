# Floatilla

> A touch-first, Signal K-native marine navigation platform for Android and iOS.

> **Note:** This repository is named `flutter_plotter` but the product is called **Floatilla**.
> The repo will be renamed to `floatilla` in a future milestone to match the product name.

---

## Overview

Floatilla is a mobile-first chart plotter and social platform for recreational sailors and power boaters. It combines real-time chart navigation, Signal K instrument integration, fleet social features, and a cloud logbook in a single modern app — built with Flutter for Android and iOS.

### Key differentiators

| Feature | Floatilla | iNavX / SeaNav | Garmin / Raymarine |
|---|---|---|---|
| Signal K native | Yes | No | No |
| Real-time fleet social | Yes | No | No |
| AI passage briefing | Yes | No | No |
| Cloud logbook | Yes | No | Partial |
| Open weather (no subscription) | Yes | No | No |
| Touch-first UX | Yes | Partial | No |
| Open source | Yes | No | No |

### Platform support

- **Android** 6.0+ (API 23+) — primary target
- **iOS** 14+ — planned

---

## Screenshots

| Chart | Plugin Hub | Passage Briefing |
|---|---|---|
| [Screenshot] | [Screenshot] | [Screenshot] |

| AIS CPA | GRIB Weather | Cloud Logbook |
|---|---|---|
| [Screenshot] | [Screenshot] | [Screenshot] |

---

## Features

All 40+ features are accessible from the **Plugin Hub** screen, grouped by category.

### Navigation & Planning

| Feature | Description |
|---|---|
| Passage Plan | Multi-leg passage planning with waypoints, ETA, distance |
| Route Planner | Create, edit, and sync routes with cloud backup |
| Tidal Gates | 97-window departure solver using NOAA currents API |
| Departure Planner | 4-window weather comparison, Open-Meteo scoring |
| Dead Reckoning | Position extrapolation from last known fix |
| Celestial Nav | Sun/moon/planet sights using Meeus algorithms, sight reduction |
| Waypoint Calculator | Bearing+distance to lat/lng and reverse |
| CDI | Highway-style course deviation indicator |
| Fuel Range | Range calculator with chart range ring overlay |
| Night Mode | CartoDB dark tiles, helm-readable dimmed instruments |

### Safety & Alerts

| Feature | Description |
|---|---|
| AIS Collision (CPA) | Smart CPA/TCPA ranked alerting with COLREGS guidance |
| Anchor Watch (Scope) | Scope-aware drag detection (chain length + depth + catenary) |
| Boat Health Monitor | Signal K sensor alerting with configurable alert rules |
| MOB | Man overboard drift prediction (IAMSAR leeway model, 120-min) |
| SAR Patterns | IAMSAR expanding square, sector, and parallel sweep patterns |

### Weather & Environment

| Feature | Description |
|---|---|
| GRIB Weather | GFS, ECMWF, ICON models via Open-Meteo with offline save |
| Tidal Currents | Current overlay from NOAA |
| Weather Overlay | Wind, pressure, precipitation overlay on chart |
| Briefing | Daily 7-day weather briefing (Open-Meteo) |
| Wind | Wind history trail + wind rose from Signal K buffer |
| Currents | Ocean current overlay (Marine API, 0–48h forecast) |
| Swell | Swell component breakdown (primary/wind wave, comfort rating) |

### Instruments & Data

| Feature | Description |
|---|---|
| Signal K Dashboard | Live readout of all Signal K paths |
| NMEA Multiplexer | Live NMEA sentence stream with checksum validation |
| Engine Dashboard | RPM, hours, temperature from Signal K propulsion.* |
| Polar Performance | CSV polar upload, VMG targets, live TWA/TWS overlay |
| Radar Simulator | PPI display from AIS targets with animated sweep |
| Tanks | Tank monitoring dashboard (Signal K tanks.*) |
| Trim Assistant | Heel + VMG + polar → sail trim advice, A–F grade |

### Voyage

| Feature | Description |
|---|---|
| Voyage Logger | Auto-detect start/stop by SOG, SQLite storage |
| Voyage Score | Health scoring: VMG%, tack count, wind shift response |
| Cloud Logbook | Captain's Log + Ship's Log with cloud sync (Logbook Pro) |
| AIS History Trail | 24-hour position history per AIS vessel |
| Track Comparison | Up to 4 tracks, speed color mode, divergence points |

### Social & Community

| Feature | Description |
|---|---|
| Floatilla Feed | Fleet position sharing, social feed, messaging |
| Anchorages | Social anchorage status — live boat count, check-in/out |
| Passage Briefing (AI) | LLM-powered briefing via Anthropic claude-3-5-haiku (streaming) |
| Marinas | Marina community layer — fuel, water, depth, facilities |

### Racing

| Feature | Description |
|---|---|
| Race Start Timer | Laylines, favoured end, time-on-distance countdown |
| Deviation Table | Compass deviation vs GPS — deviation card builder |

---

## Architecture

```
Flutter (Dart)
  └── Riverpod 2 (StateNotifier pattern)
        ├── Signal K WebSocket (real-time instrument data)
        ├── NMEA 0183/2000 (TCP/UDP via Signal K server)
        ├── Floatilla REST API (Railway / PostgreSQL)
        ├── Open-Meteo API (weather, waves — no key required)
        ├── NOAA CO-OPS API (tides, currents — no key required)
        └── OpenStreetMap + OpenSeaMap (chart tiles)
```

- **Flutter** — cross-platform UI, single codebase for Android/iOS
- **Riverpod 2** — `StateNotifierProvider<Notifier, State>` pattern throughout
- **Signal K** — WebSocket stream at `ws://host:3000/signalk/v1/stream`
- **Node.js/Express** backend on Railway with PostgreSQL
- **Open-Meteo + NOAA** for all weather and tide data — no API keys needed
- **flutter_map** with OpenStreetMap + OpenSeaMap tile layers

---

## Getting Started

### Prerequisites

- [Flutter 3.x SDK](https://docs.flutter.dev/get-started/install)
- Android Studio (for Android) or Xcode 14+ (for iOS)
- Android SDK 34+ / iOS 14+

### Build

```bash
# Install dependencies
flutter pub get

# Run in debug mode (connected device or emulator)
flutter run

# Release builds
flutter build apk --release          # Android APK
flutter build appbundle --release    # Android AAB (Play Store)
flutter build ios --release          # iOS
```

### Environment

Server URL is configured in **Settings → Server URL**. The default points to the Railway deployment. For local development, run `server/` locally and set the URL to `http://localhost:8080`.

---

## Project Structure

```
lib/
  core/                     # Business logic, services, utilities
    ais/                    # AIS decoder (NMEA VDM/VDO messages)
    anchor/                 # Anchor watch logic
    floatilla/              # Floatilla cloud service, models
      floatilla_service.dart
      logbook_service.dart
      voyage_logger_service.dart
      track_comparison_service.dart
    nav/                    # Navigation math (geo, XTE, route nav)
    nmea/                   # NMEA stream handling (TCP/UDP sources)
    routing/                # A* route engine, path smoothing
    signalk/                # Signal K WebSocket connection + parser
    tides/                  # Tide station + tide service
    utils/
      geo_utils.dart        # Shared distance/bearing calculations
      error_handler.dart    # Shared error logging (logError())
    weather/                # Open-Meteo weather service
  data/
    models/                 # Data models (AIS target, waypoint, route, etc.)
    providers/              # Riverpod state providers
    repositories/           # Route + waypoint repositories
  ui/
    chart/                  # Main chart screen + map layers
    floatilla/              # All plugin screens (40+)
    instruments/            # Instrument panel, strip, sidebar, tiles
    routes/                 # Route editor + list screens
    settings/               # App settings, vessel profile editor
    shared/                 # App shell, responsive helpers, theme
    signalk/                # Signal K dashboard
    tides/                  # Tide panel
    weather/                # Weather overlay screen

server/                     # Node.js backend
  index.js                  # Express API server (all endpoints)
  package.json
```

---

## Backend (server/)

The backend is a Node.js/Express REST API deployed on Railway with a managed PostgreSQL database.

- **Auth:** JWT (bcrypt password hashing, token expiry)
- **Social:** Friend system, fleet positions, messaging, anchorage check-in/out, hazard reports
- **Sync:** Cloud route/waypoint sync (PUT/GET per user)
- **Logbook:** Captain's Log + Ship's Log with Logbook Pro gating (`logbook_pro` flag)
- **Stripe:** Subscription billing for Logbook Pro ($0.99/mo), webhook handler
- **AI:** Passage briefing via Anthropic SDK (claude-3-5-haiku, streaming SSE)
- **Admin:** Revenue dashboard, user management, ban/unban, feature flags
- **WebSocket:** Real-time fleet position broadcast to connected clients

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full API endpoint reference and DB schema.

---

## Contributing

- Branch naming: `feature/name`, `fix/name`, `chore/name`
- All PRs must pass `flutter analyze` with 0 errors
- No emoji in UI — use Material Icons only
- Responsive layouts required (phone / tablet / desktop breakpoints)
- Every new screen must be added to `plugin_hub_screen.dart`

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full code style guide.

---

## License

MIT
