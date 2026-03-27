class RouteOptions {
  final double safetyMargin;
  final bool avoidShallows;
  final bool avoidBridges;
  final bool preferDeepWater;

  const RouteOptions({
    this.safetyMargin = 0.5,
    this.avoidShallows = true,
    this.avoidBridges = true,
    this.preferDeepWater = false,
  });

  RouteOptions copyWith({
    double? safetyMargin,
    bool? avoidShallows,
    bool? avoidBridges,
    bool? preferDeepWater,
  }) {
    return RouteOptions(
      safetyMargin: safetyMargin ?? this.safetyMargin,
      avoidShallows: avoidShallows ?? this.avoidShallows,
      avoidBridges: avoidBridges ?? this.avoidBridges,
      preferDeepWater: preferDeepWater ?? this.preferDeepWater,
    );
  }
}
