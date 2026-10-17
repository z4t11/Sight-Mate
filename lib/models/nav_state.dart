/// Runtime navigation state — current position, route, confidence.
class NavState {
  final String? currentNodeId;
  final List<String> route;       // ordered list of node IDs to destination
  final int routeIndex;           // which step of route we're on
  final int stepsSinceLast;       // steps walked since last confirmed landmark
  final double confidence;        // 0.0 – 1.0; < 0.5 triggers "I think you're near…?"
  final double headingDegrees;    // last known compass heading
  final bool isNavigating;

  const NavState({
    this.currentNodeId,
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

  NavState copyWith({
    String? currentNodeId,
    List<String>? route,
    int? routeIndex,
    int? stepsSinceLast,
    double? confidence,
    double? headingDegrees,
    bool? isNavigating,
    bool clearCurrentNode = false,
  }) =>
      NavState(
        currentNodeId:
            clearCurrentNode ? null : (currentNodeId ?? this.currentNodeId),
        route: route ?? this.route,
        routeIndex: routeIndex ?? this.routeIndex,
        stepsSinceLast: stepsSinceLast ?? this.stepsSinceLast,
        confidence: confidence ?? this.confidence,
        headingDegrees: headingDegrees ?? this.headingDegrees,
        isNavigating: isNavigating ?? this.isNavigating,
      );
}
