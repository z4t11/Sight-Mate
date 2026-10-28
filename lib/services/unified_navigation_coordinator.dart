import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'gps_service.dart';
import 'audio_priority_manager.dart';
import 'clew_route_follower.dart';
import 'clew_route_storage.dart';
import 'outdoor_routing_service.dart';
import 'outdoor_safety_guardian.dart';
import 'live_vision_session.dart';
import 'persistent_object_search_service.dart';
import 'map_loader.dart';
import 'positioning_service.dart';

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
/// Coordinates Clew-style indoor route retracing, live vision object search,
/// outdoor Google Maps / GPS routing, and intelligent indoor <-> outdoor transitions.
class UnifiedNavigationCoordinator {
  final GpsService _gps;
  final AudioPriorityManager _audio;
  final ClewRouteFollower _clewFollower;
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
  ClewRouteFollower get clewFollower => _clewFollower;

  UnifiedNavigationCoordinator({
    required GpsService gps,
    required AudioPriorityManager audio,
    required ClewRouteFollower clewFollower,
    required OutdoorRoutingService outdoorRouter,
    required OutdoorSafetyGuardian outdoorGuardian,
    required LiveVisionSession liveVision,
    required PersistentObjectSearchService objectSearch,
    required MapLoader map,
    required PositioningService positioning,
  })  : _gps = gps,
        _audio = audio,
        _clewFollower = clewFollower,
        _outdoorRouter = outdoorRouter,
        _outdoorGuardian = outdoorGuardian,
        _liveVision = liveVision,
        _objectSearch = objectSearch,
        _map = map,
        _positioning = positioning;

  // ── Destination Keywords ──────────────────────────────────────────

  static const List<String> _nearbyObjectKeywords = [
    'door', 'front door', 'back door', 'exit door', 'main door', 'bedroom door',
    'office door', 'classroom door', 'bathroom door', 'entrance door',
    'chair', 'seat', 'armchair', 'couch', 'sofa', 'bench', 'stool',
    'table', 'desk', 'counter', 'coffee table', 'dining table',
    'bottle', 'water bottle', 'cup', 'glass', 'mug', 'flask',
    'bathroom', 'restroom', 'washroom', 'toilet', 'sink', 'basin',
    'stairs', 'staircase', 'steps', 'elevator', 'lift', 'escalator',
    'window', 'wall', 'pillar', 'pole', 'railing', 'trash can', 'bin', 'dustbin',
    'keys', 'key', 'phone', 'mobile', 'wallet', 'purse', 'cane', 'white cane',
    'bag', 'backpack', 'charger', 'laptop', 'computer', 'screen', 'monitor',
    'keyboard', 'mouse', 'switch', 'light switch', 'board', 'whiteboard',
  ];

  static const List<String> _indoorCategoryKeywords = [
    'room', 'classroom', 'class room', 'lab', 'laboratory',
    'software lab', 'hardware lab', 'staff room', 'faculty room',
    'hallway', 'corridor', 'auditorium', 'conference room',
    'seminar hall', 'cabin', 'floor', 'reception desk',
  ];

  static const List<String> _outdoorKeywords = [
    'bus stop', 'bus station', 'bus stand', 'train station', 'railway station',
    'metro station', 'subway', 'hospital', 'clinic', 'pharmacy', 'medical store',
    'supermarket', 'grocery', 'grocery store', 'market', 'mall', 'shopping mall',
    'park', 'playground', 'stadium', 'bank', 'atm', 'post office',
    'street', 'road', 'avenue', 'lane', 'boulevard', 'highway', 'drive',
    'restaurant', 'hotel', 'cafe', 'coffee shop', 'bakery', 'airport',
    'gas station', 'petrol pump', 'another building', 'next building', 'outside building',
  ];

  static const List<String> _ambiguousKeywords = [
    'canteen', 'library', 'reception', 'gym', 'store', 'gate', 'parking', 'entrance',
  ];

  /// Categorize the destination query into nearby object, indoor route, outdoor place, or ambiguous.
  Future<DestinationCategory> categorizeDestination(String destination, {String origin = 'Staff Room'}) async {
    final clean = destination.toLowerCase().trim();

    // 1. Check if an exact saved Clew route exists in ClewRouteStorage
    final clewRoute = await ClewRouteStorage.findRoute(
      startName: origin,
      destinationName: clean,
    );
    if (clewRoute != null) {
      return DestinationCategory.indoorSavedRoute;
    }

    // 2. Check if a node exists in MapLoader
    final mapNode = _map.findByName(clean);
    if (mapNode != null) {
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
    final addressPattern = RegExp(r'\b(?:\d+\s+)?(?:street|road|st|rd|ave|avenue|lane|drive|blvd|way)\b', caseSensitive: false);
    if (addressPattern.hasMatch(clean)) {
      return DestinationCategory.outdoorPlace;
    }

    // 6. Check ambiguous keywords
    for (final amb in _ambiguousKeywords) {
      if (clean.contains(amb)) {
        return DestinationCategory.ambiguous;
      }
    }

    // Default: ambiguous
    return DestinationCategory.ambiguous;
  }

  /// Whether the user is currently determined to be indoors.
  bool get isUserIndoors {
    if (_positioning.state.currentNodeId != null) return true;
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
  /// Uses live camera vision and monotonic 360° search. NEVER sends to map search!
  Future<String> _startNearbyObjectSearch(String objectName) async {
    stopAllNavigation();
    _mode = ActiveNavigationMode.nearbyObjectSearch;

    await _objectSearch.startSearch(objectName);
    return "Looking for $objectName with the camera.";
  }

  /// Case 2: Clew-Style Indoor Saved Route Retracing.
  /// Uses hands-free spatial keypoints, dead reckoning, and supporting Gemini vision.
  Future<String> _startIndoorDestination(String destination, {String origin = 'Staff Room'}) async {
    stopAllNavigation();

    // 1. Check for a saved ClewRoute
    final clewRoute = await ClewRouteStorage.findRoute(
      startName: origin,
      destinationName: destination,
    );

    if (clewRoute != null) {
      _mode = ActiveNavigationMode.indoorSavedRoute;
      final startInstruction = await _clewFollower.startRoute(clewRoute);
      return startInstruction;
    }

    // 2. Check MapLoader node fallback
    final mapNode = _map.findByName(destination);
    if (mapNode != null) {
      final msg = "Found ${mapNode.name} on the building map. Head down the corridor and look for ${mapNode.expectedSigns.isNotEmpty ? mapNode.expectedSigns.first : mapNode.name}.";
      _mode = ActiveNavigationMode.indoorSavedRoute;
      await _audio.speak(text: msg, priority: AudioPriority.navigationInstruction);
      return msg;
    }

    // Indoor target has no saved route yet: prompt user to map route
    _mode = ActiveNavigationMode.none;
    final noRouteMsg = "I don't have a saved indoor route to $destination yet. "
        "You can record this route hands-free using the Map Route button.";
    await _audio.speak(text: noRouteMsg, priority: AudioPriority.conversationalResponse);
    return noRouteMsg;
  }

  /// Case 3: Outdoor destination (bus stop, hospital, street address).
  /// If user is indoors, guides to the building exit first using Clew routes or exit door vision,
  /// then transitions to outdoor Google Maps/GPS once outside.
  Future<String> _startOutdoorDestination(String destination, {String origin = 'Staff Room'}) async {
    stopAllNavigation();

    if (isUserIndoors) {
      _mode = ActiveNavigationMode.indoorGuidingToExit;
      _pendingOutdoorDestination = destination;

      // Look for a recorded indoor route to the exit
      final exitRoute = await ClewRouteStorage.findRoute(startName: origin, destinationName: 'Exit')
          ?? await ClewRouteStorage.findRoute(startName: origin, destinationName: 'Main Exit')
          ?? await ClewRouteStorage.findRoute(startName: origin, destinationName: 'Front Door')
          ?? await ClewRouteStorage.findRoute(startName: origin, destinationName: 'Entrance');

      _startGpsExitMonitor();

      if (exitRoute != null) {
        final exitMsg = await _clewFollower.startRoute(exitRoute);
        final spoken = "Guiding you to the building exit first. Once outside, I will guide you to $destination. $exitMsg";
        await _audio.speak(text: spoken, priority: AudioPriority.navigationInstruction);
        return spoken;
      } else {
        // No recorded exit route: use visual search for the exit door
        final msg = "Guiding you to the building exit first. Looking for the exit door. Once outside, I will guide you to $destination.";
        await _audio.speak(text: msg, priority: AudioPriority.navigationInstruction);
        await _objectSearch.startSearch("exit door");
        return msg;
      }
    } else {
      return await _startOutdoorGpsRouting(destination);
    }
  }

  /// Start direct outdoor GPS routing with safety guardian.
  Future<String> _startOutdoorGpsRouting(String destination) async {
    _mode = ActiveNavigationMode.outdoorGps;
    _pendingOutdoorDestination = null;

    final outdoorMsg = await _outdoorRouter.planRoute(destination);
    if (outdoorMsg != null) {
      _outdoorGuardian.start();

      _gpsSub?.cancel();
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
      ).listen((pos) async {
        if (_mode != ActiveNavigationMode.outdoorGps) return;

        final turnMsg = _outdoorRouter.onPositionUpdate(pos);
        if (turnMsg != null) {
          await _audio.speak(
            text: turnMsg,
            priority: AudioPriority.navigationInstruction,
          );

          if (turnMsg.toLowerCase().contains('arrived') || turnMsg.toLowerCase().contains('complete')) {
            await transitionOutdoorToIndoor();
          }
        }
      });

      await _audio.speak(
        text: outdoorMsg,
        priority: AudioPriority.navigationInstruction,
      );
      return outdoorMsg;
    }

    _mode = ActiveNavigationMode.none;
    final failMsg = "Unable to plan an outdoor walking route to '$destination'. Please check the address or try again.";
    await _audio.speak(text: failMsg, priority: AudioPriority.systemNotice);
    return failMsg;
  }

  /// Ambiguous destination: Ask clarifying question.
  Future<String> _askClarification(String destination) async {
    _mode = ActiveNavigationMode.none;
    _pendingClarificationDestination = destination;

    final question = "Is $destination inside this building, or outdoors?";
    await _audio.speak(
      text: question,
      priority: AudioPriority.conversationalResponse,
    );
    return question;
  }

  /// Handle user's response to an ambiguous clarification question.
  Future<String> handleClarification(String userResponse) async {
    final dest = _pendingClarificationDestination;
    _pendingClarificationDestination = null;

    if (dest == null) return '';

    final lower = userResponse.toLowerCase().trim();
    if (lower.contains('in') || lower.contains('inside') || lower.contains('building') || lower.contains('indoor')) {
      return await startNavigation(dest, forceIndoor: true);
    } else if (lower.contains('out') || lower.contains('outside') || lower.contains('outdoor') || lower.contains('street')) {
      return await startNavigation(dest, forceOutdoor: true);
    } else {
      final retry = "Please say 'inside' or 'outdoors' for $dest.";
      _pendingClarificationDestination = dest;
      await _audio.speak(text: retry, priority: AudioPriority.conversationalResponse);
      return retry;
    }
  }

  // ── Mode Transitions ──────────────────────────────────────────────

  void _startGpsExitMonitor() {
    _gpsSub?.cancel();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
    ).listen((pos) async {
      if (_mode == ActiveNavigationMode.indoorGuidingToExit) {
        if (pos.accuracy <= 16.0 && _pendingOutdoorDestination != null) {
          await transitionIndoorToOutdoor(_pendingOutdoorDestination!);
        }
      }
    });
  }

  Future<void> transitionIndoorToOutdoor(String outdoorDestination) async {
    _gpsSub?.cancel();
    _gpsSub = null;
    _clewFollower.stopRoute();
    _objectSearch.stopSearch(speakNotice: false);

    await _audio.speak(
      text: "Building exit confirmed. Starting outdoor walking route to $outdoorDestination.",
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

  /// Forward compass heading to Clew route follower for deviation checking.
  void updateHeading(double heading) {
    if (_mode == ActiveNavigationMode.indoorSavedRoute || _mode == ActiveNavigationMode.indoorGuidingToExit) {
      _clewFollower.updateHeading(heading);
    }
  }

  /// Forward pedometer step delta to Clew route follower.
  void onStep(int delta) async {
    if (_mode == ActiveNavigationMode.indoorSavedRoute || _mode == ActiveNavigationMode.indoorGuidingToExit) {
      _clewFollower.onStep(delta);
      if (!_clewFollower.isNavigating && _mode == ActiveNavigationMode.indoorGuidingToExit && _pendingOutdoorDestination != null) {
        await transitionIndoorToOutdoor(_pendingOutdoorDestination!);
      }
    }
  }

  /// Stop all active navigation, timers, and camera streams immediately.
  void stopAllNavigation() {
    _mode = ActiveNavigationMode.none;
    _pendingOutdoorDestination = null;
    _pendingClarificationDestination = null;
    _gpsSub?.cancel();
    _gpsSub = null;
    _clewFollower.stopRoute();
    _outdoorRouter.stopNavigation();
    _outdoorGuardian.stop();
    _liveVision.stopSession();
    _objectSearch.stopSearch(speakNotice: false);
  }
}
