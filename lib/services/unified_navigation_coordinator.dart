import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'gps_service.dart';
import 'audio_priority_manager.dart';
import 'outdoor_routing_service.dart';
import 'outdoor_safety_guardian.dart';
import 'live_vision_session.dart';
import 'persistent_object_search_service.dart';
import 'map_loader.dart';
import 'positioning_service.dart';
import 'user_route_storage.dart';

/// Navigation mode currently active in the Unified Coordinator.
enum ActiveNavigationMode {
  none,
  nearbyObjectSearch,
  indoorSavedRoute,
  indoorGuidingToExit,
  outdoorGps,
  exploratoryLiveVision,
}

/// Category of destination resolved from user query.
enum DestinationCategory {
  nearbyObject,
  indoorSavedRoute,
  outdoorPlace,
  ambiguous,
}

/// Unified Navigation Coordinator.
/// Coordinates live vision object search, indoor building navigation,
/// outdoor Google Maps / GPS pedestrian routing, and intelligent indoor <-> outdoor transitions.
class UnifiedNavigationCoordinator {
  final GpsService _gps;
  final AudioPriorityManager _audio;
  final OutdoorRoutingService _outdoorRouter;
  final OutdoorSafetyGuardian _outdoorGuardian;
  final LiveVisionSession _liveVision;
  final PersistentObjectSearchService _objectSearch;
  final MapLoader _map;
  final PositioningService _positioning;

  GpsService get gps => _gps;
  ActiveNavigationMode _mode = ActiveNavigationMode.none;
  StreamSubscription<Position>? _gpsSub;

  String? _pendingOutdoorDestination;
  String? _pendingClarificationDestination;

  ActiveNavigationMode get mode => _mode;
  bool get isNavigating => _mode != ActiveNavigationMode.none;
  bool get isWaitingForClarification => _pendingClarificationDestination != null;
  String? get pendingClarificationDestination => _pendingClarificationDestination;
  OutdoorRoutingService get outdoorRouter => _outdoorRouter;

  UnifiedNavigationCoordinator({
    required GpsService gps,
    required AudioPriorityManager audio,
    required OutdoorRoutingService outdoorRouter,
    required OutdoorSafetyGuardian outdoorGuardian,
    required LiveVisionSession liveVision,
    required PersistentObjectSearchService objectSearch,
    required MapLoader map,
    required PositioningService positioning,
  })  : _gps = gps,
        _audio = audio,
        _outdoorRouter = outdoorRouter,
        _outdoorGuardian = outdoorGuardian,
        _liveVision = liveVision,
        _objectSearch = objectSearch,
        _map = map,
        _positioning = positioning;

  // ── Keywords for Intent Resolution ──────────────────────────────────────────

  static const List<String> _nearbyObjectKeywords = [
    'door', 'front door', 'exit door', 'exit', 'entrance',
    'chair', 'armchair', 'bench', 'seat',
    'table', 'desk', 'counter',
    'water bottle', 'bottle', 'cup', 'glass',
    'bathroom', 'restroom', 'washroom', 'toilet', 'lavatory',
    'stairs', 'staircase', 'steps', 'elevator', 'lift',
    'dustbin', 'trash can', 'bin',
    'switchboard', 'switch', 'socket',
    'board', 'blackboard', 'whiteboard',
    'fan', 'air conditioner', 'ac',
    'bed', 'sofa', 'couch',
  ];

  static const List<String> _indoorCategoryKeywords = [
    'room', 'classroom', 'class', 'lab', 'laboratory', 'office', 'cabin',
    'seminar hall', 'auditorium', 'library', 'canteen', 'cafeteria',
    'hod office', 'staff room', 'dean office', 'reception', 'lobby',
    'restroom corridor', 'stairwell', 'lift lobby',
  ];

  static const List<String> _outdoorKeywords = [
    'bus stop', 'bus stand', 'bus station', 'metro station', 'train station',
    'railway station', 'station', 'hospital', 'clinic', 'pharmacy', 'medical store',
    'supermarket', 'grocery', 'bakery', 'mall', 'shopping center',
    'park', 'bank', 'atm', 'temple', 'church', 'mosque',
    'stadium', 'ground', 'playground', 'gate', 'main gate', 'exit gate',
    'street', 'road', 'avenue', 'boulevard', 'lane', 'circle', 'junction',
    'building b', 'campus ground', 'hostel', 'canteen outdoor',
  ];

  /// Categorize the destination query into nearby object, indoor route, outdoor place, or ambiguous.
  Future<DestinationCategory> categorizeDestination(String destination, {String origin = 'Staff Room'}) async {
    final clean = destination.toLowerCase().trim();

    // 1. Check if a node exists in MapLoader
    final mapNode = _map.findByName(clean);
    if (mapNode != null) {
      return DestinationCategory.indoorSavedRoute;
    }

    // 2. Check if a saved user route exists
    final savedRoute = await UserRouteStorage.findRoute(
      startName: origin,
      destinationName: clean,
    );
    if (savedRoute != null) {
      return DestinationCategory.indoorSavedRoute;
    }

    // 3. Check for nearby physical objects (door, chair, bottle, bathroom, stairs, etc.)
    for (final obj in _nearbyObjectKeywords) {
      if (clean == obj || clean.startsWith('$obj ') || clean.endsWith(' $obj') || clean.contains(' $obj ')) {
        return DestinationCategory.nearbyObject;
      }
    }

    // 4. Check for explicit indoor keywords (classroom, lab, room 101, etc.)
    final roomPattern = RegExp(r'\b(?:room|class(?:room)?|lab)\s*\d+\b', caseSensitive: false);
    if (roomPattern.hasMatch(clean)) {
      return DestinationCategory.indoorSavedRoute;
    }
    for (final ind in _indoorCategoryKeywords) {
      if (clean.contains(ind)) {
        return DestinationCategory.indoorSavedRoute;
      }
    }

    // 5. Check for explicit outdoor keywords (bus stop, hospital, street addresses)
    for (final out in _outdoorKeywords) {
      if (clean.contains(out)) {
        return DestinationCategory.outdoorPlace;
      }
    }

    // Street suffixes / numbers
    final addressPattern = RegExp(r'\b(?:street|st|road|rd|ave|avenue|dr|drive|lane|way|highway|hwy)\b', caseSensitive: false);
    if (addressPattern.hasMatch(clean)) {
      return DestinationCategory.outdoorPlace;
    }

    // Ambiguous
    return DestinationCategory.ambiguous;
  }

  /// True if current device state indicates the user is indoors.
  bool get isUserIndoors {
    if (_positioning.state.customLocationName != null) return true;
    if (_mode == ActiveNavigationMode.indoorSavedRoute ||
        _mode == ActiveNavigationMode.indoorGuidingToExit) {
      return true;
    }
    final pos = _gps.currentPosition;
    if (pos == null) return true;
    if (pos.accuracy > 30.0 && _mode != ActiveNavigationMode.outdoorGps) {
      return true;
    }
    return false;
  }

  /// Start a unified navigation journey.
  Future<String> startNavigation(
    String destination, {
    String origin = 'Staff Room',
    bool? forceIndoor,
    bool? forceOutdoor,
  }) async {
    final cleanDest = destination.trim();
    if (cleanDest.isEmpty) return "Please specify a destination.";

    _pendingClarificationDestination = null;

    // ── 1. Forcing overrides (e.g. from clarification answer) ───────
    if (forceIndoor == true) {
      return await _startIndoorDestination(cleanDest, origin: origin);
    }
    if (forceOutdoor == true) {
      return await _startOutdoorDestination(cleanDest, origin: origin);
    }

    // ── 2. Automatic Intent Categorization ──────────────────────────
    final category = await categorizeDestination(cleanDest, origin: origin);

    switch (category) {
      case DestinationCategory.nearbyObject:
        return await _startNearbyObjectSearch(cleanDest);

      case DestinationCategory.indoorSavedRoute:
        return await _startIndoorDestination(cleanDest, origin: origin);

      case DestinationCategory.outdoorPlace:
        return await _startOutdoorDestination(cleanDest, origin: origin);

      case DestinationCategory.ambiguous:
        return await _askClarification(cleanDest);
    }
  }

  // ── Mode Handlers ─────────────────────────────────────────────────

  /// Case 1: Nearby physical object (door, chair, bathroom, stairs, water bottle).
  /// Uses live camera vision and persistent 360° search. NEVER sends to map search!
  Future<String> _startNearbyObjectSearch(String objectName) async {
    stopAllNavigation();
    _mode = ActiveNavigationMode.nearbyObjectSearch;

    await _objectSearch.startSearch(objectName);
    return "Looking for $objectName with the camera.";
  }

  /// Case 2: Indoor Saved Route or Building Map Destination.
  Future<String> _startIndoorDestination(String destination, {String origin = 'Staff Room'}) async {
    stopAllNavigation();

    // 1. Check for recorded indoor route
    final savedRoute = await UserRouteStorage.findRoute(
      startName: origin,
      destinationName: destination,
    );

    if (savedRoute != null) {
      _mode = ActiveNavigationMode.indoorSavedRoute;
      final firstInstruction = savedRoute.segments.isNotEmpty
          ? savedRoute.segments.first.movementInstruction
          : "Walk straight forward along the route.";
      final msg = "Starting route to ${savedRoute.destinationLocationName}. $firstInstruction";
      await _audio.speak(text: msg, priority: AudioPriority.navigationInstruction);
      return msg;
    }

    // 2. Check MapLoader node fallback
    final mapNode = _map.findByName(destination);
    if (mapNode != null) {
      final msg = "Found ${mapNode.name} on the building map. Head down the corridor and look for ${mapNode.expectedSigns.isNotEmpty ? mapNode.expectedSigns.first : mapNode.name}.";
      _mode = ActiveNavigationMode.indoorSavedRoute;
      await _audio.speak(text: msg, priority: AudioPriority.navigationInstruction);
      return msg;
    }

    _mode = ActiveNavigationMode.none;
    final noRouteMsg = "I don't have a saved indoor route to $destination yet. You can map this route using the Map Route button.";
    await _audio.speak(text: noRouteMsg, priority: AudioPriority.conversationalResponse);
    return noRouteMsg;
  }

  /// Case 3: Outdoor destination (bus stop, hospital, street address).
  /// Uses Google Maps Platform Directions API.
  /// If user is indoors, guides to the building exit first, then engages outdoor Google Maps routing.
  Future<String> _startOutdoorDestination(String destination, {String origin = 'Staff Room'}) async {
    stopAllNavigation();

    if (isUserIndoors) {
      _mode = ActiveNavigationMode.indoorGuidingToExit;
      _pendingOutdoorDestination = destination;
      _startGpsExitMonitor();

      final msg = "Guiding you to the building exit first. Looking for the exit door. Once outside, I will guide you to $destination with Google Maps.";
      await _audio.speak(text: msg, priority: AudioPriority.navigationInstruction);
      await _objectSearch.startSearch("exit door");
      return msg;
    }

    return await _startOutdoorGpsRouting(destination);
  }

  /// Start actual outdoor Google Maps / GPS routing.
  Future<String> _startOutdoorGpsRouting(String destination) async {
    stopAllNavigation();
    _mode = ActiveNavigationMode.outdoorGps;

    final routeResult = await _outdoorRouter.planRoute(destination);
    if (routeResult == null) {
      _mode = ActiveNavigationMode.none;
      final failMsg = "Unable to find a walking route to $destination on Google Maps. Please check the address or internet connection.";
      await _audio.speak(text: failMsg, priority: AudioPriority.navigationInstruction);
      return failMsg;
    }

    await _audio.speak(text: routeResult, priority: AudioPriority.navigationInstruction);
    _outdoorGuardian.start();

    _gpsSub?.cancel();
    _gpsSub = _gps.onPositionChanged.listen((pos) {
      if (_mode == ActiveNavigationMode.outdoorGps) {
        final stepPrompt = _outdoorRouter.onPositionUpdate(pos);
        if (stepPrompt != null) {
          _audio.speak(text: stepPrompt, priority: AudioPriority.navigationInstruction);
        }
      }
    });

    return routeResult;
  }

  /// Case 4: Ambiguous destination -> Ask clarifying question.
  Future<String> _askClarification(String destination) async {
    _pendingClarificationDestination = destination;
    final question = "Is $destination inside this building, or an outdoor place?";
    await _audio.speak(text: question, priority: AudioPriority.conversationalResponse);
    return question;
  }

  /// Answer the clarification query.
  Future<String?> resolveClarification(String answer) async {
    final dest = _pendingClarificationDestination;
    if (dest == null) return null;

    final a = answer.toLowerCase().trim();
    if (a.contains('indoor') || a.contains('inside') || a.contains('here') || a.contains('building')) {
      _pendingClarificationDestination = null;
      return await startNavigation(dest, forceIndoor: true);
    }
    if (a.contains('outdoor') || a.contains('outside') || a.contains('map') || a.contains('street') || a.contains('place')) {
      _pendingClarificationDestination = null;
      return await startNavigation(dest, forceOutdoor: true);
    }

    final repeatQuestion = "Please tell me: is $dest inside this building or outside?";
    await _audio.speak(text: repeatQuestion, priority: AudioPriority.conversationalResponse);
    return repeatQuestion;
  }

  /// Alias for clarification handling
  Future<String?> handleClarification(String answer) => resolveClarification(answer);

  void _startGpsExitMonitor() {
    _gpsSub?.cancel();
    _gpsSub = _gps.onPositionChanged.listen((pos) {
      if (_mode == ActiveNavigationMode.indoorGuidingToExit && _pendingOutdoorDestination != null) {
        if (pos.accuracy <= 15.0) {
          transitionIndoorToOutdoor(_pendingOutdoorDestination!);
        }
      }
    });
  }

  Future<void> transitionIndoorToOutdoor(String outdoorDestination) async {
    _gpsSub?.cancel();
    _gpsSub = null;
    _objectSearch.stopSearch(speakNotice: false);

    await _audio.speak(
      text: "Building exit confirmed. Starting Google Maps walking route to $outdoorDestination.",
      priority: AudioPriority.navigationInstruction,
    );

    await _startOutdoorGpsRouting(outdoorDestination);
  }

  Future<void> transitionOutdoorToIndoor() async {
    if (_mode != ActiveNavigationMode.outdoorGps) return;

    _mode = ActiveNavigationMode.none;
    _gpsSub?.cancel();
    _gpsSub = null;
    _outdoorRouter.stopNavigation();
    _outdoorGuardian.stop();

    final msg = "You have entered the building. Switching to indoor visual guidance. What room or object would you like to find?";
    await _audio.speak(
      text: msg,
      priority: AudioPriority.navigationInstruction,
    );
  }

  Future<void> confirmBuildingExit() async {
    if (_mode == ActiveNavigationMode.indoorGuidingToExit && _pendingOutdoorDestination != null) {
      await transitionIndoorToOutdoor(_pendingOutdoorDestination!);
    }
  }

  Future<void> confirmBuildingEntry() async {
    if (_mode == ActiveNavigationMode.outdoorGps) {
      await transitionOutdoorToIndoor();
    }
  }

  void updateHeading(double heading) {}

  void onStep(int delta) {}

  /// Stop all active navigation, timers, and camera streams immediately.
  void stopAllNavigation() {
    _mode = ActiveNavigationMode.none;
    _pendingOutdoorDestination = null;
    _pendingClarificationDestination = null;
    _gpsSub?.cancel();
    _gpsSub = null;
    _outdoorRouter.stopNavigation();
    _outdoorGuardian.stop();
    _liveVision.stopSession();
    _objectSearch.stopSearch(speakNotice: false);
  }
}
