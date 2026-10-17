import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/map_node.dart';
import '../models/map_edge.dart';

/// Loads the campus map JSON from assets/maps/.
class MapLoader {
  Map<String, MapNode> _nodes = {};
  List<MapEdge> _edges = [];

  Map<String, MapNode> get nodes => _nodes;
  List<MapEdge> get edges => _edges;

  /// Load and parse the JSON graph. Call once at startup.
  Future<void> load([String path = 'assets/maps/campus_map.json']) async {
    try {
      final raw = await rootBundle.loadString(path);
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final nodeList = json['nodes'] as List? ?? [];
      for (final n in nodeList) {
        final node = MapNode.fromJson(n as Map<String, dynamic>);
        _nodes[node.id] = node;
      }

      final edgeList = json['edges'] as List? ?? [];
      for (final e in edgeList) {
        _edges.add(MapEdge.fromJson(e as Map<String, dynamic>));
      }
    } catch (_) {
      // Graceful: no map data loaded — navigation disabled
      _nodes = {};
      _edges = [];
    }
  }

  /// Find a node by fuzzy name match (case-insensitive, contains).
  /// Returns null if not found.
  MapNode? findByName(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return null;

    // Exact match first
    for (final node in _nodes.values) {
      if (node.name.toLowerCase() == q) return node;
    }
    // Partial match
    for (final node in _nodes.values) {
      if (node.name.toLowerCase().contains(q) ||
          q.contains(node.name.toLowerCase())) {
        return node;
      }
    }
    return null;
  }

  /// Get an edge between two node IDs (or null).
  MapEdge? getEdge(String from, String to) {
    for (final e in _edges) {
      if (e.from == from && e.to == to) return e;
    }
    return null;
  }

  bool get isEmpty => _nodes.isEmpty;
}
