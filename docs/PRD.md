# Floatilla — Product Requirements Document

**Version:** 0.3.0  
**Date:** 2026-03-29  
**Status:** Active Development

---

## 1. Executive Summary

Floatilla is a mobile-first marine navigation platform that combines chart plotting, real-time fleet social features, Signal K instrument integration, and cloud logbook capabilities. It targets recreational sailors and power boaters who want a capable, modern alternative to legacy navigation software.

Built with Flutter for Android and iOS, Floatilla is Signal K-native, meaning it can read all instrument data from any modern boat network without proprietary hardware. It adds a social layer that existing navigation apps lack, and keeps core features free while monetising power users through a low-cost logbook subscription.

---

## 2. Problem Statement

Existing mobile marine navigation apps are either:

- **Feature-thin** — basic chart display only (e.g. Navionics without subscription extras)
- **Legacy UX** — unchanged since 2012 (iNavX, SeaNav)
- **Expensive and hardware-locked** — Garmin, Raymarine apps require their own hardware
- **Missing social/cloud features** — no fleet sharing, no collaborative anchorage data
- **Not Signal K-aware** — cannot interface with modern open boat data networks

There is no free, open-source, Signal K-native mobile chart plotter with social features and AI-assisted passage planning.

---

## 3. Target Users

### Primary: Recreational Sailors

- Own a sailing vessel 25–50ft
- Weekend and holiday sailing in home waters
- Interested in racing performance and improving sail trim
- Use Signal K server or NMEA instruments on board

### Secondary: Power Boaters / Cruisers

- Longer passages, offshore capability required
- Heavy weather planning is a priority
- Logbook compliance requirements (some jurisdictions)

### Tertiary: Charter Fleet Operators

- Need multi-vessel tracking
- Client-facing sharing features
- Crew/delivery skipper handover logbooks

---

## 4. Core Value Propositions

1. **Signal K-native** — reads all instrument data without proprietary hardware or paid integrations
2. **Social fleet** — real-time position sharing, anchorage status, hazard reporting
3. **AI-powered planning** — LLM passage briefings, weather window analysis
4. **Cloud logbook** — legal-grade logbook synced across all devices ($0.99/mo)
5. **Open weather** — GFS/ECMWF/ICON GRIB models, NOAA tides, no subscription

---

## 5. Feature Inventory (Current — v0.3.0)

### Navigation & Planning
- Passage Plan — multi-leg with ETA/distance
- Route Planner — create, edit, cloud sync
- Tidal Gates — 97-window departure solver (NOAA currents)
- Departure Planner — 4-window weather comparison (Open-Meteo)
- Dead Reckoning
- Celestial Navigation (Meeus algorithms, sight reduction)
- Waypoint Calculator (bearing+distance ↔ lat/lng)
- CDI — course deviation indicator
- Fuel Range — calculator + chart range ring
- Night Mode — dark chart tiles, dimmed instruments

### Safety & Alerts
- AIS Collision (CPA) — ranked targets, COLREGS guidance
- Anchor Watch (Scope) — catenary-formula drag radius
- Boat Health Monitor — Signal K sensor alerting
- MOB — drift prediction (IAMSAR leeway, 120-min)
- SAR Patterns — IAMSAR expanding square/sector/parallel

### Weather & Environment
- GRIB Weather — GFS, ECMWF, ICON via Open-Meteo, offline save
- Tidal Currents — NOAA overlay
- Weather Overlay — wind/pressure/precipitation on chart
- Daily Briefing — 7-day summary (Open-Meteo)
- Wind History — trail + wind rose from Signal K buffer
- Ocean Currents — Marine API 0–48h forecast
- Swell Breakdown — primary/wind wave components, comfort rating

### Instruments & Data
- Signal K Dashboard — all live paths
- NMEA Multiplexer — sentence stream with checksum validation
- Engine Dashboard — Signal K propulsion.*
- Polar Performance — CSV upload, VMG, live TWA/TWS
- Radar Simulator — PPI from AIS, animated sweep
- Tank Monitor — Signal K tanks.*
- Trim Assistant — heel + VMG + polar → A–F grade

### Voyage
- Voyage Logger — auto-detect by SOG, SQLite
- Voyage Score — VMG%, tack count, wind shift response
- Cloud Logbook — Captain's Log + Ship's Log (Logbook Pro)
- AIS History Trail — 24h per vessel
- Track Comparison — 4 tracks, speed colour mode

### Social & Community
- Floatilla Feed — fleet positions, social feed, messaging
- Anchorages — live boat count, check-in/out
- Passage Briefing (AI) — claude-3-5-haiku streaming
- Marinas — crowdsourced fuel/water/depth/facilities

### Racing
- Race Start Timer — laylines, favoured end, time-on-distance
- Deviation Table — compass deviation card

---

## 6. Monetisation

### Free tier (all users)
- All navigation features
- Fleet social (friends, position sharing)
- Basic weather overlay
- Anchor watch, AIS, MOB
- Signal K integration

### Logbook Pro ($0.99/month)
- Cloud logbook sync across all devices
- Captain's Log with geo-tagged entries
- Ship's Log with Signal K auto-fill
- Voyage history and statistics export

### Floatilla Pro (planned, $4.99/month)
- AI passage briefing (unlimited requests)
- GRIB weather download + offline storage
- Advanced weather routing (isochrones)
- Priority support

---

## 7. Technical Requirements

### Performance
- Chart render: <100ms on mid-range Android (2021+, Snapdragon 778G or equivalent)
- Signal K reconnect: automatic, <5 seconds
- App launch to chart visible: <3 seconds cold start

### Compatibility
- Android 6.0+ (API 23+) — primary target
- iOS 14+ — planned release
- Tablets: responsive layout at 600px+ (2-column) and 1000px+ (3-column + sidebar) breakpoints

### Offline capability
- Chart tiles cached via `flutter_map_tile_caching`
- GRIB model grids saveable to `SharedPreferences` (offline playback)
- Logbook entries queued locally, synced on reconnect
- Voyage logger uses SQLite (no network required)

---

## 8. Signal K Integration

Floatilla connects to a Signal K server WebSocket at `ws://host:3000/signalk/v1/stream`.

### Key paths consumed

| Signal K path | Used for |
|---|---|
| `navigation.position` | GPS position on chart |
| `navigation.speedOverGround` | SOG instruments, voyage logger |
| `navigation.courseOverGroundTrue` | COG, dead reckoning |
| `navigation.headingMagnetic` / `headingTrue` | Heading display |
| `environment.wind.speedTrue` / `directionTrue` | TWS, TWD |
| `environment.wind.speedApparent` / `angleApparent` | AWS, AWA |
| `environment.depth.belowKeel` | Depth instrument |
| `propulsion.*.revolutions` | Engine RPM |
| `propulsion.*.runTime` | Engine hours |
| `electrical.batteries.*` | Battery voltage/current |
| `tanks.*` | Fuel, water, waste levels |
| `navigation.courseGreatCircle.crossTrackError` | XTE / CDI |
| `navigation.courseGreatCircle.nextPoint` | Active waypoint |

### Server discovery
Signal K server address can be:
- Set manually in **Settings → Signal K Server**
- Auto-discovered via mDNS (`_signalk-ws._tcp.local`)

---

## 9. Roadmap

### v0.4 (next)
- Weather routing with isochrones (GRIB + polar → fastest route)
- Riverpod 3 migration: `StateNotifier` → `AsyncNotifier`
- Route sharing + collaborative editing
- Offline vector chart download
- Autopilot control via Signal K `steering.autopilot.*`

### v0.5
- iOS App Store release
- AR navigation overlay (camera + chart position annotation)
- Fleet tracking for sailing clubs and race committees
- Weather window push notifications (FCM)

### v1.0
- App Store + Google Play Store public launch
- Stripe subscriptions live in production
- Full COLREGS collision avoidance decision tree
- VHF DSC integration via Signal K `notifications.mob`

---

## 10. Out of Scope (Current)

- Vector ENC chart support (S-57/S-63) — post v1.0
- Autopilot route following — v0.4
- Multi-boat racing scoring — post v1.0
- Sat phone / Iridium integration — future
- Web app version — post v1.0
