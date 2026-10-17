import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:pedometer/pedometer.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';
import '../models/map_node.dart';
import '../models/nav_state.dart';
import 'map_loader.dart';
import 'app_config.dart';

/// Positioning engine: determines the user's current location node.
/// Strategy: OCR signs → match expected_signs → confirm landmark → 
/// between landmarks: step counting + compass → drift correction at each landmark.
/// Low confidence → ask user ("I think you're near Room 204, is that right?").
class PositioningService {
  final MapLoader _map;
  final TextRecognizer _textRecognizer = TextRecognizer();

  NavState _state = const NavState();
  double _heading = 0.0;
  int _lastStepCount = -1;

  StreamSubscription? _compassSub;
  StreamSubscription? _stepSub;

  NavState get state => _state;

  PositioningService(this._map);

  /// Start listening to compass + pedometer.
  void start() {
    // Compass heading
    _compassSub = magnetometerEventStream().listen((event) {
      // Simple heading from magnetometer (good enough for indoor relative turns).
      // atan2-based heading in degrees.
      _heading = _calculateHeading(event.x, event.y);
      _state = _state.copyWith(headingDegrees: _heading);
    });

    // Step counter
    _stepSub = Pedometer.stepCountStream.listen((event) {
      if (_lastStepCount < 0) {
        _lastStepCount = event.steps;
        return;
      }
      final delta = event.steps - _lastStepCount;
      _lastStepCount = event.steps;
      if (delta > 0) {
        _state = _state.copyWith(
          stepsSinceLast: _state.stepsSinceLast + delta,
          // Confidence decays as steps accumulate without a landmark
          confidence: (_state.confidence - 0.02 * delta).clamp(0.0, 1.0),
        );
      }
    });
  }

  /// Try OCR on the current camera frame to match expected_signs.
  /// Returns the matched node or null.
  Future<MapNode?> tryOcrMatch(CameraController? camController) async {
    if (AppConfig.isMockMode) return _mockOcrMatch();
    if (camController == null || !camController.value.isInitialized) {
      return null;
    }

    try {
      final xfile = await camController.takePicture();
      final inputImage = InputImage.fromFilePath(xfile.path);
      final recognized = await _textRecognizer.processImage(inputImage);
      final allText = recognized.text.toLowerCase();

      if (allText.isEmpty) return null;

      // Check each node's expected_signs
      for (final node in _map.nodes.values) {
        for (final sign in node.expectedSigns) {
          if (allText.contains(sign.toLowerCase())) {
            // Confirmed landmark!
            _confirmLandmark(node.id);
            return node;
          }
        }
      }
    } catch (_) {
      // OCR failed — no match
    }
    return null;
  }

  /// Manually confirm location (e.g., user says "yes" to "I think you're near…").
  void confirmLocation(String nodeId) => _confirmLandmark(nodeId);

  void _confirmLandmark(String nodeId) {
    _state = _state.copyWith(
      currentNodeId: nodeId,
      stepsSinceLast: 0,
      confidence: 1.0,
    );
  }

  /// Generate a spoken description of current position for "where am I?".
  String describeLocation() {
    final nodeId = _state.currentNodeId;
    if (nodeId == null || _map.nodes[nodeId] == null) {
      return "I'm not sure where you are right now. "
          "Try pointing your camera at a sign or room number.";
    }

    final node = _map.nodes[nodeId]!;
    if (_state.confidence >= 0.7) {
      return "I think you're near ${node.name}. Is that right?";
    } else if (_state.confidence >= 0.4) {
      return "I'm not too sure, but you might be near ${node.name}. "
          "About ${_state.stepsSinceLast} steps since I last confirmed. "
          "Can you see a sign?";
    } else {
      return "I've lost track a bit. You were near ${node.name}, "
          "but that was about ${_state.stepsSinceLast} steps ago. "
          "Try pointing your camera at a sign so I can reposition.";
    }
  }

  /// Update state for navigation (external callers).
  void updateState(NavState newState) => _state = newState;

  double _calculateHeading(double x, double y) {
    double heading = ((-1.0 * _atan2(y, x)) * (180.0 / 3.14159265) + 360) % 360;
    return heading;
  }

  double _atan2(double y, double x) {
    if (x > 0) return _arctan(y / x);
    if (x < 0 && y >= 0) return _arctan(y / x) + 3.14159265;
    if (x < 0 && y < 0) return _arctan(y / x) - 3.14159265;
    if (y > 0) return 3.14159265 / 2;
    if (y < 0) return -3.14159265 / 2;
    return 0;
  }

  double _arctan(double x) {
    // Approximation — sufficient for heading
    return x - (x * x * x) / 3 + (x * x * x * x * x) / 5;
  }

  // Mock: simulate being near the main entrance
  MapNode? _mockOcrMatch() {
    final entrance = _map.findByName('main entrance') ?? _map.findByName('entrance');
    if (entrance != null) {
      _confirmLandmark(entrance.id);
    }
    return entrance;
  }

  void dispose() {
    _compassSub?.cancel();
    _stepSub?.cancel();
    _textRecognizer.close();
  }
}
