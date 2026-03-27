# Contributing to FlutterPlotter

## Getting Started

```bash
git clone https://github.com/craigrallen/flutter_plotter.git
cd flutter_plotter
flutter pub get
flutter run
```

## Project Structure

```
lib/core/     — Business logic (NMEA, AIS, navigation math, GPX)
lib/data/     — Models, Riverpod providers, repositories
lib/ui/       — Screens and widgets
```

## Adding a Chart Provider

Chart tiles are managed in `lib/data/providers/chart_tile_provider.dart`.

1. Define a new tile URL template:
   ```dart
   // In chart_tile_provider.dart, add a new entry
   static const String myChartUrl = 'https://tiles.example.com/{z}/{x}/{y}.png';
   ```

2. Expose it as a selectable option in the settings UI (`lib/ui/settings/settings_screen.dart`).

3. If the provider requires an API key, store it in `SharedPreferences` via `settings_provider.dart`.

4. For attribution, ensure the tile layer includes proper `TileLayer.additionalOptions` or attribution widget per the provider's license.

## Adding an NMEA Sentence Type

NMEA sentences are parsed in `lib/core/nmea/`.

1. **Create a parser** in `lib/core/nmea/sentences/`:
   ```dart
   // lib/core/nmea/sentences/mda.dart
   import '../sentence_parser.dart';

   class MdaData {
     final double? barometerInches;
     final double? barometerBar;
     final double? airTempC;

     MdaData({this.barometerInches, this.barometerBar, this.airTempC});

     static MdaData? fromSentence(NmeaSentence sentence) {
       if (sentence.fields.length < 16) return null;
       return MdaData(
         barometerInches: double.tryParse(sentence.fields[0]),
         barometerBar: double.tryParse(sentence.fields[2]),
         airTempC: double.tryParse(sentence.fields[4]),
       );
     }
   }
   ```

2. **Register in `SentenceParser`** — Add the sentence identifier to the type extraction logic in `lib/core/nmea/sentence_parser.dart`.

3. **Route in the NMEA processor** — Add a `case` to the switch in `lib/data/providers/nmea_config_provider.dart` (`nmeaProcessorProvider`):
   ```dart
   case 'MDA':
     final mda = MdaData.fromSentence(sentence);
     if (mda != null) {
       vesselNotifier.updateFromNmea(airTemp: mda.airTempC);
     }
   ```

4. **Extend VesselState** — Add the new field to `lib/data/models/vessel_state.dart` and its `copyWith` method.

5. **Display it** — Add an instrument tile in `lib/ui/instruments/instrument_panel.dart`.

## Adding an AIS Message Type

AIS messages are decoded in `lib/core/ais/`.

1. **Create a message class** in `lib/core/ais/messages/`:
   ```dart
   // lib/core/ais/messages/safety_message.dart (Type 14)
   class SafetyMessage {
     final int mmsi;
     final String text;

     SafetyMessage({required this.mmsi, required this.text});

     factory SafetyMessage.decode(List<int> bits) {
       // Use bit extraction helpers from decoder.dart
       final mmsi = extractUint(bits, 8, 30);
       final text = extractString(bits, 40, 968);
       return SafetyMessage(mmsi: mmsi, text: text);
     }
   }
   ```

2. **Register in the decoder** — Add the message type to the switch in `lib/core/ais/decoder.dart`:
   ```dart
   case 14:
     return SafetyMessage.decode(bits);
   ```

3. **Handle in AIS provider** — Process the decoded message in `lib/data/providers/ais_provider.dart`.

4. **Update UI if needed** — Display in `lib/ui/ais/target_list_screen.dart`.

## Code Conventions

- State management: Riverpod `StateNotifier` (no code generation)
- Models: immutable classes with `copyWith`
- File naming: `snake_case.dart`
- One class per file for models and providers
- No third-party AIS or NMEA parsing libraries — we use custom decoders for full control

## Running Builds

```bash
flutter build apk --release      # Android
flutter build ios --no-codesign   # iOS (no signing for CI)
flutter test                      # Run tests
```
