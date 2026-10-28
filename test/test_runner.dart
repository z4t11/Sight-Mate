import 'package:sight_mate/models/app_intent.dart';
import 'package:sight_mate/models/clew_route_models.dart';
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

  // Test 5: Clew Route Serialization & Inverted Return Route
  print('\n-- Test Group 5: Clew Route Inversion & JSON Serialization --');
  final forwardRoute = ClewRoute(
    id: 'test_route_1',
    name: 'Office to Cafeteria',
    startName: 'Office',
    destinationName: 'Cafeteria',
    createdAt: DateTime.now(),
    crumbs: [
      ClewCrumb(x: 0, y: 0, heading: 90, stepCount: 0, timestamp: DateTime.now()),
      ClewCrumb(x: 10, y: 0, heading: 90, stepCount: 15, timestamp: DateTime.now()),
      ClewCrumb(x: 10, y: 8, heading: 0, stepCount: 27, timestamp: DateTime.now()),
    ],
    keypoints: const [
      ClewKeypoint(
        index: 0,
        x: 0,
        y: 0,
        heading: 90,
        turnAngle: 0,
        cumulativeSteps: 0,
        cumulativeMeters: 0,
        instruction: 'Start from Office. Walk forward 15 steps.',
      ),
      ClewKeypoint(
        index: 1,
        x: 10,
        y: 0,
        heading: 0,
        turnAngle: 90,
        cumulativeSteps: 15,
        cumulativeMeters: 10,
        instruction: 'Turn left. Walk forward 12 steps.',
      ),
      ClewKeypoint(
        index: 2,
        x: 10,
        y: 8,
        heading: 0,
        turnAngle: 0,
        cumulativeSteps: 27,
        cumulativeMeters: 18,
        instruction: 'Arrived at Cafeteria.',
      ),
    ],
    totalSteps: 27,
    totalDistanceMeters: 18.0,
  );

  final json = forwardRoute.toJson();
  final deserialized = ClewRoute.fromJson(json);
  expect(deserialized.id, 'test_route_1', 'ClewRoute JSON deserialization ID matches');
  expect(deserialized.totalSteps, 27, 'ClewRoute JSON steps match');

  final returnRoute = forwardRoute.createReturnRoute();
  expect(returnRoute.startName, 'Cafeteria', 'Return route startName is Cafeteria');
  expect(returnRoute.destinationName, 'Office', 'Return route destinationName is Office');
  expect(returnRoute.totalSteps, 27, 'Return route totalSteps preserved');
  expect(returnRoute.keypoints.first.instruction.contains('Start from Cafeteria'), true, 'Return keypoint 0 starts from Cafeteria');
  expect(returnRoute.keypoints.last.instruction.contains('Arrived at Office'), true, 'Return keypoint last arrives at Office');

  print('\n================================================');
  print('TEST SUMMARY: $passed passed, $failed failed.');
  print('================================================');
}
