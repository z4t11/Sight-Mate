import '../models/map_node.dart';
import '../models/map_edge.dart';

/// Dijkstra shortest-path over the campus graph.
/// Cost metric: number of steps (edges).
class Dijkstra {
  /// Returns an ordered list of node IDs from [startId] to [goalId],
  /// or an empty list if no path exists.
  static List<String> shortestPath({
    required String startId,
    required String goalId,
    required Map<String, MapNode> nodes,
    required List<MapEdge> edges,
  }) {
    if (startId == goalId) return [startId];

    // Build adjacency list
    final adj = <String, List<MapEdge>>{};
    for (final node in nodes.keys) {
      adj[node] = [];
    }
    for (final edge in edges) {
      adj[edge.from]?.add(edge);
    }

    // Simple list-based priority queue (fine for small campus graphs)
    final dist = <String, int>{};
    final prev = <String, String?>{};
    final visited = <String>{};

    for (final id in nodes.keys) {
      dist[id] = 999999;
      prev[id] = null;
    }
    dist[startId] = 0;

    while (true) {
      // Find unvisited node with smallest distance
      String? u;
      int minDist = 999999;
      for (final id in nodes.keys) {
        if (!visited.contains(id) && (dist[id] ?? 999999) < minDist) {
          minDist = dist[id] ?? 999999;
          u = id;
        }
      }

      if (u == null || u == goalId) break;
      visited.add(u);

      for (final edge in adj[u] ?? []) {
        final int newCost = ((dist[u] ?? 999999) + edge.steps).toInt();
        if (newCost < (dist[edge.to] ?? 999999)) {
          dist[edge.to] = newCost;
          prev[edge.to] = u;
        }
      }
    }

    // Reconstruct path
    if (prev[goalId] == null && goalId != startId) return [];
    final path = <String>[];
    String? current = goalId;
    while (current != null) {
      path.insert(0, current);
      current = prev[current];
    }
    return path;
  }
}
