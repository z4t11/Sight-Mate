/// Models representing states, directions, and results for persistent 360° object search.

/// Persistent lifecycle state of the object search system.
enum ObjectSearchState {
  /// No object-search request is active.
  idle,

  /// Continuously analysing camera frames for the requested object.
  searching,

  /// Object is not currently visible; the app is actively guiding the user to scan or rotate.
  guiding,

  /// Target has been detected and the app is communicating its spatial location.
  found,
}

/// Detection confidence status for a specific camera frame.
enum TargetDetectionStatus {
  found,
  notFound,
  uncertain,
}

/// Estimated direction of the target relative to the camera lens.
enum ObjectDirection {
  ahead,
  left,
  right,
  farLeft,
  farRight,
  nearEdge,
  unknown,
}

extension ObjectDirectionX on ObjectDirection {
  String get label {
    switch (this) {
      case ObjectDirection.ahead:
        return 'ahead';
      case ObjectDirection.left:
        return 'on your left';
      case ObjectDirection.right:
        return 'on your right';
      case ObjectDirection.farLeft:
        return 'on your far left';
      case ObjectDirection.farRight:
        return 'on your far right';
      case ObjectDirection.nearEdge:
        return 'near the edge of view';
      case ObjectDirection.unknown:
        return 'nearby';
    }
  }

  String get turnInstruction {
    switch (this) {
      case ObjectDirection.ahead:
        return 'Walk straight ahead towards it.';
      case ObjectDirection.left:
      case ObjectDirection.farLeft:
        return 'Turn your phone a little to the left toward it.';
      case ObjectDirection.right:
      case ObjectDirection.farRight:
        return 'Turn your phone a little to the right toward it.';
      case ObjectDirection.nearEdge:
        return 'Turn your phone slightly to bring it into the center.';
      case ObjectDirection.unknown:
        return 'Keep phone pointed forward.';
    }
  }
}

/// Result returned from AI frame analysis for a target object.
class ObjectSearchResult {
  final TargetDetectionStatus status;
  final ObjectDirection direction;
  final String distance;
  final String description;
  final String guidance;
  final String rawResponse;

  const ObjectSearchResult({
    required this.status,
    required this.direction,
    required this.distance,
    required this.description,
    required this.guidance,
    this.rawResponse = '',
  });

  bool get isFound => status == TargetDetectionStatus.found;
  bool get isUncertain => status == TargetDetectionStatus.uncertain;
  bool get isNotFound => status == TargetDetectionStatus.notFound;
}
