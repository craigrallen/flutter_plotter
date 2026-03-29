# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [0.3.0] - 2026-03-29

### Added

- Waypoint calculator — bearing+distance ↔ lat/lng conversion tool
- CDI — highway-style course deviation indicator
- Fuel range calculator with range ring overlay on chart
- Night mode — CartoDB dark tiles, helm-readable dimmed instruments
- MOB drift prediction — IAMSAR leeway model, 120-minute simulation
- Daily 7-day weather briefing powered by Open-Meteo
- Wind history trail + wind rose built from Signal K buffer
- Ocean current overlay — Marine API, 0–48h forecast
- Swell component breakdown — primary swell vs wind wave, comfort rating
- Tank monitoring dashboard reading Signal K `tanks.*` paths
- Trim assistant — heel + VMG + polar input → sail trim advice, A–F grade
- Marina community layer — fuel, water, depth, facilities crowdsourced
- Voyage health scoring — VMG%, tack count, wind shift response metrics
- GRIB weather models: GFS, ECMWF, ICON via Open-Meteo with offline save to SharedPreferences
- Shared `geo_utils.dart` for all distance/bearing calculations
- Shared `error_handler.dart` with `logError()` for consistent error logging

### Changed

- Navigation restructured: 5 core tabs + Plugin Hub replacing 25+ bottom nav items
- All emoji icons replaced with Material Icons throughout the codebase
- Responsive layouts added to all plugin screens (LayoutBuilder 600/1000 breakpoints)
- Kotlin upgraded to 2.1.0
- `intl` upgraded to 0.20.2
- `web_socket_channel` upgraded to 3.0.3

### Fixed

- GRIB weather now fetches directly from Open-Meteo (removed server proxy dependency)
- `Path<LatLng>` type clash with `dart:ui Path` resolved in CustomPainter files
- Silent catch blocks replaced with `logError()` calls throughout
- `pubspec.yaml` assets field malformed — corrected indentation

---

## [0.2.0] - 2026-03-28

### Added

- Smart AIS collision alerting — CPA/TCPA ranked targets with COLREGS guidance
- Scope-aware anchor watch — chain length + depth + catenary formula for drag radius
- LLM passage briefing — Anthropic claude-3-5-haiku, streaming SSE
- Tidal gate optimizer — NOAA currents API, 97-window departure solver
- Departure planning tool — 4-window weather comparison, Open-Meteo scoring
- Social anchorage status — live boat count, check-in/out via Floatilla API
- Real-time hazard crowdsourcing — 6 hazard types, 24-hour expiry
- Voyage auto-logger — auto-detect voyage start/stop by SOG, SQLite local storage
- Track comparison — up to 4 tracks, speed color mode, divergence point detection
- Boat network health monitor — Signal K sensor alerting with configurable alert rules
- Cloud logbook — Captain's Log + Ship's Log, gated behind Logbook Pro ($0.99/mo Stripe)
- Web route planner screen
- Charter dashboard screen
- Tidal atlas screen
- Passage share link screen
- Server: Stripe billing with webhook handler for subscription lifecycle
- Server: Feature flags per user (`feature_flags` JSONB column)
- Server: Admin revenue dashboard endpoint
- Admin: Revenue dashboard UI
- Admin: Feature flag management UI
- Competitive feature research document (17 apps analysed)

---

## [0.1.0] - 2026-03-27

### Added

- Initial Flutter chart plotter with OpenStreetMap + OpenSeaMap tile layers
- Floatilla social feed — fleet position sharing, social feed, direct messaging
- Voyage logbook with GPX export
- Passage planning screen with multi-leg route support
- Engine dashboard reading Signal K `propulsion.*` paths
- Anchor watch with cloud drag alert via Floatilla server
- AIS targets on chart with CPA distance alarm
- Weather overlay (Open-Meteo wind, pressure, precipitation)
- Tide panel reading NOAA CO-OPS API
- Polar performance — CSV polar upload, VMG targets, live TWA/TWS overlay
- Tidal currents overlay from NOAA
- AIS history trail — 24-hour position history per vessel
- Deviation table — compass deviation vs GPS, printable deviation card
- Race start timer — laylines, favoured end detection, time-on-distance countdown
- Dead reckoning — position extrapolation from last known GPS fix
- Celestial navigation — Meeus algorithms, altitude/azimuth, sight reduction
- SAR pattern planner — IAMSAR expanding square, sector, and parallel sweep
- Radar simulator — PPI display built from AIS targets with animated sweep
- NMEA multiplexer — live sentence stream display with checksum validation
- Railway deployment with managed PostgreSQL database
- JWT authentication, friend system, WebSocket fleet positions
