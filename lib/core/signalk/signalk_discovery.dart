import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';

/// Information about a discovered Signal K server.
class SignalKServerInfo {
  final String host;
  final int port;
  final String? name;

  const SignalKServerInfo({
    required this.host,
    required this.port,
    this.name,
  });

  @override
  String toString() => '${name ?? host}:$port';
}

/// Discovers Signal K servers on the local network using mDNS.
///
/// Scans for `_signalk-ws._tcp` services with a 5-second timeout.
class SignalKDiscovery {
  /// Scan the local network for Signal K WebSocket servers.
  /// Returns the first server found, or null after timeout.
  static Future<SignalKServerInfo?> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = MDnsClient();
    try {
      await client.start();

      final completer = Completer<SignalKServerInfo?>();
      Timer? timer;

      timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });

      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_signalk-ws._tcp'),
      )) {
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          timer.cancel();
          final info = SignalKServerInfo(
            host: srv.target.replaceAll(RegExp(r'\.$'), ''),
            port: srv.port,
            name: ptr.domainName.split('.').first,
          );
          if (!completer.isCompleted) completer.complete(info);
          client.stop();
          return info;
        }
      }

      timer.cancel();
      if (!completer.isCompleted) completer.complete(null);
      return completer.future;
    } catch (_) {
      return null;
    } finally {
      client.stop();
    }
  }
}
