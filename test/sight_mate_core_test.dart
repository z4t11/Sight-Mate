import 'package:flutter_test/flutter_test.dart';
import 'package:sight_mate/models/clew_route_models.dart';
import 'package:sight_mate/services/audio_priority_manager.dart';
import 'package:sight_mate/services/tts_service.dart';
import 'package:sight_mate/services/local_perception_service.dart';
import 'package:sight_mate/services/camera_service.dart';
import 'package:sight_mate/services/gemini_service.dart';
import 'package:sight_mate/services/clew_route_follower.dart';

// Fake TTS for deterministic testing without native engine
class FakeTtsService extends TtsService {
  String? lastSpoken;
  bool wasStopped = false;
  bool fakeSpeaking = false;

  @override
  bool get isSpeaking => fakeSpeaking;

  @override
  Future<void> speak(String text, {bool movieMode = false}) async {
    lastSpoken = text;
    fakeSpeaking = true;
  }

  @override
  Future<void> stop() async {
    wasStopped = true;
    fakeSpeaking = false;
  }
}

void main() {
  group('AudioPriorityManager Tests', () {
    test('Priority levels ordering is correct', () {
      expect(
        AudioPriority.urgentHazard.hasHigherOrEqualPriorityThan(AudioPriority.navigationInstruction),
        isTrue,
      );
      expect(
        AudioPriority.navigationInstruction.hasHigherOrEqualPriorityThan(AudioPriority.conversationalResponse),
        isTrue,
      );
      expect(
        AudioPriority.conversationalResponse.hasHigherOrEqualPriorityThan(AudioPriority.urgentHazard),
        isFalse,
      );
    });

    test('Urgent hazard immediately interrupts conversational speech', () async {
      final fakeTts = FakeTtsService();
      final audioManager = AudioPriorityManager(fakeTts);

      // Start low priority speech
      await audioManager.speak(
        text: 'The room appears to have three chairs.',
        priority: AudioPriority.conversationalResponse,
      );
      expect(fakeTts.lastSpoken, equals('The room appears to have three chairs.'));

      // Interrupt with hazard
      await audioManager.speak(
        text: 'Stop! Drop-off detected directly ahead.',
        priority: AudioPriority.urgentHazard,
      );
      expect(fakeTts.lastSpoken, equals('Stop! Drop-off detected directly ahead.'));
    });

    test('Duplicate hazard announcements are rate-limited', () async {
      final fakeTts = FakeTtsService();
      final audioManager = AudioPriorityManager(fakeTts);

      final first = await audioManager.speak(
        text: 'Obstacle ahead on your path.',
        priority: AudioPriority.urgentHazard,
      );
      expect(first, isTrue);

      final duplicate = await audioManager.speak(
        text: 'Obstacle ahead on your path.',
        priority: AudioPriority.urgentHazard,
      );
      expect(duplicate, isFalse); // Suppressed within cooldown window
    });
  });

  group('Clew Route & Follower Tests', () {
    late ClewRoute sampleRoute;

    setUp(() {
      sampleRoute = ClewRoute(
        id: 'route_staff_to_lab',
        name: 'Staff Room to Software Lab',
        startName: 'Staff Room',
        destinationName: 'Software Lab',
        createdAt: DateTime.now(),
        crumbs: [
          ClewCrumb(x: 0, y: 0, heading: 0, stepCount: 0, timestamp: DateTime.now()),
          ClewCrumb(x: 0, y: 10, heading: 0, stepCount: 14, timestamp: DateTime.now()),
          ClewCrumb(x: -12, y: 10, heading: 270, stepCount: 32, timestamp: DateTime.now()),
        ],
        keypoints: const [
          ClewKeypoint(
            index: 0,
            x: 0,
            y: 0,
            heading: 0,
            turnAngle: 0,
            cumulativeSteps: 0,
            cumulativeMeters: 0,
            instruction: 'Start from Staff Room. Walk forward 14 steps.',
          ),
          ClewKeypoint(
            index: 1,
            x: 0,
            y: 10,
            heading: 270,
            turnAngle: -90,
            cumulativeSteps: 14,
            cumulativeMeters: 10,
            instruction: 'Turn left. Walk forward 18 steps.',
          ),
          ClewKeypoint(
            index: 2,
            x: -12,
            y: 10,
            heading: 270,
            turnAngle: 0,
            cumulativeSteps: 32,
            cumulativeMeters: 22,
            instruction: 'You have arrived at Software Lab.',
          ),
        ],
        totalSteps: 32,
        totalDistanceMeters: 22.0,
      );
    });

    test('ClewRoute serializes and deserializes cleanly to JSON', () {
      final json = sampleRoute.toJson();
      final restored = ClewRoute.fromJson(json);

      expect(restored.id, equals('route_staff_to_lab'));
      expect(restored.startName, equals('Staff Room'));
      expect(restored.destinationName, equals('Software Lab'));
      expect(restored.crumbs.length, equals(3));
      expect(restored.keypoints.length, equals(3));
      expect(restored.totalSteps, equals(32));
      expect(restored.totalDistanceMeters, equals(22.0));
    });

    test('createReturnRoute inverts route accurately', () {
      final returnRoute = sampleRoute.createReturnRoute();

      expect(returnRoute.startName, equals('Software Lab'));
      expect(returnRoute.destinationName, equals('Staff Room'));
      expect(returnRoute.totalSteps, equals(32));
      expect(returnRoute.totalDistanceMeters, equals(22.0));
      expect(returnRoute.keypoints.first.instruction, contains('Start from Software Lab'));
      expect(returnRoute.keypoints.last.instruction, contains('Arrived at Staff Room'));
    });

    test('ClewRouteFollower tracks route progression hands-free', () async {
      final fakeTts = FakeTtsService();
      final audioManager = AudioPriorityManager(fakeTts);
      final camera = CameraService();
      final gemini = GeminiService();
      final perception = LocalPerceptionService();

      final follower = ClewRouteFollower(
        camera: camera,
        gemini: gemini,
        audio: audioManager,
        localPerception: perception,
      );

      final startMsg = await follower.startRoute(sampleRoute);
      expect(follower.isNavigating, isTrue);
      expect(startMsg, contains('Starting route to Software Lab'));

      // Progress through segment 1
      for (int i = 0; i < 14; i++) {
        follower.onStep(1);
      }
      expect(follower.totalStepsTaken, equals(14));

      // Stop route
      follower.stopRoute();
      expect(follower.isNavigating, isFalse);
    });
  });

  group('LocalPerceptionService State Tests', () {
    test('Service resets tracking cleanly', () {
      final perception = LocalPerceptionService();
      perception.reset();
      expect(perception, isNotNull);
    });
  });
}
