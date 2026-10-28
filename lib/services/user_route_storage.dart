import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/map_node.dart';
import '../models/map_edge.dart';
import '../models/spatial_route_models.dart';
import '../utils/compass_helper.dart';

/// Legacy RecordedLeg for backward compatibility with RouteRecorderScreen.
class RecordedLeg {
  final String label;
  final int steps;
  final double heading;

  const RecordedLeg({
    required this.label,
    required this.steps,
    required this.heading,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'steps': steps,
        'heading': heading,
      };

  factory RecordedLeg.fromJson(Map<String, dynamic> j) => RecordedLeg(
        label: j['label'] as String? ?? 'Waypoint',
        steps: (j['steps'] as num?)?.toInt() ?? 10,
        heading: (j['heading'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Persistent Storage for Spatial Indoor Routes (Section 6.A - 6.C).
/// Saves and retrieves full RecordedIndoorRoute models, automatically
/// generating forward and return routes and feeding the campus graph.
class UserRouteStorage {
  static const String _routesFileName = 'recorded_indoor_routes.json';
  static const String _graphFileName = 'user_recorded_routes.json';

  static Future<File> _getRoutesFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_routesFileName');
  }

  static Future<File> _getGraphFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_graphFileName');
  }

  /// Load all structured indoor routes.
  static Future<List<RecordedIndoorRoute>> loadAllIndoorRoutes() async {
    try {
      final file = await _getRoutesFile();
      if (!await file.exists()) {
        // Return default seeded demo route: Staff Room to Software Lab
        return [_getDefaultDemoRoute(), _getDefaultDemoReturnRoute()];
      }
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List;
      final routes = list
          .map((item) => RecordedIndoorRoute.fromJson(item as Map<String, dynamic>))
          .toList();

      if (routes.isEmpty) {
        return [_getDefaultDemoRoute(), _getDefaultDemoReturnRoute()];
      }
      return routes;
    } catch (_) {
      return [_getDefaultDemoRoute(), _getDefaultDemoReturnRoute()];
    }
  }

  /// Find a recorded route matching starting point and destination.
  static Future<RecordedIndoorRoute?> findRoute({
    required String startName,
    required String destinationName,
  }) async {
    final all = await loadAllIndoorRoutes();
    final cleanStart = startName.trim().toLowerCase();
    final cleanDest = destinationName.trim().toLowerCase();

    for (final r in all) {
      final rStart = r.startLocationName.toLowerCase();
      final rDest = r.destinationLocationName.toLowerCase();

      final startMatches = rStart.contains(cleanStart) || cleanStart.contains(rStart);
      final destMatches = rDest.contains(cleanDest) || cleanDest.contains(rDest);

      if (startMatches && destMatches) {
        return r;
      }
    }
    return null;
  }

  /// Save a new structured indoor route and its reverse return path.
  static Future<void> saveIndoorRoute(RecordedIndoorRoute route) async {
    final routes = await loadAllIndoorRoutes();
    routes.removeWhere((r) => r.id == route.id);
    routes.add(route);

    // Also auto-generate the reverse return route!
    final returnRoute = _generateReturnRoute(route);
    routes.removeWhere((r) => r.id == returnRoute.id);
    routes.add(returnRoute);

    final file = await _getRoutesFile();
    final jsonList = routes.map((r) => r.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));

    // Also sync with campus graph nodes/edges
    await _syncCampusGraph(routes);
  }

  /// Record and save a route walked by the user (Section 6.A).
  static Future<Map<String, dynamic>> saveRoute({
    required String startName,
    required String destName,
    required List<RecordedLeg> legs,
    String buildingName = 'Software Block',
    String floorName = 'Floor 1',
  }) async {
    final routeId = 'route_${_slug(startName)}_to_${_slug(destName)}';

    final checkpoints = <RouteCheckpoint>[];
    final segments = <RouteSegment>[];

    // Origin Checkpoint
    final startChkId = 'chk_${_slug(startName)}';
    checkpoints.add(RouteCheckpoint(
      id: startChkId,
      routeId: routeId,
      sequenceNumber: 0,
      landmarkType: 'doorway',
      landmarkDescription: startName,
      expectedOrientation: legs.isNotEmpty ? legs.first.heading : 0.0,
      instruction: "Start at $startName doorway.",
    ));

    String prevChkId = startChkId;
    double prevHeading = legs.isNotEmpty ? legs.first.heading : 0.0;

    for (int i = 0; i < legs.length; i++) {
      final leg = legs[i];
      final isLast = (i == legs.length - 1);
      final chkId = isLast ? 'chk_${_slug(destName)}' : 'chk_${_slug(startName)}_wp_$i';
      final chkDesc = isLast ? destName : leg.label;

      checkpoints.add(RouteCheckpoint(
        id: chkId,
        routeId: routeId,
        sequenceNumber: i + 1,
        landmarkType: isLast ? 'destination' : 'turn',
        landmarkDescription: chkDesc,
        expectedOrientation: leg.heading,
        instruction: isLast ? "Arrive at $destName." : "Turn towards $chkDesc.",
      ));

      final turnWord = i > 0
          ? CompassHelper.turnInstruction(prevHeading, leg.heading)
          : CompassHelper.relativeDirection(0.0, leg.heading);

      segments.add(RouteSegment(
        id: 'seg_${prevChkId}_to_$chkId',
        routeId: routeId,
        startCheckpointId: prevChkId,
        endCheckpointId: chkId,
        expectedDirection: turnWord,
        targetSteps: leg.steps,
        targetMeters: (leg.steps * 0.7),
        expectedLandmarks: [chkDesc],
        movementInstruction: "$turnWord. Walk ${leg.steps} steps forward.",
        recoveryInstruction: "Stop and turn around slowly until you spot the previous doorway.",
      ));

      prevChkId = chkId;
      prevHeading = leg.heading;
    }

    final newRoute = RecordedIndoorRoute(
      id: routeId,
      buildingId: _slug(buildingName),
      startLocationId: _slug(startName),
      startLocationName: startName,
      destinationLocationId: _slug(destName),
      destinationLocationName: destName,
      createdAt: DateTime.now(),
      checkpoints: checkpoints,
      segments: segments,
    );

    await saveIndoorRoute(newRoute);
    return await loadCustomGraph();
  }

  /// Generate symmetric reverse return route with inverted headings.
  static RecordedIndoorRoute _generateReturnRoute(RecordedIndoorRoute forward) {
    final returnRouteId = 'route_${forward.destinationLocationId}_to_${forward.startLocationId}';
    final revCheckpoints = <RouteCheckpoint>[];
    final revSegments = <RouteSegment>[];

    final fwdChks = forward.checkpoints.reversed.toList();
    for (int i = 0; i < fwdChks.length; i++) {
      final chk = fwdChks[i];
      final invertedHeading = (chk.expectedOrientation + 180.0) % 360.0;
      revCheckpoints.add(RouteCheckpoint(
        id: 'rev_${chk.id}',
        routeId: returnRouteId,
        sequenceNumber: i,
        landmarkType: chk.landmarkType,
        landmarkDescription: chk.landmarkDescription,
        expectedOrientation: invertedHeading,
        instruction: chk.instruction,
      ));
    }

    final fwdSegs = forward.segments.reversed.toList();
    for (int i = 0; i < fwdSegs.length; i++) {
      final seg = fwdSegs[i];
      revSegments.add(RouteSegment(
        id: 'rev_${seg.id}',
        routeId: returnRouteId,
        startCheckpointId: 'rev_${seg.endCheckpointId}',
        endCheckpointId: 'rev_${seg.startCheckpointId}',
        expectedDirection: _invertDirection(seg.expectedDirection),
        targetSteps: seg.targetSteps,
        targetMeters: seg.targetMeters,
        expectedLandmarks: seg.expectedLandmarks,
        movementInstruction: "Continue along corridor for ${seg.targetSteps} steps.",
        recoveryInstruction: seg.recoveryInstruction,
      ));
    }

    return RecordedIndoorRoute(
      id: returnRouteId,
      buildingId: forward.buildingId,
      startLocationId: forward.destinationLocationId,
      startLocationName: forward.destinationLocationName,
      destinationLocationId: forward.startLocationId,
      destinationLocationName: forward.startLocationName,
      createdAt: DateTime.now(),
      checkpoints: revCheckpoints,
      segments: revSegments,
    );
  }

  static String _invertDirection(String dir) {
    final d = dir.toLowerCase();
    if (d.contains('left')) return 'Turn right';
    if (d.contains('right')) return 'Turn left';
    return 'Continue straight';
  }

  /// Sync custom graph file with all indoor routes for Dijkstra graph compatibility.
  static Future<void> _syncCampusGraph(List<RecordedIndoorRoute> routes) async {
    final nodes = <MapNode>[];
    final edges = <MapEdge>[];

    for (final r in routes) {
      for (final c in r.checkpoints) {
        if (!nodes.any((n) => n.id == c.id)) {
          nodes.add(MapNode(
            id: c.id,
            name: c.landmarkDescription,
            floor: 1,
            expectedSigns: [c.landmarkDescription.toLowerCase()],
            hazards: [],
            description: c.instruction,
          ));
        }
      }
      for (final s in r.segments) {
        edges.add(MapEdge(
          from: s.startCheckpointId,
          to: s.endCheckpointId,
          steps: s.targetSteps,
          heading: 0.0,
        ));
      }
    }

    final graphFile = await _getGraphFile();
    final json = {
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
    };
    await graphFile.writeAsString(jsonEncode(json));
  }

  /// Load graph for backward-compatible Dijkstra path planning.
  static Future<Map<String, dynamic>> loadCustomGraph() async {
    try {
      final file = await _getGraphFile();
      if (!await file.exists()) {
        final routes = await loadAllIndoorRoutes();
        await _syncCampusGraph(routes);
      }
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final nodes = <MapNode>[];
      for (final n in (json['nodes'] as List? ?? [])) {
        nodes.add(MapNode.fromJson(n as Map<String, dynamic>));
      }

      final edges = <MapEdge>[];
      for (final e in (json['edges'] as List? ?? [])) {
        edges.add(MapEdge.fromJson(e as Map<String, dynamic>));
      }

      return {'nodes': nodes, 'edges': edges};
    } catch (_) {
      return {'nodes': <MapNode>[], 'edges': <MapEdge>[]};
    }
  }

  static String _slug(String text) => text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  /// Seeded Coordinator presentation route: Software Block Staff Room to Software Lab
  static RecordedIndoorRoute _getDefaultDemoRoute() {
    return RecordedIndoorRoute(
      id: 'route_staff_room_to_software_lab',
      buildingId: 'software_block',
      startLocationId: 'staff_room',
      startLocationName: 'Staff Room',
      destinationLocationId: 'software_lab',
      destinationLocationName: 'Software Lab',
      createdAt: DateTime(2026, 10, 27),
      checkpoints: const [
        RouteCheckpoint(
          id: 'chk_staff_room',
          routeId: 'route_staff_room_to_software_lab',
          sequenceNumber: 0,
          landmarkType: 'doorway',
          landmarkDescription: 'Staff Room Door',
          expectedOrientation: 0.0,
          instruction: 'Exit Staff Room into the software section hallway.',
        ),
        RouteCheckpoint(
          id: 'chk_corridor_junction',
          routeId: 'route_staff_room_to_software_lab',
          sequenceNumber: 1,
          landmarkType: 'turn',
          landmarkDescription: 'Corridor Corner Junction',
          expectedOrientation: 270.0,
          instruction: 'Turn left at the 90 degree corner.',
        ),
        RouteCheckpoint(
          id: 'chk_software_lab',
          routeId: 'route_staff_room_to_software_lab',
          sequenceNumber: 2,
          landmarkType: 'destination',
          landmarkDescription: 'Software Lab Door',
          expectedOrientation: 270.0,
          instruction: 'Software Lab entrance on your left.',
        ),
      ],
      segments: const [
        RouteSegment(
          id: 'seg_staff_to_junction',
          routeId: 'route_staff_room_to_software_lab',
          startCheckpointId: 'chk_staff_room',
          endCheckpointId: 'chk_corridor_junction',
          expectedDirection: 'Walk straight',
          targetSteps: 14,
          targetMeters: 9.8,
          expectedLandmarks: ['Software corridor notice board'],
          movementInstruction: 'Walk straight down the corridor for 14 steps.',
          recoveryInstruction: 'Stop and turn around slowly if you do not see the notice board.',
        ),
        RouteSegment(
          id: 'seg_junction_to_lab',
          routeId: 'route_staff_room_to_software_lab',
          startCheckpointId: 'chk_corridor_junction',
          endCheckpointId: 'chk_software_lab',
          expectedDirection: 'Turn left',
          targetSteps: 18,
          targetMeters: 12.6,
          expectedLandmarks: ['Software Lab blue sign'],
          movementInstruction: 'Turn left now. Walk 18 steps forward towards Software Lab.',
          recoveryInstruction: 'Stop. Face the wall and check the door signs with your camera.',
        ),
      ],
    );
  }

  static RecordedIndoorRoute _getDefaultDemoReturnRoute() {
    return _generateReturnRoute(_getDefaultDemoRoute());
  }
}
