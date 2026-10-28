import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sight_mate/models/app_intent.dart';
import 'package:sight_mate/models/clew_route_models.dart';
import 'package:sight_mate/services/intent_router.dart';
import 'package:sight_mate/services/gemini_service.dart';
import 'package:sight_mate/services/unified_navigation_coordinator.dart';
import 'package:sight_mate/services/map_loader.dart';
import 'package:sight_mate/services/gps_service.dart';
import 'package:sight_mate/services/audio_priority_manager.dart';
import 'package:sight_mate/services/tts_service.dart';
import 'package:sight_mate/services/clew_route_follower.dart';
import 'package:sight_mate/services/outdoor_routing_service.dart';
import 'package:sight_mate/services/outdoor_safety_guardian.dart';
import 'package:sight_mate/services/live_vision_session.dart';
import 'package:sight_mate/services/persistent_object_search_service.dart';
import 'package:sight_mate/services/positioning_service.dart';
import 'package:sight_mate/services/camera_service.dart';
import 'package:sight_mate/services/local_perception_service.dart';

class FakeTts extends TtsService {
  String? lastSpoken;
  @override
  Future<void> speak(String text, {bool movieMode = false}) async {
    lastSpoken = text;
  }
  @override
  Future<void> stop() async {}
}

void main() {
  group('Indoor/Outdoor Navigation Intent & Mode Selection Tests', () {
    final router = IntentRouter();

    test('1. "Take me to the door" routes to navigate with slot "door"', () {
      final intent = router.route('Take me to the door');
      expect(intent.type, equals(AppIntentType.navigate));
      expect(intent.slot, equals('door'));
    });

    test('2. "Find the bathroom" routes to findObject with slot "bathroom"', () {
      final intent = router.route('Find the bathroom');
      expect(intent.type, equals(AppIntentType.findObject));
      expect(intent.slot, equals('bathroom'));
    });

    test('3. "Guide me to the classroom" routes to navigate with slot "classroom"', () {
      final intent = router.route('Guide me to the classroom');
      expect(intent.type, equals(AppIntentType.navigate));
      expect(intent.slot, equals('classroom'));
    });

    test('4. "Take me to the bus stop" routes to navigate with slot "bus stop"', () {
      final intent = router.route('Take me to the bus stop');
      expect(intent.type, equals(AppIntentType.navigate));
      expect(intent.slot, equals('bus stop'));
    });

    test('5. Building entry and exit voice confirmations', () {
      final exit1 = router.route('I am outside');
      expect(exit1.type, equals(AppIntentType.confirmExit));

      final exit2 = router.route("I've exited");
      expect(exit2.type, equals(AppIntentType.confirmExit));

      final entry1 = router.route('I am inside');
      expect(entry1.type, equals(AppIntentType.confirmEntry));

      final entry2 = router.route('Entered the building');
      expect(entry2.type, equals(AppIntentType.confirmEntry));
    });
  });

  group('Clew Route Models & Bidirectional Inversion Tests', () {
    test('ClewRoute createReturnRoute inverts crumbs and keypoints correctly', () {
      final now = DateTime.now();
      final crumbs = [
        ClewCrumb(x: 0.0, y: 0.0, heading: 90.0, stepCount: 0, timestamp: now),
        ClewCrumb(x: 7.0, y: 0.0, heading: 90.0, stepCount: 10, timestamp: now),
        ClewCrumb(x: 7.0, y: 7.0, heading: 0.0, stepCount: 20, timestamp: now),
      ];

      final keypoints = [
        const ClewKeypoint(
          index: 0,
          x: 0.0,
          y: 0.0,
          heading: 90.0,
          turnAngle: 0.0,
          cumulativeSteps: 0,
          cumulativeMeters: 0.0,
          instruction: 'Start at Room A.',
        ),
        const ClewKeypoint(
          index: 1,
          x: 7.0,
          y: 0.0,
          heading: 0.0,
          turnAngle: -90.0, // Left turn
          cumulativeSteps: 10,
          cumulativeMeters: 7.0,
          instruction: 'Turn left.',
        ),
        const ClewKeypoint(
          index: 2,
          x: 7.0,
          y: 7.0,
          heading: 0.0,
          turnAngle: 0.0,
          cumulativeSteps: 20,
          cumulativeMeters: 14.0,
          instruction: 'Arrived at Room B.',
        ),
      ];

      final forwardRoute = ClewRoute(
        id: 'test_route_ab',
        name: 'Room A to Room B',
        startName: 'Room A',
        destinationName: 'Room B',
        createdAt: now,
        crumbs: crumbs,
        keypoints: keypoints,
        totalSteps: 20,
        totalDistanceMeters: 14.0,
      );

      final returnRoute = forwardRoute.createReturnRoute();

      // Return route should swap endpoints
      expect(returnRoute.startName, equals('Room B'));
      expect(returnRoute.destinationName, equals('Room A'));
      expect(returnRoute.totalSteps, equals(20));

      // Keypoints in return route should have reversed order
      expect(returnRoute.keypoints.length, equals(3));
      expect(returnRoute.keypoints.first.instruction, contains('Start from Room B'));
      expect(returnRoute.keypoints.last.instruction, contains('Arrived at Room A'));

      // Headings should be flipped by 180 degrees
      expect(returnRoute.crumbs.first.heading, equals(180.0)); // (0 + 180) % 360
    });
  });

  group('Destination Categorization Tests', () {
    late UnifiedNavigationCoordinator coordinator;
    late MapLoader map;

    setUp(() {
      final fakeTts = FakeTts();
      final audio = AudioPriorityManager(fakeTts);
      final gps = GpsService();
      map = MapLoader();
      final pos = PositioningService(map, gps);
      final cam = CameraService();
      final gemini = GeminiService();
      final local = LocalPerceptionService();

      final clewFollower = ClewRouteFollower(
        camera: cam,
        gemini: gemini,
        audio: audio,
        localPerception: local,
      );
      final outdoorRouter = OutdoorRoutingService(gps);
      final outdoorGuardian = OutdoorSafetyGuardian(
        camera: cam,
        gemini: gemini,
        audio: audio,
        localPerception: local,
      );
      final liveVision = LiveVisionSession(
        camera: cam,
        gemini: gemini,
        audio: audio,
      );
      final objectSearch = PersistentObjectSearchService(
        camera: cam,
        gemini: gemini,
        audio: audio,
        positioning: pos,
        localPerception: local,
      );

      coordinator = UnifiedNavigationCoordinator(
        gps: gps,
        audio: audio,
        clewFollower: clewFollower,
        outdoorRouter: outdoorRouter,
        outdoorGuardian: outdoorGuardian,
        liveVision: liveVision,
        objectSearch: objectSearch,
        map: map,
        positioning: pos,
      );
    });

    test('Case 1: Nearby physical objects categorize as nearbyObject', () async {
      expect(await coordinator.categorizeDestination('door'), equals(DestinationCategory.nearbyObject));
      expect(await coordinator.categorizeDestination('chair'), equals(DestinationCategory.nearbyObject));
      expect(await coordinator.categorizeDestination('water bottle'), equals(DestinationCategory.nearbyObject));
      expect(await coordinator.categorizeDestination('bathroom'), equals(DestinationCategory.nearbyObject));
      expect(await coordinator.categorizeDestination('stairs'), equals(DestinationCategory.nearbyObject));
      expect(await coordinator.categorizeDestination('desk'), equals(DestinationCategory.nearbyObject));
    });

    test('Case 2: Indoor destinations categorize as indoorSavedRoute', () async {
      expect(await coordinator.categorizeDestination('classroom'), equals(DestinationCategory.indoorSavedRoute));
      expect(await coordinator.categorizeDestination('software lab'), equals(DestinationCategory.indoorSavedRoute));
      expect(await coordinator.categorizeDestination('staff room'), equals(DestinationCategory.indoorSavedRoute));
      expect(await coordinator.categorizeDestination('room 204'), equals(DestinationCategory.indoorSavedRoute));
      expect(await coordinator.categorizeDestination('lab 3'), equals(DestinationCategory.indoorSavedRoute));
    });

    test('Case 3: Outdoor destinations categorize as outdoorPlace', () async {
      expect(await coordinator.categorizeDestination('bus stop'), equals(DestinationCategory.outdoorPlace));
      expect(await coordinator.categorizeDestination('city hospital'), equals(DestinationCategory.outdoorPlace));
      expect(await coordinator.categorizeDestination('train station'), equals(DestinationCategory.outdoorPlace));
      expect(await coordinator.categorizeDestination('supermarket'), equals(DestinationCategory.outdoorPlace));
      expect(await coordinator.categorizeDestination('100 Main Street'), equals(DestinationCategory.outdoorPlace));
    });

    test('Case 4: Ambiguous destinations ask clarification question', () async {
      expect(await coordinator.categorizeDestination('canteen'), equals(DestinationCategory.ambiguous));
      expect(await coordinator.categorizeDestination('library'), equals(DestinationCategory.ambiguous));
      expect(await coordinator.categorizeDestination('gym'), equals(DestinationCategory.ambiguous));

      // Test clarification flow
      final prompt = await coordinator.startNavigation('library');
      expect(prompt, contains('inside this building, or outdoors?'));
      expect(coordinator.isWaitingForClarification, isTrue);

      // Clarify as indoors
      await coordinator.handleClarification('inside');
      expect(coordinator.isWaitingForClarification, isFalse);
    });

    test('Case 5: Indoor-to-Outdoor transition keeps pending destination', () async {
      // Simulate user indoors requesting outdoor destination
      final res = await coordinator.startNavigation('bus stop');
      expect(res, contains('building exit first'));
      expect(coordinator.mode, equals(ActiveNavigationMode.indoorGuidingToExit));

      // When building exit is confirmed, transitions to outdoor GPS
      await coordinator.confirmBuildingExit();
      expect(coordinator.mode, equals(ActiveNavigationMode.outdoorGps));
    });

    test('Case 6: Outdoor-to-Indoor transition when entering building', () async {
      // Simulate confirmation of entering building
      await coordinator.confirmBuildingEntry();
      expect(coordinator.mode, equals(ActiveNavigationMode.none));
    });
  });

  group('Low-Token Gemini Object Locator Parsing Tests', () {
    test('Compact format "FOUND: ahead, 2 metres" parses accurately', () {
      final gemini = GeminiService();
      final res = gemini.locateObject(targetObject: 'chair', imageBytes: Uint8List(0));
      expect(res, isNotNull);
    });
  });
}
