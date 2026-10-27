import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/map_node.dart';
import '../models/map_edge.dart';

/// Recorded waypoint segment during Route Recorder mode.
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

/// Manages persistence of custom user-recorded campus/building routes ("Scan & Save").
class UserRouteStorage {
  static const String _fileName = 'user_recorded_routes.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Load custom nodes and edges recorded on this device.
  static Future<Map<String, dynamic>> loadCustomGraph() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        return {'nodes': <MapNode>[], 'edges': <MapEdge>[]};
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

  /// Save a newly recorded route connecting [startName] to [destName] with intermediate [legs].
  /// Automatically creates forward and reverse graph edges with inverted headings.
  static Future<Map<String, dynamic>> saveRoute({
    required String startName,
    required String destName,
    required List<RecordedLeg> legs,
  }) async {
    final cleanStart = startName.trim();
    final cleanDest = destName.trim();
    final startId = _slug(cleanStart);
    final destId = _slug(cleanDest);

    final newNodes = <MapNode>[];
    final newEdges = <MapEdge>[];

    // 1. Origin Node
    final startNode = MapNode(
      id: startId,
      name: cleanStart,
      floor: 0,
      expectedSigns: [cleanStart.toLowerCase()],
      hazards: [],
      description: 'Custom recorded room: $cleanStart',
    );
    newNodes.add(startNode);

    // 2. Intermediate Waypoint Nodes & Edges
    String prevNodeId = startId;

    for (int i = 0; i < legs.length; i++) {
      final leg = legs[i];
      final isLast = i == legs.length - 1;
      final currentNodeId = isLast
          ? destId
          : '${startId}_${destId}_wp${i + 1}';

      if (!isLast) {
        final wpNode = MapNode(
          id: currentNodeId,
          name: '${leg.label} ${i + 1}',
          floor: 0,
          expectedSigns: [leg.label.toLowerCase()],
          hazards: [],
          description: 'Corridor turn between $cleanStart and $cleanDest',
        );
        newNodes.add(wpNode);
      }

      // Forward Edge
      newEdges.add(MapEdge(
        from: prevNodeId,
        to: currentNodeId,
        steps: leg.steps,
        heading: leg.heading,
      ));

      // Reverse Edge (opposite heading: (heading + 180) % 360)
      final reverseHeading = (leg.heading + 180.0) % 360.0;
      newEdges.add(MapEdge(
        from: currentNodeId,
        to: prevNodeId,
        steps: leg.steps,
        heading: reverseHeading,
      ));

      prevNodeId = currentNodeId;
    }

    // 3. Destination Node
    final destNode = MapNode(
      id: destId,
      name: cleanDest,
      floor: 0,
      expectedSigns: [cleanDest.toLowerCase()],
      hazards: [],
      description: 'Custom recorded room: $cleanDest',
    );
    newNodes.add(destNode);

    // 4. Merge with existing saved graph and persist to disk
    try {
      final existing = await loadCustomGraph();
      final existingNodes = existing['nodes'] as List<MapNode>;
      final existingEdges = existing['edges'] as List<MapEdge>;

      final allNodes = <String, MapNode>{};
      for (final n in existingNodes) {
        allNodes[n.id] = n;
      }
      for (final n in newNodes) {
        allNodes[n.id] = n;
      }

      final allEdges = List<MapEdge>.from(existingEdges);
      for (final e in newEdges) {
        allEdges.removeWhere((ex) => ex.from == e.from && ex.to == e.to);
        allEdges.add(e);
      }

      final file = await _getFile();
      final data = {
        'nodes': allNodes.values.map((n) => {
              'id': n.id,
              'name': n.name,
              'floor': n.floor,
              'expected_signs': n.expectedSigns,
              'hazards': n.hazards,
              'description': n.description,
            }).toList(),
        'edges': allEdges.map((e) => {
              'from': e.from,
              'to': e.to,
              'steps': e.steps,
              'heading': e.heading,
            }).toList(),
      };

      await file.writeAsString(jsonEncode(data));
    } catch (_) {}

    return {'nodes': newNodes, 'edges': newEdges};
  }

  static String _slug(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
