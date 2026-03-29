# Contributing to Floatilla

---

## Getting Started

1. Fork the repo and clone locally
2. Run `flutter pub get`
3. Run `flutter analyze` — must show 0 errors before you start
4. Create a feature branch: `feature/your-feature-name`

---

## Branch Naming

| Prefix | Use for |
|---|---|
| `feature/` | New features or screens |
| `fix/` | Bug fixes |
| `chore/` | Dependency updates, tooling, refactors |
| `docs/` | Documentation only |

---

## Code Style

### No emoji in UI code

Use Material Icons only. Never use emoji literals in widget trees, button labels, or display strings.

```dart
// WRONG
Text('⚓ Anchor Watch')
Icon(... /* emoji fallback */)

// RIGHT
Icon(Icons.anchor)
Text('Anchor Watch')
```

### Responsive layouts — required on all screens

Every screen must handle three breakpoints using `LayoutBuilder`:

```dart
Widget build(BuildContext context) {
  return LayoutBuilder(builder: (context, constraints) {
    if (constraints.maxWidth >= 1000) {
      return _buildDesktopLayout();   // side-by-side panels
    } else if (constraints.maxWidth >= 600) {
      return _buildTabletLayout();    // 2-column grid
    } else {
      return _buildPhoneLayout();     // single column
    }
  });
}
```

The `Responsive` helper in `lib/ui/shared/responsive.dart` provides `Responsive.isPhone()`, `isTablet()`, `isDesktop()` shortcuts.

### Error handling — use `logError()`

Never use silent catch blocks. Always log errors via `logError()` from `core/utils/error_handler.dart`.

```dart
// WRONG
try {
  await fetchData();
} catch (e) {
  // silently ignored
}

// RIGHT
import 'package:flutter_plotter/core/utils/error_handler.dart';

try {
  await fetchData();
} catch (e, stack) {
  logError('fetchData failed', e, stack);
}
```

### Distance and bearing calculations — use `geo_utils.dart`

Do not implement haversine, bearing, or rhumb line calculations per-file. Use the shared utility.

```dart
// WRONG (per-file implementation)
double dist = sqrt(pow(lat2 - lat1, 2) + ...);  // not valid for geo

// RIGHT
import 'package:flutter_plotter/core/utils/geo_utils.dart';

final distNm = GeoUtils.distanceNm(from, to);
final bearing = GeoUtils.bearingDeg(from, to);
```

### Provider pattern

Use `StateNotifierProvider<Notifier, State>` consistently:

```dart
// Notifier
class MyNotifier extends StateNotifier<MyState> {
  MyNotifier() : super(const MyState());

  void doSomething() {
    state = state.copyWith(value: newValue);
  }
}

// Provider
final myProvider = StateNotifierProvider<MyNotifier, MyState>(
  (ref) => MyNotifier(),
);
```

---

## Naming Conventions

| What | Convention | Example |
|---|---|---|
| Screen widgets | `XxxScreen` | `AisCpaScreen` |
| Riverpod providers | `xxxProvider` | `signalkProvider` |
| StateNotifier classes | `XxxNotifier` | `SignalKNotifier` |
| State classes | `XxxState` | `SignalKState` |
| Service classes | `XxxService` | `FloatillaService` |
| File names | `snake_case.dart` | `ais_cpa_screen.dart` |

---

## Adding a New Screen

1. Create `lib/ui/floatilla/your_feature_screen.dart`
2. Implement `YourFeatureScreen extends StatefulWidget` (or `StatelessWidget` if no local state)
3. Add responsive layout (LayoutBuilder with 600/1000 breakpoints)
4. Add import + entry to `lib/ui/floatilla/plugin_hub_screen.dart`:

```dart
// In the appropriate _Category in _categories list:
_PluginEntry(
  name: 'Your Feature',
  icon: Icons.your_icon,
  builder: (_) => const YourFeatureScreen(),
),
```

5. Run `flutter analyze` — 0 errors required

---

## Adding a New Provider

1. Create `lib/data/providers/your_feature_provider.dart`
2. Define state class with `copyWith`
3. Define notifier class extending `StateNotifier<YourFeatureState>`
4. Export the provider constant: `final yourFeatureProvider = StateNotifierProvider<...>(...)`
5. If the provider depends on Signal K data, watch `signalkProvider`

---

## Pull Request Checklist

- [ ] Branch named correctly (`feature/`, `fix/`, `chore/`)
- [ ] `flutter analyze` shows 0 errors
- [ ] No emoji in any widget tree or display string
- [ ] All new screens have responsive layout (LayoutBuilder 600/1000)
- [ ] Error handling uses `logError()` — no silent catches
- [ ] Distance/bearing calculations use `geo_utils.dart`
- [ ] New screen added to `plugin_hub_screen.dart`
- [ ] CHANGELOG.md updated under `[Unreleased]`
- [ ] PR description explains what changed and why

---

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add tidal current overlay
fix: silence crash on empty AIS buffer
chore: upgrade intl to 0.20.2
docs: update ARCHITECTURE.md with new endpoints
refactor: extract geo_utils from per-file implementations
```

---

## Running Tests

```bash
flutter test
```

Widget tests live in `test/`. Integration tests (planned) will live in `integration_test/`.

---

## Server Development

```bash
cd server
npm install
DATABASE_URL=postgresql://localhost/floatilla_dev JWT_SECRET=dev-secret node index.js
```

The server runs on port 8080 by default. Configure the Flutter app to point to `http://localhost:8080` in Settings.
