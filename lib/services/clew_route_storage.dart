import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/clew_route_models.dart';

/// Persistent Local Storage for Clew-Style Indoor Routes.
/// Survives app restarts; stores breadcrumbs, keypoints, and auto-generated return paths.
class ClewRouteStorage {
  static const String _fileName = 'clew_indoor_routes.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Load all stored Clew routes.
  static Future<List<ClewRoute>> loadAllRoutes() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        final defaults = _getDefaultDemoRoutes();
        await saveAllRoutes(defaults);
        return defaults;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return _getDefaultDemoRoutes();
      final list = jsonDecode(raw) as List;
      return list.map((item) => ClewRoute.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[ClewRouteStorage] Error loading routes: $e');
      return _getDefaultDemoRoutes();
    }
  }

  /// Save all routes to disk.
  static Future<void> saveAllRoutes(List<ClewRoute> routes) async {
    try {
      final file = await _getFile();
      final raw = jsonEncode(routes.map((r) => r.toJson()).toList());
      await file.writeAsString(raw);
    } catch (e) {
      debugPrint('[ClewRouteStorage] Error saving all routes: $e');
    }
  }

  /// Save a newly recorded route, automatically creating and saving its return path!
  static Future<void> saveRoute(ClewRoute forwardRoute) async {
    final routes = await loadAllRoutes();

    // Remove existing routes with identical start and destination
    routes.removeWhere((r) =>
        r.startName.toLowerCase() == forwardRoute.startName.toLowerCase() &&
        r.destinationName.toLowerCase() == forwardRoute.destinationName.toLowerCase());

    final returnRoute = forwardRoute.createReturnRoute();
    routes.removeWhere((r) =>
        r.startName.toLowerCase() == returnRoute.startName.toLowerCase() &&
        r.destinationName.toLowerCase() == returnRoute.destinationName.toLowerCase());

    routes.add(forwardRoute);
    routes.add(returnRoute);

    await saveAllRoutes(routes);
    debugPrint('[ClewRouteStorage] Saved route "${forwardRoute.name}" and return route "${returnRoute.name}". Total: ${routes.length}');
  }

  /// Find a route matching start and destination names.
  static Future<ClewRoute?> findRoute({
    String? startName,
    required String destinationName,
  }) async {
    final routes = await loadAllRoutes();
    final dest = destinationName.toLowerCase().trim();
    final start = startName?.toLowerCase().trim();

    // 1. Exact match for start and dest
    if (start != null && start.isNotEmpty) {
      for (final r in routes) {
        if (r.startName.toLowerCase() == start && r.destinationName.toLowerCase() == dest) {
          return r;
        }
      }
    }

    // 2. Exact match for destination only
    for (final r in routes) {
      if (r.destinationName.toLowerCase() == dest) {
        return r;
      }
    }

    // 3. Partial match
    for (final r in routes) {
      if (r.destinationName.toLowerCase().contains(dest) || dest.contains(r.destinationName.toLowerCase())) {
        return r;
      }
    }

    return null;
  }

  /// Default verified demo routes (Staff Room <-> Software Lab).
  static List<ClewRoute> _getDefaultDemoRoutes() {
    final now = DateTime.now();

    final crumbs = <ClewCrumb>[
      ClewCrumb(x: 0.0, y: 0.0, heading: 90.0, stepCount: 0, timestamp: now),
      ClewCrumb(x: 3.5, y: 0.0, heading: 90.0, stepCount: 5, timestamp: now),
      ClewCrumb(x: 7.0, y: 0.0, heading: 90.0, stepCount: 10, timestamp: now, visualLandmark: 'Corridor corner'),
      ClewCrumb(x: 7.0, y: 3.5, heading: 0.0, stepCount: 15, timestamp: now),
      ClewCrumb(x: 7.0, y: 7.0, heading: 0.0, stepCount: 20, timestamp: now),
      ClewCrumb(x: 7.0, y: 10.5, heading: 0.0, stepCount: 25, timestamp: now, visualLandmark: 'Software Lab sign'),
    ];

    final keypoints = <ClewKeypoint>[
      const ClewKeypoint(
        index: 0,
        x: 0.0,
        y: 0.0,
        heading: 90.0,
        turnAngle: 0.0,
        cumulativeSteps: 0,
        cumulativeMeters: 0.0,
        instruction: 'Start at Staff Room. Walk forward along the corridor for 10 steps.',
        landmarkDescription: 'Staff Room doorway',
      ),
      const ClewKeypoint(
        index: 1,
        x: 7.0,
        y: 0.0,
        heading: 0.0,
        turnAngle: -90.0,
        cumulativeSteps: 10,
        cumulativeMeters: 7.0,
        instruction: 'Turn left into the main hallway, then walk forward 15 steps.',
        landmarkDescription: 'Corridor junction corner',
      ),
      const ClewKeypoint(
        index: 2,
        x: 7.0,
        y: 10.5,
        heading: 0.0,
        turnAngle: 0.0,
        cumulativeSteps: 25,
        cumulativeMeters: 17.5,
        instruction: 'You have arrived at the Software Lab.',
        landmarkDescription: 'Software Lab entrance',
      ),
    ];

    final forward = ClewRoute(
      id: 'demo_staff_to_software_lab',
      name: 'Staff Room to Software Lab',
      startName: 'Staff Room',
      destinationName: 'Software Lab',
      createdAt: now,
      crumbs: crumbs,
      keypoints: keypoints,
      totalSteps: 25,
      totalDistanceMeters: 17.5,
    );

    return [forward, forward.createReturnRoute()];
  }
}
