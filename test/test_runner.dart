import 'dart:convert';
import 'package:sight_mate/models/app_intent.dart';
import 'package:sight_mate/models/object_search_models.dart';
import 'package:sight_mate/services/intent_router.dart';

void main() {
  print('=== STARTING SIGHT MATE VERIFICATION SUITE ===');
  int passed = 0;
  int failed = 0;

  void expect(dynamic actual, dynamic expected, String testName) {
    if (actual == expected) {
      print('  ✓ PASS: $testName');
      passed++;
    } else {
      print('  ✗ FAIL: $testName');
      print('    Expected: $expected');
      print('    Actual:   $actual');
      failed++;
    }
  }

  final router = IntentRouter();

  // Test 1: Case 1 - Nearby object queries
  print('\n-- Test Group 1: Case 1 (Nearby Physical Objects) --');
  final t1 = router.route('Take me to the door');
  expect(t1.type, AppIntentType.navigate, 'Take me to the door maps to navigate');
  expect(t1.slot, 'door', 'Slot is "door"');

  final t2 = router.route('Find the bathroom');
  expect(t2.type, AppIntentType.findObject, 'Find the bathroom maps to findObject');
  expect(t2.slot, 'bathroom', 'Slot is "bathroom"');

  final t3 = router.route('Where is the chair');
  expect(t3.type, AppIntentType.findObject, 'Where is the chair maps to findObject');
  expect(t3.slot, 'chair', 'Slot is "chair"');

  final t4 = router.route('Can you find a water bottle for me?');
  expect(t4.type, AppIntentType.findObject, 'Conversational water bottle maps to findObject');
  expect(t4.slot, 'water bottle', 'Cleaned slot is "water bottle" without filler');

  // Test 2: Case 2 - Indoor Destinations
  print('\n-- Test Group 2: Case 2 (Indoor Destinations) --');
  final t5 = router.route('Guide me to the classroom');
  expect(t5.type, AppIntentType.navigate, 'Guide me to classroom maps to navigate');
  expect(t5.slot, 'classroom', 'Slot is "classroom"');

  final t6 = router.route('Take me to Software Lab');
  expect(t6.type, AppIntentType.navigate, 'Take me to Software Lab maps to navigate');
  expect(t6.slot, 'software lab', 'Slot is "software lab"');

  // Test 3: Case 3 - Outdoor Destinations
  print('\n-- Test Group 3: Case 3 (Outdoor Places & Addresses) --');
  final t7 = router.route('Navigate to the bus stop');
  expect(t7.type, AppIntentType.navigate, 'Navigate to bus stop maps to navigate');
  expect(t7.slot, 'bus stop', 'Slot is "bus stop" without article');

  final t8 = router.route('Directions to Central Station');
  expect(t8.type, AppIntentType.navigate, 'Directions to Central Station maps to navigate');
  expect(t8.slot, 'central station', 'Slot is "central station"');

  // Test 4: Exit & Entry Confirmations
  print('\n-- Test Group 4: Exit & Entry Confirmations --');
  final t9 = router.route("I'm outside");
  expect(t9.type, AppIntentType.confirmExit, 'I am outside maps to confirmExit');

  final t10 = router.route("I've exited");
  expect(t10.type, AppIntentType.confirmExit, 'I have exited maps to confirmExit');

  final t11 = router.route('I entered the building');
  expect(t11.type, AppIntentType.confirmEntry, 'Entered building maps to confirmEntry');

  final t12 = router.route('I am inside');
  expect(t12.type, AppIntentType.confirmEntry, 'I am inside maps to confirmEntry');

  // Test 5: Persistent Object Search & Directional Models
  print('\n-- Test Group 5: Object Search Models & Directions --');
  expect(ObjectDirection.ahead.label, 'ahead', 'ObjectDirection.ahead label');
  expect(ObjectDirection.left.label, 'on your left', 'ObjectDirection.left label');
  expect(ObjectDirection.right.label, 'on your right', 'ObjectDirection.right label');

  const foundResult = ObjectSearchResult(
    status: TargetDetectionStatus.found,
    direction: ObjectDirection.ahead,
    distance: 'about 2 metres',
    description: 'A wooden chair is directly ahead.',
    guidance: '',
  );
  expect(foundResult.isFound, true, 'ObjectSearchResult isFound');

  const jsonStr = '{"status":"found","direction":"right","distance":"about 2 metres"}';
  final map = jsonDecode(jsonStr) as Map<String, dynamic>;
  expect(map['status'], 'found', 'JSON status parsed');
  expect(map['direction'], 'right', 'JSON direction parsed');

  print('\n================================================');
  print('TEST SUMMARY: $passed passed, $failed failed.');
  print('================================================');
}
