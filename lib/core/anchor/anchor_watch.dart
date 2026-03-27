import 'package:latlong2/latlong.dart';
import '../nav/geo.dart';

/// Core anchor watch logic: monitors position vs drop point + radius.
class AnchorWatch {
  final LatLng dropPosition;
  final double radiusM;

  const AnchorWatch({
    required this.dropPosition,
    required this.radiusM,
  });

  /// Current distance from anchor drop point in metres.
  double distanceM(LatLng currentPosition) {
    return haversineDistanceM(dropPosition, currentPosition);
  }

  /// Whether the vessel is dragging (outside the watch radius).
  bool isDragging(LatLng currentPosition) {
    return distanceM(currentPosition) > radiusM;
  }
}
