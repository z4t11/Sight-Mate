/// Complete Spatial Route Hierarchy for Indoor Navigation (Section 6.C).

class IndoorBuilding {
  final String id;
  final String name;

  const IndoorBuilding({
    required this.id,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory IndoorBuilding.fromJson(Map<String, dynamic> j) => IndoorBuilding(
        id: j['id'] as String? ?? 'main_building',
        name: j['name'] as String? ?? 'Main Building',
      );
}

class IndoorFloor {
  final String id;
  final String buildingId;
  final String floorLabel;

  const IndoorFloor({
    required this.id,
    required this.buildingId,
    required this.floorLabel,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'buildingId': buildingId,
        'floorLabel': floorLabel,
      };

  factory IndoorFloor.fromJson(Map<String, dynamic> j) => IndoorFloor(
        id: j['id'] as String? ?? 'floor_0',
        buildingId: j['buildingId'] as String? ?? 'main_building',
        floorLabel: j['floorLabel'] as String? ?? 'Ground Floor',
      );
}

class IndoorLocation {
  final String id;
  final String floorId;
  final String name;
  final String locationType; // classroom, lab, staff_room, corridor, stairs, entrance

  const IndoorLocation({
    required this.id,
    required this.floorId,
    required this.name,
    required this.locationType,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'floorId': floorId,
        'name': name,
        'locationType': locationType,
      };

  factory IndoorLocation.fromJson(Map<String, dynamic> j) => IndoorLocation(
        id: j['id'] as String? ?? '',
        floorId: j['floorId'] as String? ?? 'floor_0',
        name: j['name'] as String? ?? '',
        locationType: j['locationType'] as String? ?? 'room',
      );
}

/// A recorded visual checkpoint along an indoor route (Section 6.C).
class RouteCheckpoint {
  final String id;
  final String routeId;
  final int sequenceNumber;
  final String landmarkType; // corner, doorway, sign, junction, destination, stairs
  final String landmarkDescription;
  final String? visualDescriptorHash; // Low-res luminance/edge signature for matching
  final double expectedOrientation; // Degrees (0-360)
  final String instruction;
  final double confidenceThreshold;

  const RouteCheckpoint({
    required this.id,
    required this.routeId,
    required this.sequenceNumber,
    required this.landmarkType,
    required this.landmarkDescription,
    this.visualDescriptorHash,
    required this.expectedOrientation,
    required this.instruction,
    this.confidenceThreshold = 0.65,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'routeId': routeId,
        'sequenceNumber': sequenceNumber,
        'landmarkType': landmarkType,
        'landmarkDescription': landmarkDescription,
        'visualDescriptorHash': visualDescriptorHash,
        'expectedOrientation': expectedOrientation,
        'instruction': instruction,
        'confidenceThreshold': confidenceThreshold,
      };

  factory RouteCheckpoint.fromJson(Map<String, dynamic> j) => RouteCheckpoint(
        id: j['id'] as String? ?? '',
        routeId: j['routeId'] as String? ?? '',
        sequenceNumber: (j['sequenceNumber'] as num?)?.toInt() ?? 0,
        landmarkType: j['landmarkType'] as String? ?? 'waypoint',
        landmarkDescription: j['landmarkDescription'] as String? ?? '',
        visualDescriptorHash: j['visualDescriptorHash'] as String?,
        expectedOrientation: (j['expectedOrientation'] as num?)?.toDouble() ?? 0.0,
        instruction: j['instruction'] as String? ?? '',
        confidenceThreshold: (j['confidenceThreshold'] as num?)?.toDouble() ?? 0.65,
      );
}

/// A segment connecting two consecutive checkpoints (Section 6.C).
class RouteSegment {
  final String id;
  final String routeId;
  final String startCheckpointId;
  final String endCheckpointId;
  final String expectedDirection; // straight, left, right, slight left, slight right
  final int targetSteps;
  final double targetMeters;
  final List<String> expectedLandmarks;
  final String movementInstruction;
  final String recoveryInstruction;

  const RouteSegment({
    required this.id,
    required this.routeId,
    required this.startCheckpointId,
    required this.endCheckpointId,
    required this.expectedDirection,
    required this.targetSteps,
    required this.targetMeters,
    required this.expectedLandmarks,
    required this.movementInstruction,
    required this.recoveryInstruction,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'routeId': routeId,
        'startCheckpointId': startCheckpointId,
        'endCheckpointId': endCheckpointId,
        'expectedDirection': expectedDirection,
        'targetSteps': targetSteps,
        'targetMeters': targetMeters,
        'expectedLandmarks': expectedLandmarks,
        'movementInstruction': movementInstruction,
        'recoveryInstruction': recoveryInstruction,
      };

  factory RouteSegment.fromJson(Map<String, dynamic> j) => RouteSegment(
        id: j['id'] as String? ?? '',
        routeId: j['routeId'] as String? ?? '',
        startCheckpointId: j['startCheckpointId'] as String? ?? '',
        endCheckpointId: j['endCheckpointId'] as String? ?? '',
        expectedDirection: j['expectedDirection'] as String? ?? 'straight',
        targetSteps: (j['targetSteps'] as num?)?.toInt() ?? 10,
        targetMeters: (j['targetMeters'] as num?)?.toDouble() ?? 7.0,
        expectedLandmarks: (j['expectedLandmarks'] as List? ?? []).map((e) => e.toString()).toList(),
        movementInstruction: j['movementInstruction'] as String? ?? 'Walk forward.',
        recoveryInstruction: j['recoveryInstruction'] as String? ?? 'Stop and turn around slowly to relocalize.',
      );
}

/// A complete persistent indoor route (Section 6.C).
class RecordedIndoorRoute {
  final String id;
  final String buildingId;
  final String startLocationId;
  final String startLocationName;
  final String destinationLocationId;
  final String destinationLocationName;
  final int routeVersion;
  final DateTime createdAt;
  final String routeStatus; // verified, draft
  final List<RouteCheckpoint> checkpoints;
  final List<RouteSegment> segments;

  const RecordedIndoorRoute({
    required this.id,
    required this.buildingId,
    required this.startLocationId,
    required this.startLocationName,
    required this.destinationLocationId,
    required this.destinationLocationName,
    this.routeVersion = 1,
    required this.createdAt,
    this.routeStatus = 'verified',
    required this.checkpoints,
    required this.segments,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'buildingId': buildingId,
        'startLocationId': startLocationId,
        'startLocationName': startLocationName,
        'destinationLocationId': destinationLocationId,
        'destinationLocationName': destinationLocationName,
        'routeVersion': routeVersion,
        'createdAt': createdAt.toIso8601String(),
        'routeStatus': routeStatus,
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
        'segments': segments.map((s) => s.toJson()).toList(),
      };

  factory RecordedIndoorRoute.fromJson(Map<String, dynamic> j) => RecordedIndoorRoute(
        id: j['id'] as String? ?? '',
        buildingId: j['buildingId'] as String? ?? 'software_block',
        startLocationId: j['startLocationId'] as String? ?? '',
        startLocationName: j['startLocationName'] as String? ?? 'Start',
        destinationLocationId: j['destinationLocationId'] as String? ?? '',
        destinationLocationName: j['destinationLocationName'] as String? ?? 'Destination',
        routeVersion: (j['routeVersion'] as num?)?.toInt() ?? 1,
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        routeStatus: j['routeStatus'] as String? ?? 'verified',
        checkpoints: (j['checkpoints'] as List? ?? [])
            .map((c) => RouteCheckpoint.fromJson(c as Map<String, dynamic>))
            .toList(),
        segments: (j['segments'] as List? ?? [])
            .map((s) => RouteSegment.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
