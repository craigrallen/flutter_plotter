# Floatilla — Architecture

---

## 1. Flutter Layer Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         UI Layer                                │
│  chart/        floatilla/      settings/       shared/          │
│  (ChartScreen) (40+ screens)   (SettingsScreen) (AppShell)      │
└────────────────────────┬────────────────────────────────────────┘
                         │ consumes via ref.watch / ref.read
┌────────────────────────▼────────────────────────────────────────┐
│                     Provider Layer (Riverpod 2)                 │
│  signalkProvider   vesselProvider   aisProvider   routeProvider │
│  weatherProvider   tideProvider     floatillaProvider  ...      │
└────────┬──────────────────────────────────────┬─────────────────┘
         │                                      │
┌────────▼──────────┐               ┌──────────▼──────────────────┐
│   Core / Services │               │   Data Layer                │
│  SignalKSource    │               │  RouteRepository            │
│  NmeaStream       │               │  WaypointRepository         │
│  FloatillaService │               │  data/models/               │
│  WeatherService   │               └─────────────────────────────┘
│  TideService      │
│  VoyageLogger     │
│  LogbookService   │
└────────┬──────────┘
         │
┌────────▼──────────────────────────────────────────────────────────┐
│                     External Sources                              │
│  Signal K WebSocket    Open-Meteo REST    NOAA CO-OPS REST        │
│  Floatilla REST API    Anthropic SDK      OpenStreetMap tiles      │
└───────────────────────────────────────────────────────────────────┘
```

---

## 2. Provider Dependency Graph

### Core providers

```
dataSourceProvider          ← settings (server URL, NMEA config)
  └── signalkProvider       ← dataSourceProvider
  └── nmeaConfigProvider    ← dataSourceProvider

vesselProvider              ← signalkProvider
aisProvider                 ← signalkProvider
aisCpaProvider              ← aisProvider
aisHistoryProvider          ← signalkProvider
anchorProvider              ← signalkProvider, settingsProvider
boatHealthProvider          ← signalkProvider

weatherProvider             ← settingsProvider (location)
weatherGribProvider         ← settingsProvider
tideProvider                ← settingsProvider

routeProvider               ← RouteRepository
routeEngineProvider         ← routeProvider, vesselProvider
routingApiProvider          ← settingsProvider

floatillaProvider           ← settingsProvider (server URL, auth token)
cloudLogbookProvider        ← floatillaProvider
voyageLoggerProvider        ← vesselProvider, signalkProvider

vesselProfileProvider       ← SharedPreferences
settingsProvider            ← SharedPreferences
chartTileProvider           ← settingsProvider
```

### Notifier types

All providers follow `StateNotifierProvider<XxxNotifier, XxxState>` pattern:

```dart
// Example
final signalkProvider = StateNotifierProvider<SignalKNotifier, SignalKState>(
  (ref) => SignalKNotifier(ref.watch(settingsProvider)),
);
```

---

## 3. Signal K Data Flow

```
Boat instruments (NMEA 0183/2000)
        │
        ▼
Signal K server (OpenPlotter / Victron Cerbo / etc.)
  ws://host:3000/signalk/v1/stream
        │
        ▼ JSON delta stream
SignalKSource (lib/core/signalk/signalk_source.dart)
  • WebSocket reconnect with backoff
  • Parses delta messages via SignalKParser
  • Emits SignalKState updates
        │
        ▼
signalkProvider (StateNotifier)
  • Holds current SignalKState
  • Derived providers watch specific paths
        │
     ┌──┴──────────────────────────────┐
     ▼                                 ▼
vesselProvider                    aisProvider
(position, SOG, COG, heading,     (decoded VDM messages → AisTarget list)
 wind, depth, engine, tanks)
     │                                 │
     ▼                                 ▼
UI: instrument strip,             UI: AIS layer, CPA screen,
    chart vessel marker,              history trail
    engine dashboard,
    tank monitor, etc.
```

### NMEA fallback path

When no Signal K server is configured, the app can receive NMEA directly:

```
TCP source (port 10110)  or  UDP source (port 10110)
        │
        ▼
NmeaStream (lib/core/nmea/nmea_stream.dart)
  • Parses RMC, GLL, VTG, MWV, DBT, HDT, VDM sentences
  • Emits position/wind/depth updates
        │
        ▼
NmeaSource → SignalKState (same downstream path as above)
```

---

## 4. Server API Endpoint Reference

Base URL: `https://floatilla.up.railway.app` (production)

### Authentication

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/auth/register` | — | Register new user |
| POST | `/auth/login` | — | Login, returns JWT |
| POST | `/auth/forgot-password` | — | Send password reset token |
| POST | `/auth/reset-password` | — | Reset password with token |

### Users

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/users/me` | JWT | Get own profile |
| POST | `/users/location` | JWT | Update own position (lat/lng/SOG/COG) |
| POST | `/users/fcm-token` | JWT | Register FCM push token |

### Friends

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/friends` | JWT | List accepted friends with positions |
| GET | `/friends/requests` | JWT | List pending friend requests |
| POST | `/friends/add` | JWT | Send friend request |
| POST | `/friends/accept` | JWT | Accept friend request |
| POST | `/friends/remove` | JWT | Remove friend |
| GET | `/friends/:username/tracks` | JWT | Get friend's track history |

### Messages

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/messages` | JWT | Get social feed messages |
| POST | `/messages` | JWT | Post a feed message |

### Waypoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/waypoints` | JWT | List own waypoints |
| POST | `/waypoints` | JWT | Create waypoint |
| DELETE | `/waypoints/:id` | JWT | Delete waypoint |
| POST | `/waypoints/share` | JWT | Share waypoint with a friend |

### Routes

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/routes` | JWT | List own routes |
| POST | `/routes` | JWT | Create route |
| PUT | `/routes/:id` | JWT | Update route |
| DELETE | `/routes/:id` | JWT | Delete route |

### Cloud Sync

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/sync/routes` | JWT | Pull cloud routes |
| PUT | `/sync/routes` | JWT | Push cloud routes |
| GET | `/sync/waypoints` | JWT | Pull cloud waypoints |
| PUT | `/sync/waypoints` | JWT | Push cloud waypoints |

### Social / Anchorages

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/anchorages/nearby` | — | List nearby anchorages (lat/lng/radius) |
| POST | `/anchorages/checkin` | JWT | Check in to an anchorage |
| POST | `/anchorages/checkout` | JWT | Check out of anchorage |

### Hazards

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/hazards/nearby` | — | List nearby hazards |
| POST | `/hazards` | JWT | Report a hazard |
| POST | `/hazards/:id/confirm` | JWT | Confirm an existing hazard |

### Marinas

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/marinas/nearby` | — | List nearby marinas |
| POST | `/marinas` | JWT | Add a marina |
| GET | `/marinas/:id/notes` | — | Get marina notes |
| POST | `/marinas/:id/notes` | JWT | Add note to marina |

### MOB

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/mob` | JWT | Broadcast MOB alert to friends |

### Anchor

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/anchor/alert` | JWT | Trigger anchor drag push alert |
| POST | `/alerts/anchor-drag` | JWT | Register anchor drag alert rule |

### Logbook (legacy)

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/logbook` | JWT | Get voyage logbook entries |
| POST | `/logbook/entry` | JWT | Add logbook entry |
| GET | `/logbook/gpx` | JWT | Export logbook as GPX |
| GET | `/logbook/status` | JWT | Get Logbook Pro subscription status |
| POST | `/logbook/subscribe` | JWT | Subscribe to Logbook Pro |

### Captain's Log (Logbook Pro)

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/captains-log` | JWT + Pro | List captain's log entries |
| GET | `/captains-log/sync` | JWT + Pro | Delta sync since timestamp |
| POST | `/captains-log` | JWT + Pro | Create entry |
| PUT | `/captains-log/:id` | JWT + Pro | Update entry |
| DELETE | `/captains-log/:id` | JWT + Pro | Soft-delete entry |

### Ship's Log (Logbook Pro)

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/ships-log` | JWT + Pro | List ship's log entries |
| GET | `/ships-log/sync` | JWT + Pro | Delta sync since timestamp |
| GET | `/ships-log/voyages` | JWT + Pro | List voyage summaries |
| POST | `/ships-log` | JWT + Pro | Create entry |

### Weather (proxy)

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/weather/grib` | — | GRIB forecast data (Open-Meteo proxy) |
| GET | `/weather/grib/raw` | — | Raw GRIB grid data |
| GET | `/weather/waves` | — | Wave forecast (Open-Meteo) |
| GET | `/proxy/tides` | — | NOAA tide proxy |
| GET | `/proxy/weather` | — | Open-Meteo proxy |

### AI

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/passage/briefing` | JWT | Generate AI passage briefing (SSE stream) |

### Features

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/features` | JWT | Get feature flags for current user |

### Subscription

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/subscription/create` | JWT | Create Stripe subscription |
| POST | `/webhook/stripe` | — | Stripe webhook handler |

### Admin

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/admin/login` | — | Admin login |
| GET | `/admin/stats` | Admin | Global statistics |
| GET | `/admin/users` | Admin | List all users |
| GET | `/admin/messages` | Admin | List all messages |
| DELETE | `/admin/messages/:id` | Admin | Delete a message |
| POST | `/admin/users/:id/ban` | Admin | Ban a user |
| POST | `/admin/users/:id/unban` | Admin | Unban a user |
| DELETE | `/admin/users/:id` | Admin | Delete a user |
| GET | `/admin/activity` | Admin | Recent activity log |
| GET | `/admin/revenue` | Admin | Revenue dashboard |
| GET | `/admin/features` | Admin | Feature flag overview |
| PUT | `/admin/users/:id/pro` | Admin | Set/unset pro status for a user |

---

## 5. Database Schema

PostgreSQL managed by Railway.

### `users`

| Column | Type | Notes |
|---|---|---|
| id | SERIAL PK | |
| username | TEXT UNIQUE | |
| email | TEXT UNIQUE | nullable |
| vessel_name | TEXT | |
| password_hash | TEXT | bcrypt |
| reset_token | TEXT | nullable |
| reset_token_expires | BIGINT | unix timestamp |
| lat | DOUBLE PRECISION | last known position |
| lng | DOUBLE PRECISION | |
| sog | DOUBLE PRECISION | default 0 |
| cog | DOUBLE PRECISION | default 0 |
| last_seen | BIGINT | unix timestamp |
| created_at | BIGINT | unix timestamp |
| banned | BOOLEAN | default false |
| fcm_token | TEXT | push notification token |
| fcm_platform | TEXT | 'ios' or 'android' |
| is_pro | BOOLEAN | default false |
| logbook_pro | BOOLEAN | default false |
| stripe_customer_id | TEXT | nullable |
| feature_flags | JSONB | per-user feature overrides |

### `friendships`

| Column | Type | Notes |
|---|---|---|
| id | SERIAL PK | |
| user_id | INTEGER FK users | |
| friend_id | INTEGER FK users | |
| status | TEXT | 'pending' or 'accepted' |
| created_at | BIGINT | |
| UNIQUE | (user_id, friend_id) | |

### `messages`

| Column | Type | Notes |
|---|---|---|
| id | SERIAL PK | |
| user_id | INTEGER FK users | |
| text | TEXT | |
| lat | DOUBLE PRECISION | nullable |
| lng | DOUBLE PRECISION | nullable |
| created_at | BIGINT | |

### `waypoints`

| Column | Type | Notes |
|---|---|---|
| id | SERIAL PK | |
| sender_id | INTEGER FK users | |
| recipient_id | INTEGER FK users | |
| name | TEXT | nullable |
| lat | DOUBLE PRECISION | |
| lng | DOUBLE PRECISION | |
| note | TEXT | nullable |
| created_at | BIGINT | |

### `routes`

| Column | Type | Notes |
|---|---|---|
| id | SERIAL PK | |
| user_id | INTEGER FK users | |
| name | TEXT | |
| waypoints | JSONB | array of {lat, lng, name} |
| color | TEXT | nullable |
| notes | TEXT | nullable |
| created_at | BIGINT | |
| updated_at | BIGINT | |

### `cloud_routes`

| Column | Type | Notes |
|---|---|---|
| user_id | INTEGER PK FK users | one row per user |
| data | JSONB | full routes array |
| updated_at | BIGINT | |

### `cloud_waypoints`

| Column | Type | Notes |
|---|---|---|
| user_id | INTEGER PK FK users | one row per user |
| data | JSONB | full waypoints array |
| updated_at | BIGINT | |

### `captain_log_entries`

| Column | Type | Notes |
|---|---|---|
| id | SERIAL PK | |
| user_id | INTEGER FK users | |
| entry_date | TEXT | YYYY-MM-DD |
| position_lat | DOUBLE PRECISION | nullable |
| position_lng | DOUBLE PRECISION | nullable |
| weather | TEXT | nullable |
| crew | TEXT | nullable |
| notes | TEXT | |
| created_at | BIGINT | |
| updated_at | BIGINT | |
| deleted | BOOLEAN | soft delete |

### `ship_log_entries`

| Column | Type | Notes |
|---|---|---|
| id | SERIAL PK | |
| user_id | INTEGER FK users | |
| logged_at | BIGINT | unix timestamp |
| position_lat | DOUBLE PRECISION | nullable |
| position_lng | DOUBLE PRECISION | nullable |
| course | DOUBLE PRECISION | nullable |
| speed | DOUBLE PRECISION | nullable |
| wind_speed | DOUBLE PRECISION | nullable |
| wind_direction | DOUBLE PRECISION | nullable |
| depth | DOUBLE PRECISION | nullable |
| barometer | DOUBLE PRECISION | nullable |
| engine_hours | DOUBLE PRECISION | nullable |
| fuel_remaining | DOUBLE PRECISION | nullable |
| notes | TEXT | nullable |
| voyage_id | TEXT | nullable, groups entries into voyages |
| created_at | BIGINT | |
| deleted | BOOLEAN | soft delete |

---

## 6. WebSocket (Real-time Fleet Positions)

The server upgrades HTTP connections to WebSocket on the same port (8080).

- On connect: client sends `{ type: 'auth', token: <JWT> }`
- Server validates JWT, joins the user to the broadcast pool
- On each `POST /users/location`, the server broadcasts `{ type: 'position', userId, username, vesselName, lat, lng, sog, cog }` to all connected authenticated clients
- Client-side: `FloatillaService` manages the WebSocket connection with reconnect logic
