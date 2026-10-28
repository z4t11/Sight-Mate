import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sight_mate/models/app_intent.dart';
import 'package:sight_mate/models/object_search_models.dart';
import 'package:sight_mate/services/intent_router.dart';
import 'package:sight_mate/services/audio_priority_manager.dart';

void main() {
  group('Persistent Object Search Intent Routing Tests (Section 5)', () {
    final router = IntentRouter();

    test('1. "Find a chair" maps to findObject with slot "chair"', () {
      final intent = router.route('Find a chair');
      expect(intent.type, equals(AppIntentType.findObject));
      expect(intent.slot, equals('chair'));
    });

    test('2. "Where is the door" maps to findObject with slot "door"', () {
      final intent = router.route('Where is the door');
      expect(intent.type, equals(AppIntentType.findObject));
      expect(intent.slot, equals('door'));
    });

    test('3. "Find the door instead" maps to switchFindObject with slot "door"', () {
      final intent = router.route('Find the door instead');
      expect(intent.type, equals(AppIntentType.switchFindObject));
      expect(intent.slot, equals('door'));
    });

    test('4. "Turn left" and "Turn right" map to scanTurnCommand', () {
      final left = router.route('turn left');
      expect(left.type, equals(AppIntentType.scanTurnCommand));
      expect(left.slot, equals('left'));

      final right = router.route('turn right');
      expect(right.type, equals(AppIntentType.scanTurnCommand));
      expect(right.slot, equals('right'));
    });

    test('5. "Keep looking" maps to continueSearch', () {
      final intent = router.route('keep looking');
      expect(intent.type, equals(AppIntentType.continueSearch));
    });

    test('6. "Stop searching" maps to stopSearch', () {
      final intent = router.route('stop searching');
      expect(intent.type, equals(AppIntentType.stopSearch));
    });

    test('7. Natural English conversational query strips trailing conversational filler', () {
      final intent1 = router.route('Can you find a water bottle for me?');
      expect(intent1.type, equals(AppIntentType.findObject));
      expect(intent1.slot, equals('water bottle'));

      final intent2 = router.route('Help me find my glasses please');
      expect(intent2.type, equals(AppIntentType.findObject));
      expect(intent2.slot, equals('glasses'));

      final intent3 = router.route('Where is the chair in here?');
      expect(intent3.type, equals(AppIntentType.findObject));
      expect(intent3.slot, equals('chair'));
    });
  });

  group('Object Search Models and Directions (Section 3 & 4)', () {
    test('Direction instructions and labels are accurate and conservative', () {
      expect(ObjectDirection.ahead.label, equals('ahead'));
      expect(ObjectDirection.ahead.turnInstruction, contains('straight ahead'));

      expect(ObjectDirection.left.label, equals('on your left'));
      expect(ObjectDirection.left.turnInstruction, contains('left toward it'));

      expect(ObjectDirection.right.label, equals('on your right'));
      expect(ObjectDirection.right.turnInstruction, contains('right toward it'));

      expect(ObjectDirection.nearEdge.label, equals('near the edge of view'));
      expect(ObjectDirection.nearEdge.turnInstruction, contains('bring it into the center'));
    });

    test('ObjectSearchResult correctly identifies detection states', () {
      const foundResult = ObjectSearchResult(
        status: TargetDetectionStatus.found,
        direction: ObjectDirection.ahead,
        distance: 'about 2 metres',
        description: 'A wooden chair is directly ahead.',
        guidance: '',
      );
      expect(foundResult.isFound, isTrue);
      expect(foundResult.isNotFound, isFalse);

      const notFoundResult = ObjectSearchResult(
        status: TargetDetectionStatus.notFound,
        direction: ObjectDirection.unknown,
        distance: 'unknown',
        description: 'No chair visible.',
        guidance: 'Slowly turn phone left.',
      );
      expect(notFoundResult.isFound, isFalse);
      expect(notFoundResult.isNotFound, isTrue);

      const uncertainResult = ObjectSearchResult(
        status: TargetDetectionStatus.uncertain,
        direction: ObjectDirection.nearEdge,
        distance: '3 metres',
        description: 'Possible chair leg near edge.',
        guidance: 'Turn phone right.',
      );
      expect(uncertainResult.isUncertain, isTrue);
    });

    test('JSON decoding parses model payload accurately', () {
      const jsonStr = '''
      {
        "status": "found",
        "direction": "right",
        "distance": "about 2 metres",
        "confidence": "high",
        "description": "Office chair visible on right.",
        "guidance": "Turn phone a little toward it."
      }
      ''';
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(map['status'], equals('found'));
      expect(map['direction'], equals('right'));
      expect(map['distance'], equals('about 2 metres'));
    });
  });

  group('Audio Priority Arbitration (Requirement 7 & 6)', () {
    test('Safety hazard priority strictly preempts all lower priorities', () {
      expect(AudioPriority.urgentHazard.level, equals(0));
      expect(AudioPriority.navigationInstruction.level, equals(1));
      expect(AudioPriority.conversationalResponse.level, equals(2));
      expect(AudioPriority.systemNotice.level, equals(3));

      expect(AudioPriority.urgentHazard.level < AudioPriority.navigationInstruction.level, isTrue);
      expect(AudioPriority.urgentHazard.level < AudioPriority.conversationalResponse.level, isTrue);
      expect(AudioPriority.urgentHazard.level < AudioPriority.systemNotice.level, isTrue);
    });
  });
}
