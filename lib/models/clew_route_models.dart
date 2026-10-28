/// A high-resolution spatial crumb recorded during indoor walking.
/// Clew-inspired: recorded automatically every step/meter without tapping.
class ClewCrumb {
  final double x; // Relative X coordinate in meters (East / Right)
  final double y; // Relative Y coordinate in meters (North / Forward)
  final double heading; // Compass heading in degrees (0 - 360)
  final int stepCount; // Cumulative steps from start
  final DateTime timestamp;
  final String? visualLandmark; // Optional visual description detected by Gemini

  const ClewCrumb({
    required this.x,
    required this.y,
    required this.heading,
    required this.stepCount,
    required this.timestamp,
    this.visualLandmark,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'heading': heading,
        'stepCount': stepCount,
        'timestamp': timestamp.toIso8601String(),
        'visualLandmark': visualLandmark,
      };

  factory ClewCrumb.fromJson(Map<String, dynamic> j) => ClewCrumb(
        x: (j['x'] as num?)?.toDouble() ?? 0.0,
        y: (j['y'] as num?)?.toDouble() ?? 0.0,
        heading: (j['heading'] as num?)?.toDouble() ?? 0.0,
        stepCount: (j['stepCount'] as num?)?.toInt() ?? 0,
        timestamp: j['timestamp'] != null
            ? DateTime.tryParse(j['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        visualLandmark: j['visualLandmark'] as String?,
      );
}

/// A simplified key decision point along the route (Start, Turns, Destination).
class ClewKeypoint {
  final int index;
  final double x;
  final double y;
  final double heading; // Target orientation at this keypoint
  final double turnAngle; // Turn angle relative to previous keypoint (-180 to +180)
  final int cumulativeSteps;
  final double cumulativeMeters;
  final String instruction; // e.g. "Walk forward 12 steps", "Turn left"
  final String? landmarkDescription;

  const ClewKeypoint({
    required this.index,
    required this.x,
    required this.y,
    required this.heading,
    required this.turnAngle,
    required this.cumulativeSteps,
    required this.cumulativeMeters,
    required this.instruction,
    this.landmarkDescription,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'x': x,
        'y': y,
        'heading': heading,
        'turnAngle': turnAngle,
        'cumulativeSteps': cumulativeSteps,
        'cumulativeMeters': cumulativeMeters,
        'instruction': instruction,
        'landmarkDescription': landmarkDescription,
      };

  factory ClewKeypoint.fromJson(Map<String, dynamic> j) => ClewKeypoint(
        index: (j['index'] as num?)?.toInt() ?? 0,
        x: (j['x'] as num?)?.toDouble() ?? 0.0,
        y: (j['y'] as num?)?.toDouble() ?? 0.0,
        heading: (j['heading'] as num?)?.toDouble() ?? 0.0,
        turnAngle: (j['turnAngle'] as num?)?.toDouble() ?? 0.0,
        cumulativeSteps: (j['cumulativeSteps'] as num?)?.toInt() ?? 0,
        cumulativeMeters: (j['cumulativeMeters'] as num?)?.toDouble() ?? 0.0,
        instruction: j['instruction'] as String? ?? 'Walk forward.',
        landmarkDescription: j['landmarkDescription'] as String?,
      );
}

/// Complete Clew-style indoor route supporting bidirectional retracing.
class ClewRoute {
  final String id;
  final String name;
  final String startName;
  final String destinationName;
  final DateTime createdAt;
  final List<ClewCrumb> crumbs;
  final List<ClewKeypoint> keypoints;
  final int totalSteps;
  final double totalDistanceMeters;

  const ClewRoute({
    required this.id,
    required this.name,
    required this.startName,
    required this.destinationName,
    required this.createdAt,
    required this.crumbs,
    required this.keypoints,
    required this.totalSteps,
    required this.totalDistanceMeters,
  });

  /// Generate an inverted return route (Clew signature: B -> A).
  ClewRoute createReturnRoute() {
    final reversedCrumbs = crumbs.reversed.map((c) {
      return ClewCrumb(
        x: c.x,
        y: c.y,
        heading: (c.heading + 180) % 360,
        stepCount: totalSteps - c.stepCount,
        timestamp: c.timestamp,
        visualLandmark: c.visualLandmark,
      );
    }).toList();

    final List<ClewKeypoint> reversedKeypoints = [];
    final original = keypoints.reversed.toList();

    for (int i = 0; i < original.length; i++) {
      final cur = original[i];
      final targetHeading = (cur.heading + 180) % 360;

      String inst;
      double turnAngle = 0.0;
      if (i == 0) {
        inst = "Start from $destinationName. Face $startName and walk forward.";
      } else if (i == original.length - 1) {
        inst = "Arrived at $startName.";
      } else {
        final prev = original[i - 1];
        final prevHeading = (prev.heading + 180) % 360;
        turnAngle = ((targetHeading - prevHeading + 540) % 360) - 180;
        final turnWord = turnAngle > 20 ? "right" : (turnAngle < -20 ? "left" : "straight");
        inst = "Turn $turnWord and continue straight.";
      }

      reversedKeypoints.add(ClewKeypoint(
        index: i,
        x: cur.x,
        y: cur.y,
        heading: targetHeading,
        turnAngle: turnAngle,
        cumulativeSteps: totalSteps - cur.cumulativeSteps,
        cumulativeMeters: totalDistanceMeters - cur.cumulativeMeters,
        instruction: inst,
        landmarkDescription: cur.landmarkDescription,
      ));
    }

    return ClewRoute(
      id: '${id}_return',
      name: '$destinationName to $startName',
      startName: destinationName,
      destinationName: startName,
      createdAt: DateTime.now(),
      crumbs: reversedCrumbs,
      keypoints: reversedKeypoints,
      totalSteps: totalSteps,
      totalDistanceMeters: totalDistanceMeters,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startName': startName,
        'destinationName': destinationName,
        'createdAt': createdAt.toIso8601String(),
        'crumbs': crumbs.map((c) => c.toJson()).toList(),
        'keypoints': keypoints.map((k) => k.toJson()).toList(),
        'totalSteps': totalSteps,
        'totalDistanceMeters': totalDistanceMeters,
      };

  factory ClewRoute.fromJson(Map<String, dynamic> j) => ClewRoute(
        id: j['id'] as String? ?? 'route_${DateTime.now().millisecondsSinceEpoch}',
        name: j['name'] as String? ?? 'Indoor Route',
        startName: j['startName'] as String? ?? 'Start',
        destinationName: j['destinationName'] as String? ?? 'Destination',
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        crumbs: (j['crumbs'] as List? ?? [])
            .map((c) => ClewCrumb.fromJson(c as Map<String, dynamic>))
            .toList(),
        keypoints: (j['keypoints'] as List? ?? [])
            .map((k) => ClewKeypoint.fromJson(k as Map<String, dynamic>))
            .toList(),
        totalSteps: (j['totalSteps'] as num?)?.toInt() ?? 0,
        totalDistanceMeters: (j['totalDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      );
}
