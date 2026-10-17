import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:pedometer/pedometer.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';
import '../models/map_node.dart';
import '../models/nav_state.dart';
import 'map_loader.dart';
import 'app_config.dart';

import 'gps_service.dart';

/// Positioning engine: determines the user's current location node.
/// Strategy: GPS (macro) + OCR signs (micro landmarks) + 
/// step counting + compass heading for dead reckoning.
class PositioningService {
  final MapLoader _map;
  final GpsService? _gps;
  final TextRecognizer _textRecognizer = TextRecognizer();

  NavState _state = const NavState();
  double _heading = 0.0;
  int _lastStepCount = -1;

  StreamSubscription? _compassSub;
  StreamSubscription? _stepSub;
  Timer? _gpsTimer;

  NavState get state => _state;

  PositioningService(this._map, [this._gps]);

  /// Start listening to compass + pedometer + GPS.
  void start() {
    // Compass heading
    _compassSub = magnetometerEventStream().listen((event) {
      _heading = _calculateHeading(event.x, event.y);
      _state = _state.copyWith(headingDegrees: _heading);
    });

    // Poll GPS coordinates periodically
    if (_gps != null) {
      _gpsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        final pos = _gps?.currentPosition;
        if (pos != null) {
          _state = _state.copyWith(
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
        }
      });
    }

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

  /// Set a user-specified or visually-inferred location (e.g., "Point A", "bedroom").
  void setCustomLocation(String locationName) {
    final clean = locationName.trim();
    if (clean.isEmpty) return;

    // If it matches a known map node, link to that node directly
    final match = _map.findByName(clean);
    if (match != null) {
      _confirmLandmark(match.id);
    } else {
      _state = _state.copyWith(
        customLocationName: clean,
        confidence: 1.0,
        stepsSinceLast: 0,
        clearCurrentNode: true,
      );
    }
  }

  void _confirmLandmark(String nodeId) {
    _state = _state.copyWith(
      currentNodeId: nodeId,
      stepsSinceLast: 0,
      confidence: 1.0,
      clearCustomLocation: true,
    );
  }

  /// Generate a spoken description of current position for "where am I?".
  String describeLocation() {
    final nodeId = _state.currentNodeId;
    if (nodeId != null && _map.nodes[nodeId] != null) {
      final node = _map.nodes[nodeId]!;
      if (_state.confidence >= 0.7) {
        return "I think you're near ${node.name}. Is that right?";
      } else if (_state.confidence >= 0.4) {
        return "I'm not too sure, but you might be near ${node.name}. "
            "About ${_state.stepsSinceLast} steps since I last confirmed.";
      } else {
        return "I've lost track a bit. You were near ${node.name}, "
            "but that was about ${_state.stepsSinceLast} steps ago.";
      }
    }

    if (_state.customLocationName != null) {
      return "You are at ${_state.customLocationName}. "
          "You can ask what is in front of you, or tell me where you'd like to walk.";
    }

    return "I'm not sure where you are right now. "
        "Point your camera at a sign, or say 'I am at' followed by your location.";
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
    _gpsTimer?.cancel();
    _compassSub?.cancel();
    _stepSub?.cancel();
    _textRecognizer.close();
  }
}
