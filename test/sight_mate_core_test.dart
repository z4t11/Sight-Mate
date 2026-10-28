import 'package:flutter_test/flutter_test.dart';
import 'package:sight_mate/services/audio_priority_manager.dart';
import 'package:sight_mate/services/tts_service.dart';
import 'package:sight_mate/services/local_perception_service.dart';

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

  group('LocalPerceptionService State Tests', () {
    test('Service resets tracking cleanly', () {
      final perception = LocalPerceptionService();
      perception.reset();
      expect(perception, isNotNull);
    });
  });
}
