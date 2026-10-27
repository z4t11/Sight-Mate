import '../utils/dijkstra.dart';
import '../utils/compass_helper.dart';
import 'map_loader.dart';
import 'positioning_service.dart';
import 'app_config.dart';
import 'gps_service.dart';

enum NavStepStatus {
  walking,
  approaching,
  turnNow,
  arrived,
}

/// Real-time live navigation update broadcasted as steps are taken.
class NavigationStepUpdate {
  final NavStepStatus status;
  final String message;
  final int stepsRemaining;
  final bool shouldSpeak;

  const NavigationStepUpdate({
    required this.status,
    required this.message,
    required this.stepsRemaining,
    this.shouldSpeak = true,
  });
}

/// Orchestrates live indoor and campus turn-by-turn navigation with real-time pedometer tracking.
class NavigationService {
  final MapLoader map;
  final PositioningService positioning;
  final GpsService? gps;

  int _currentSegmentTargetSteps = 0;
  int _currentSegmentStepsTaken = 0;
  bool _approachingSpoken = false;

  int get currentSegmentTargetSteps => _currentSegmentTargetSteps;
  int get currentSegmentStepsTaken => _currentSegmentStepsTaken;
  int get currentSegmentStepsRemaining =>
      (_currentSegmentTargetSteps - _currentSegmentStepsTaken).clamp(0, 999);

  NavigationService({
    required this.map,
    required this.positioning,
    this.gps,
  });

  /// Plan a route from current position (or [startNodeId]) to [destination] name.
  /// Returns the initial spoken instruction.
  String startNavigation(String destination, {String? startNodeId}) {
    if (startNodeId != null) {
      positioning.confirmLocation(startNodeId);
    }

    final currentId = positioning.state.currentNodeId;
    if (currentId == null) {
      return "I need to know where you are first. "
          "Try saying 'I am at Staff Room' or 'I am at Entrance'.";
    }

    final goalNode = map.findByName(destination);
    if (goalNode == null) {
      return "I couldn't find '$destination' on the building map. "
          "Could you try a different room name?";
    }

    if (currentId == goalNode.id) {
      return "You are already at ${goalNode.name}!";
    }

    final path = Dijkstra.shortestPath(
      startId: currentId,
      goalId: goalNode.id,
      nodes: map.nodes,
      edges: map.edges,
    );

    if (path.isEmpty) {
      return "I can't find a connected route from here to ${goalNode.name}. "
          "The building map might not have that connection yet.";
    }

    positioning.updateState(positioning.state.copyWith(
      route: path,
      routeIndex: 0,
      isNavigating: true,
      activeDestination: goalNode.name,
    ));

    // Setup first segment tracking
    _currentSegmentStepsTaken = 0;
    _approachingSpoken = false;
    if (path.length >= 2) {
      final firstEdge = map.getEdge(path[0], path[1]);
      _currentSegmentTargetSteps = firstEdge?.steps ?? 10;
    } else {
      _currentSegmentTargetSteps = 10;
    }

    return _initialInstruction(goalNode.name);
  }

  /// Live step tracking: called on every physical step detected by the pedometer.
  NavigationStepUpdate? onStep(int delta) {
    final state = positioning.state;
    if (!state.isNavigating || !state.hasRoute) return null;

    _currentSegmentStepsTaken += delta;
    final remaining = _currentSegmentTargetSteps - _currentSegmentStepsTaken;

    // 1. Approaching notification (e.g. 2 steps before the turn)
    if (remaining <= 2 && remaining > 0 && _currentSegmentTargetSteps >= 5 && !_approachingSpoken) {
      _approachingSpoken = true;
      final nextIdx = state.routeIndex + 1;
      if (nextIdx < state.route.length - 1) {
        final curEdge = map.getEdge(state.route[state.routeIndex], state.route[nextIdx]);
        final nxtEdge = map.getEdge(state.route[nextIdx], state.route[nextIdx + 1]);
        final turn = (curEdge != null && nxtEdge != null)
            ? CompassHelper.turnInstruction(curEdge.heading, nxtEdge.heading)
            : 'turn';
        return NavigationStepUpdate(
          status: NavStepStatus.approaching,
          message: "In 2 steps, prepare to $turn.",
          stepsRemaining: remaining,
          shouldSpeak: true,
        );
      } else {
        final destNode = map.nodes[state.route.last];
        return NavigationStepUpdate(
          status: NavStepStatus.approaching,
          message: "Approaching ${destNode?.name ?? 'destination'} in 2 steps.",
          stepsRemaining: remaining,
          shouldSpeak: true,
        );
      }
    }

    // 2. Turn or Arrival reached!
    if (_currentSegmentStepsTaken >= _currentSegmentTargetSteps) {
      _approachingSpoken = false;
      final nextIdx = state.routeIndex + 1;

      // Final destination reached!
      if (nextIdx >= state.route.length - 1) {
        final destId = state.route.last;
        final destNode = map.nodes[destId];
        final name = destNode?.name ?? 'your destination';

        positioning.updateState(state.copyWith(
          currentNodeId: destId,
          isNavigating: false,
          clearRoute: true,
        ));
        _currentSegmentStepsTaken = 0;
        _currentSegmentTargetSteps = 0;

        return NavigationStepUpdate(
          status: NavStepStatus.arrived,
          message: "You have arrived at $name. Navigation complete.",
          stepsRemaining: 0,
          shouldSpeak: true,
        );
      }

      // Transition to next segment along route
      final prevFromId = state.route[state.routeIndex];
      final prevToId = state.route[nextIdx];
      final prevEdge = map.getEdge(prevFromId, prevToId);

      positioning.updateState(state.copyWith(
        routeIndex: nextIdx,
        currentNodeId: prevToId,
      ));

      final newFromId = state.route[nextIdx];
      final newToId = state.route[nextIdx + 1];
      final nextEdge = map.getEdge(newFromId, newToId);
      final nextNode = map.nodes[newToId];

      _currentSegmentStepsTaken = 0;
      _currentSegmentTargetSteps = nextEdge?.steps ?? 10;

      if (nextEdge == null || nextNode == null) {
        return const NavigationStepUpdate(
          status: NavStepStatus.arrived,
          message: "Route complete.",
          stepsRemaining: 0,
          shouldSpeak: true,
        );
      }

      final turn = prevEdge != null
          ? CompassHelper.turnInstruction(prevEdge.heading, nextEdge.heading)
          : CompassHelper.relativeDirection(positioning.state.headingDegrees, nextEdge.heading);

      String hazard = '';
      if (nextNode.hazards.isNotEmpty) {
        hazard = ' Watch out for ${nextNode.hazards.first}.';
      }

      final msg = "$turn now. Walk ${nextEdge.steps} steps forward towards ${nextNode.name}.$hazard";
      return NavigationStepUpdate(
        status: NavStepStatus.turnNow,
        message: msg,
        stepsRemaining: nextEdge.steps,
        shouldSpeak: true,
      );
    }

    return NavigationStepUpdate(
      status: NavStepStatus.walking,
      message: "$remaining steps remaining.",
      stepsRemaining: remaining.clamp(0, 999),
      shouldSpeak: false,
    );
  }

  /// Initial spoken instruction at the start of navigation.
  String _initialInstruction(String destName) {
    final state = positioning.state;
    if (!state.hasRoute || state.route.length < 2) return "Route planned to $destName.";

    final fromId = state.route[0];
    final toId = state.route[1];
    final edge = map.getEdge(fromId, toId);
    final toNode = map.nodes[toId];

    if (edge == null || toNode == null) {
      return "Starting route to $destName.";
    }

    final direction = CompassHelper.relativeDirection(
      state.headingDegrees,
      edge.heading,
    );

    String hazard = '';
    if (toNode.hazards.isNotEmpty) {
      hazard = ' Careful: ${toNode.hazards.first}.';
    }

    return "Starting route to $destName. Head $direction towards ${toNode.name}, about ${edge.steps} steps.$hazard";
  }

  /// Advance to next route segment manually (e.g. user confirmed landmark via camera or tap).
  String advanceRoute() {
    final state = positioning.state;
    if (!state.hasRoute) return "No route active.";

    final newIdx = state.routeIndex + 1;
    if (newIdx >= state.route.length - 1) {
      return _arrivalMessage();
    }

    final prevFromId = state.route[state.routeIndex];
    final prevToId = state.route[newIdx];
    final prevEdge = map.getEdge(prevFromId, prevToId);

    positioning.updateState(state.copyWith(
      routeIndex: newIdx,
      currentNodeId: prevToId,
    ));

    final newFromId = state.route[newIdx];
    final newToId = state.route[newIdx + 1];
    final nextEdge = map.getEdge(newFromId, newToId);
    final nextNode = map.nodes[newToId];

    _currentSegmentStepsTaken = 0;
    _currentSegmentTargetSteps = nextEdge?.steps ?? 10;
    _approachingSpoken = false;

    if (nextEdge == null || nextNode == null) {
      return _arrivalMessage();
    }

    final turn = prevEdge != null
        ? CompassHelper.turnInstruction(prevEdge.heading, nextEdge.heading)
        : 'Continue';

    return "$turn now. Walk ${nextEdge.steps} steps forward towards ${nextNode.name}.";
  }

  /// Stop navigation.
  void cancelNavigation() {
    _currentSegmentStepsTaken = 0;
    _currentSegmentTargetSteps = 0;
    _approachingSpoken = false;
    positioning.updateState(positioning.state.copyWith(
      clearRoute: true,
      routeIndex: 0,
      isNavigating: false,
    ));
  }

  /// Total estimated steps remaining across the entire active route.
  int? getRemainingSteps() {
    final state = positioning.state;
    if (!state.hasRoute) return null;
    int total = currentSegmentStepsRemaining;
    for (int i = state.routeIndex + 1; i < state.route.length - 1; i++) {
      final edge = map.getEdge(state.route[i], state.route[i + 1]);
      if (edge != null) total += edge.steps;
    }
    return total;
  }

  String _arrivalMessage() {
    final state = positioning.state;
    final destId = state.route.isNotEmpty ? state.route.last : null;
    final destNode = destId != null ? map.nodes[destId] : null;
    final name = destNode?.name ?? 'your destination';

    _currentSegmentStepsTaken = 0;
    _currentSegmentTargetSteps = 0;
    positioning.updateState(state.copyWith(
      isNavigating: false,
      clearRoute: true,
    ));
    return "You have arrived at $name. Navigation complete.";
  }

  /// Handle "take me to ___", "navigate from staff room to lab", etc.
  String handleNavigateCommand(String query) {
    if (AppConfig.isMockMode) {
      return _mockNavigation(query);
    }

    // Check if query is formatted as "from [origin] to [destination]"
    final fromToPattern = RegExp(r'(?:from\s+)?(.+?)\s+to\s+(.+)', caseSensitive: false);
    final match = fromToPattern.firstMatch(query.trim());

    if (match != null) {
      final originStr = match.group(1)?.trim() ?? '';
      final destStr = match.group(2)?.trim() ?? '';

      final startNode = map.findByName(originStr);
      if (startNode != null) {
        positioning.confirmLocation(startNode.id);
        return startNavigation(destStr);
      }
    }

    // Default start node if user location unknown:
    // If destination mentions "lab" or "software" or "class", default start to staff room!
    if (positioning.state.currentNodeId == null) {
      final qLower = query.toLowerCase();
      if (qLower.contains('lab') || qLower.contains('class') || qLower.contains('software')) {
        final staff = map.findByName('staff room');
        if (staff != null) {
          positioning.confirmLocation(staff.id);
        }
      }
    }

    return startNavigation(query);
  }

  String _mockNavigation(String destination) {
    final entrance = map.findByName('entrance') ?? map.findByName('main entrance');
    if (entrance != null && positioning.state.currentNodeId == null) {
      positioning.confirmLocation(entrance.id);
    }
    return startNavigation(destination);
  }
}
