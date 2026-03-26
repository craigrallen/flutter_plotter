import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/nmea/nmea_stream.dart';
import '../../core/nmea/sentence_parser.dart';
import '../../core/nmea/sentences/rmc.dart';
import '../../core/nmea/sentences/gll.dart';
import '../../core/nmea/sentences/vtg.dart';
import '../../core/nmea/sentences/hdt.dart';
import 'ais_provider.dart';
import 'vessel_provider.dart';

/// Persisted NMEA connection configuration.
class NmeaConfig {
  final String host;
  final int port;
  final NmeaProtocol protocol;

  const NmeaConfig({
    this.host = '',
    this.port = 10110,
    this.protocol = NmeaProtocol.tcp,
  });

  NmeaConfig copyWith({String? host, int? port, NmeaProtocol? protocol}) {
    return NmeaConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
    );
  }
}

class NmeaConfigNotifier extends StateNotifier<NmeaConfig> {
  NmeaConfigNotifier() : super(const NmeaConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = NmeaConfig(
      host: prefs.getString('nmea_host') ?? '',
      port: prefs.getInt('nmea_port') ?? 10110,
      protocol: prefs.getString('nmea_protocol') == 'udp'
          ? NmeaProtocol.udp
          : NmeaProtocol.tcp,
    );
  }

  Future<void> update(NmeaConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nmea_host', config.host);
    await prefs.setInt('nmea_port', config.port);
    await prefs.setString(
      'nmea_protocol',
      config.protocol == NmeaProtocol.udp ? 'udp' : 'tcp',
    );
  }
}

final nmeaConfigProvider =
    StateNotifierProvider<NmeaConfigNotifier, NmeaConfig>((ref) {
  return NmeaConfigNotifier();
});

/// Global NMEA stream instance.
final nmeaStreamProvider = Provider<NmeaStream>((ref) {
  final stream = NmeaStream();
  ref.onDispose(() => stream.dispose());
  return stream;
});

/// Connection state as a stream provider.
final nmeaConnectionStateProvider =
    StreamProvider<NmeaConnectionState>((ref) {
  final stream = ref.watch(nmeaStreamProvider);
  return stream.connectionState;
});

/// Manages NMEA sentence processing — routes parsed data to vessel and AIS providers.
final nmeaProcessorProvider = Provider<void>((ref) {
  final stream = ref.watch(nmeaStreamProvider);
  final aisNotifier = ref.read(aisProvider.notifier);
  final vesselNotifier = ref.read(vesselProvider.notifier);

  StreamSubscription<String>? sub;
  sub = stream.sentences.listen((raw) {
    final sentence = SentenceParser.parse(raw);
    if (sentence == null) return;

    switch (sentence.type) {
      case 'RMC':
        final rmc = RmcData.fromSentence(sentence);
        if (rmc != null && rmc.isValid && rmc.latitude != null && rmc.longitude != null) {
          vesselNotifier.updateFromNmea(
            latitude: rmc.latitude!,
            longitude: rmc.longitude!,
            sog: rmc.sogKnots,
            cog: rmc.cogTrue,
          );
        }
      case 'GLL':
        final gll = GllData.fromSentence(sentence);
        if (gll != null && gll.isValid && gll.latitude != null && gll.longitude != null) {
          vesselNotifier.updateFromNmea(
            latitude: gll.latitude!,
            longitude: gll.longitude!,
          );
        }
      case 'VTG':
        final vtg = VtgData.fromSentence(sentence);
        if (vtg != null) {
          vesselNotifier.updateFromNmea(sog: vtg.sogKnots, cog: vtg.cogTrue);
        }
      case 'HDT':
        final hdt = HdtData.fromSentence(sentence);
        if (hdt != null) {
          vesselNotifier.updateFromNmea(heading: hdt.headingTrue);
        }
      case 'VDM':
      case 'VDO':
        aisNotifier.processSentence(sentence);
    }
  });

  ref.onDispose(() => sub?.cancel());
});
