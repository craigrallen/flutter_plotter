import 'dart:io';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/waypoint.dart';
import '../../data/models/route_model.dart';

/// Parse a GPX file into waypoints and routes.
class GpxParser {
  /// Parse GPX XML string into standalone waypoints.
  static List<Waypoint> parseWaypoints(String gpxXml) {
    final doc = XmlDocument.parse(gpxXml);
    final wpts = doc.findAllElements('wpt');
    return wpts.map((el) {
      final lat = double.parse(el.getAttribute('lat')!);
      final lon = double.parse(el.getAttribute('lon')!);
      final name = el.getElement('name')?.innerText ?? 'WPT';
      final desc = el.getElement('desc')?.innerText;
      return Waypoint(
        name: name,
        position: LatLng(lat, lon),
        notes: desc,
        createdAt: DateTime.now(),
      );
    }).toList();
  }

  /// Parse GPX XML string into routes (rte elements).
  /// Returns a list of (routeName, list of waypoints).
  static List<({String name, List<Waypoint> waypoints})> parseRoutes(
      String gpxXml) {
    final doc = XmlDocument.parse(gpxXml);
    final rtes = doc.findAllElements('rte');
    return rtes.map((rte) {
      final name = rte.getElement('name')?.innerText ?? 'Route';
      final rtePts = rte.findElements('rtept').map((el) {
        final lat = double.parse(el.getAttribute('lat')!);
        final lon = double.parse(el.getAttribute('lon')!);
        final wpName = el.getElement('name')?.innerText ?? 'WPT';
        return Waypoint(
          name: wpName,
          position: LatLng(lat, lon),
          createdAt: DateTime.now(),
        );
      }).toList();
      return (name: name, waypoints: rtePts);
    }).toList();
  }

  /// Also parse tracks (trk) as routes — common in GPX files.
  static List<({String name, List<Waypoint> waypoints})> parseTracks(
      String gpxXml) {
    final doc = XmlDocument.parse(gpxXml);
    final trks = doc.findAllElements('trk');
    return trks.map((trk) {
      final name = trk.getElement('name')?.innerText ?? 'Track';
      final trkPts = trk
          .findAllElements('trkpt')
          .toList()
          .asMap()
          .entries
          .map((e) {
        final el = e.value;
        final lat = double.parse(el.getAttribute('lat')!);
        final lon = double.parse(el.getAttribute('lon')!);
        final wpName =
            el.getElement('name')?.innerText ?? 'TP${e.key + 1}';
        return Waypoint(
          name: wpName,
          position: LatLng(lat, lon),
          createdAt: DateTime.now(),
        );
      }).toList();
      return (name: name, waypoints: trkPts);
    }).toList();
  }
}

/// Export a route as a GPX XML string.
class GpxExporter {
  static String exportRoute(RouteModel route) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('gpx', nest: () {
      builder.attribute('version', '1.1');
      builder.attribute('creator', 'FlutterPlotter');
      builder.attribute(
          'xmlns', 'http://www.topografix.com/GPX/1/1');

      // Export as rte element
      builder.element('rte', nest: () {
        builder.element('name', nest: route.name);
        for (final wp in route.waypoints) {
          builder.element('rtept', nest: () {
            builder.attribute('lat', wp.position.latitude.toString());
            builder.attribute('lon', wp.position.longitude.toString());
            builder.element('name', nest: wp.name);
            if (wp.notes != null) {
              builder.element('desc', nest: wp.notes!);
            }
          });
        }
      });
    });
    return builder.buildDocument().toXmlString(pretty: true);
  }

  /// Write GPX to a temporary file and return the path.
  static Future<String> exportToFile(RouteModel route) async {
    final gpxStr = exportRoute(route);
    final dir = await getApplicationDocumentsDirectory();
    final safeName = route.name.replaceAll(RegExp(r'[^\w\s-]'), '');
    final file = File('${dir.path}/$safeName.gpx');
    await file.writeAsString(gpxStr);
    return file.path;
  }
}
