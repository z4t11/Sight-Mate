import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/map_node.dart';
import '../models/map_edge.dart';
import 'user_route_storage.dart';

/// Loads the campus map JSON from assets/maps/ and merges user-recorded routes.
class MapLoader {
  Map<String, MapNode> _nodes = {};
  List<MapEdge> _edges = [];

  Map<String, MapNode> get nodes => _nodes;
  List<MapEdge> get edges => _edges;

  /// Load and parse the base JSON graph and any custom user recorded routes.
  Future<void> load([String path = 'assets/maps/campus_map.json']) async {
    _nodes = {};
    _edges = [];

    // 1. Base assets map
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
    } catch (_) {}

    // 2. Custom user-recorded routes from local storage
    try {
      final custom = await UserRouteStorage.loadCustomGraph();
      final customNodes = custom['nodes'] as List<MapNode>;
      final customEdges = custom['edges'] as List<MapEdge>;

      for (final n in customNodes) {
        _nodes[n.id] = n;
      }
      for (final e in customEdges) {
        _edges.removeWhere((ex) => ex.from == e.from && ex.to == e.to);
        _edges.add(e);
      }
    } catch (_) {}
  }

  /// Inject newly recorded custom nodes and edges directly in memory.
  void addCustomGraph(List<MapNode> newNodes, List<MapEdge> newEdges) {
    for (final n in newNodes) {
      _nodes[n.id] = n;
    }
    for (final e in newEdges) {
      _edges.removeWhere((ex) => ex.from == e.from && ex.to == e.to);
      _edges.add(e);
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

    // Expected signs match
    for (final node in _nodes.values) {
      for (final s in node.expectedSigns) {
        if (s.toLowerCase() == q || q.contains(s.toLowerCase())) {
          return node;
        }
      }
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
