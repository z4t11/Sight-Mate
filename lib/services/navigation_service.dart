import '../utils/dijkstra.dart';
import '../utils/compass_helper.dart';
import 'map_loader.dart';
import 'positioning_service.dart';
import 'app_config.dart';

import 'gps_service.dart';

/// Orchestrates navigation: route planning, spoken instructions, re-routing.
class NavigationService {
  final MapLoader map;
  final PositioningService positioning;
  final GpsService? gps;

  NavigationService({
    required this.map,
    required this.positioning,
    this.gps,
  });

  /// Plan a route from current position to [destination] name.
  /// Returns a spoken instruction or error.
  String startNavigation(String destination) {
    final currentId = positioning.state.currentNodeId;
    if (currentId == null) {
      return "I need to know where you are first. "
          "Try pointing your camera at a sign, or tell me where you are.";
    }

    final goalNode = map.findByName(destination);
    if (goalNode == null) {
      return "I couldn't find '$destination' on my map. "
          "Could you try a different name?";
    }

    if (currentId == goalNode.id) {
      return "I think you're already at ${goalNode.name}!";
    }

    final path = Dijkstra.shortestPath(
      startId: currentId,
      goalId: goalNode.id,
      nodes: map.nodes,
      edges: map.edges,
    );

    if (path.isEmpty) {
      return "I can't find a route from here to ${goalNode.name}. "
          "The map might not have that connection yet.";
    }

    positioning.updateState(positioning.state.copyWith(
      route: path,
      routeIndex: 0,
      isNavigating: true,
      activeDestination: goalNode.name,
    ));

    return _nextInstruction();
  }

  /// Get the current spoken navigation instruction.
  String _nextInstruction() {
    final state = positioning.state;
    if (!state.hasRoute) return "No route active.";
    if (state.isAtDestination) return _arrivalMessage();

    final fromIdx = state.routeIndex;
    final toIdx = fromIdx + 1;
    if (toIdx >= state.route.length) return _arrivalMessage();

    final fromId = state.route[fromIdx];
    final toId = state.route[toIdx];
    final edge = map.getEdge(fromId, toId);
    final toNode = map.nodes[toId];

    if (edge == null || toNode == null) {
      return "I've lost the route. Let me try to reposition.";
    }

    // Direction relative to user
    final direction = CompassHelper.relativeDirection(
      state.headingDegrees,
      edge.heading,
    );

    // Hazards at destination node
    String hazardWarning = '';
    if (toNode.hazards.isNotEmpty) {
      hazardWarning = ' Careful: ${toNode.hazards.first}.';
    }

    return "Head $direction towards ${toNode.name}, "
        "about ${edge.steps} steps.$hazardWarning";
  }

  /// Advance to next route segment. Call when the user has reached the next node.
  String advanceRoute() {
    final state = positioning.state;
    if (!state.hasRoute) return "No route active.";

    final newIdx = state.routeIndex + 1;
    if (newIdx >= state.route.length) {
      return _arrivalMessage();
    }

    positioning.updateState(state.copyWith(routeIndex: newIdx));
    return _nextInstruction();
  }

  /// Check if user has drifted off-route and re-route if needed.
  String? checkAndReroute() {
    final state = positioning.state;
    if (!state.isNavigating || !state.hasRoute) return null;

    final currentNodeId = state.currentNodeId;
    if (currentNodeId == null) return null;

    // If current node is on the planned route, advance to it
    final idx = state.route.indexOf(currentNodeId);
    if (idx >= 0 && idx > state.routeIndex) {
      positioning.updateState(state.copyWith(routeIndex: idx));
      if (idx >= state.route.length - 1) return _arrivalMessage();
      return _nextInstruction();
    }

    // Off-route: re-plan from current position
    if (idx < 0 && state.route.isNotEmpty) {
      final goalId = state.route.last;
      final goalNode = map.nodes[goalId];
      if (goalNode != null) {
        final newPath = Dijkstra.shortestPath(
          startId: currentNodeId,
          goalId: goalId,
          nodes: map.nodes,
          edges: map.edges,
        );
        if (newPath.isNotEmpty) {
          positioning.updateState(state.copyWith(
            route: newPath,
            routeIndex: 0,
          ));
          return "You seem to have gone off route. "
              "Let me recalculate. ${_nextInstruction()}";
        }
      }
    }

    return null;
  }

  /// Stop navigation.
  void cancelNavigation() {
    positioning.updateState(positioning.state.copyWith(
      clearRoute: true,
      routeIndex: 0,
      isNavigating: false,
    ));
  }

  /// Total estimated steps remaining in the current active route.
  int? getRemainingSteps() {
    final state = positioning.state;
    if (!state.hasRoute) return null;
    int total = 0;
    for (int i = state.routeIndex; i < state.route.length - 1; i++) {
      final edge = map.getEdge(state.route[i], state.route[i + 1]);
      if (edge != null) total += edge.steps;
    }
    return total;
  }

  String getNextInstruction() => _nextInstruction();

  String _arrivalMessage() {
    final state = positioning.state;
    final destId = state.route.isNotEmpty ? state.route.last : null;
    final destNode = destId != null ? map.nodes[destId] : null;
    final name = destNode?.name ?? 'your destination';

    positioning.updateState(state.copyWith(isNavigating: false));
    return "I think you've arrived at $name.";
  }

  /// Handle "take me to ___" — combines mock and real.
  String handleNavigateCommand(String destination) {
    if (AppConfig.isMockMode) {
      return _mockNavigation(destination);
    }
    return startNavigation(destination);
  }

  String _mockNavigation(String destination) {
    // Simulate positioning at entrance
    final entrance = map.findByName('main entrance') ?? map.findByName('entrance');
    if (entrance != null) {
      positioning.confirmLocation(entrance.id);
    }

    // Try real route on the loaded sample map
    final result = startNavigation(destination);
    return result;
  }
}
