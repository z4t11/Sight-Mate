/// Runtime navigation state — current position, route, confidence.
class NavState {
  final String? currentNodeId;
  final String? customLocationName;
  final String? activeDestination;
  final double? latitude;
  final double? longitude;
  final List<String> route;       // ordered list of node IDs to destination
  final int routeIndex;           // which step of route we're on
  final int stepsSinceLast;       // steps walked since last confirmed landmark
  final double confidence;        // 0.0 – 1.0; < 0.5 triggers "I think you're near…?"
  final double headingDegrees;    // last known compass heading
  final bool isNavigating;

  const NavState({
    this.currentNodeId,
    this.customLocationName,
    this.activeDestination,
    this.latitude,
    this.longitude,
    this.route = const [],
    this.routeIndex = 0,
    this.stepsSinceLast = 0,
    this.confidence = 0.0,
    this.headingDegrees = 0.0,
    this.isNavigating = false,
  });

  bool get hasRoute => route.isNotEmpty;
  bool get isAtDestination =>
      hasRoute && routeIndex >= route.length - 1;
  bool get hasKnownLocation =>
      currentNodeId != null || customLocationName != null;
  String? get locationDisplayName =>
      customLocationName ?? currentNodeId;
  bool get hasGps => latitude != null && longitude != null;

  NavState copyWith({
    String? currentNodeId,
    String? customLocationName,
    String? activeDestination,
    double? latitude,
    double? longitude,
    List<String>? route,
    int? routeIndex,
    int? stepsSinceLast,
    double? confidence,
    double? headingDegrees,
    bool? isNavigating,
    bool clearCurrentNode = false,
    bool clearCustomLocation = false,
    bool clearRoute = false,
  }) =>
      NavState(
        currentNodeId:
            clearCurrentNode ? null : (currentNodeId ?? this.currentNodeId),
        customLocationName: clearCustomLocation
            ? null
            : (customLocationName ?? this.customLocationName),
        activeDestination: activeDestination ?? this.activeDestination,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        route: clearRoute ? const [] : (route ?? this.route),
        routeIndex: routeIndex ?? this.routeIndex,
        stepsSinceLast: stepsSinceLast ?? this.stepsSinceLast,
        confidence: confidence ?? this.confidence,
        headingDegrees: headingDegrees ?? this.headingDegrees,
        isNavigating: isNavigating ?? this.isNavigating,
      );
}
