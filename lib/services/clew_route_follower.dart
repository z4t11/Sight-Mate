import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/clew_route_models.dart';
import 'camera_service.dart';
import 'gemini_service.dart';
import 'audio_priority_manager.dart';
import 'local_perception_service.dart';
import '../models/verbosity_level.dart';

/// Clew-inspired Indoor Route Follower and Retracer.
///
/// Features:
/// 1. Hands-free keypoint progression based on motion tracking (no tapping required).
/// 2. Heading deviation detection with corrective voice guidance ("Veering left, adjust right").
/// 3. Approaching turn warnings (10 steps / 3 steps before).
/// 4. Supporting Gemini vision for visual landmark recognition and obstacle awareness.
/// 5. Observation deduplication (does not repeat unchanged visual descriptions).
class ClewRouteFollower extends ChangeNotifier {
  final CameraService _camera;
  final GeminiService _gemini;
  final AudioPriorityManager _audio;
  final LocalPerceptionService _localPerception;

  ClewRoute? _activeRoute;
  int _currentKeypointIndex = 0;
  bool _isNavigating = false;

  // Real-time tracking in route coordinates
  double _currentX = 0.0;
  double _currentY = 0.0;
  double _currentHeading = 0.0;
  int _stepsTakenInSegment = 0;
  int _totalStepsTaken = 0;
  static const double _stepLengthMeters = 0.70;

  int get totalStepsTaken => _totalStepsTaken;

  bool _approachingWarningSpoken = false;
  DateTime? _lastCorrectionTime;
  String? _lastSpokenVisualObservation;

  Timer? _visionLoopTimer;
  bool _isEvaluatingVision = false;

  ClewRouteFollower({
    required CameraService camera,
    required GeminiService gemini,
    required AudioPriorityManager audio,
    required LocalPerceptionService localPerception,
  })  : _camera = camera,
        _gemini = gemini,
        _audio = audio,
        _localPerception = localPerception;

  bool get isNavigating => _isNavigating;
  ClewRoute? get activeRoute => _activeRoute;
  int get currentKeypointIndex => _currentKeypointIndex;
  ClewKeypoint? get currentTargetKeypoint {
    if (_activeRoute == null || _currentKeypointIndex >= _activeRoute!.keypoints.length) {
      return null;
    }
    return _activeRoute!.keypoints[_currentKeypointIndex];
  }

  /// Start retracing [route] (either forward or return).
  Future<String> startRoute(ClewRoute route) async {
    _activeRoute = route;
    _isNavigating = true;
    _currentKeypointIndex = 0;
    _currentX = 0.0;
    _currentY = 0.0;
    _stepsTakenInSegment = 0;
    _totalStepsTaken = 0;
    _approachingWarningSpoken = false;
    _lastCorrectionTime = null;
    _lastSpokenVisualObservation = null;

    final firstKeypoint = route.keypoints.first;
    final initialInstruction = firstKeypoint.instruction;

    await _audio.speak(
      text: initialInstruction,
      priority: AudioPriority.navigationInstruction,
    );

    _startVisionObservationLoop();
    notifyListeners();
    return initialInstruction;
  }

  /// Update current compass heading from sensor.
  void updateHeading(double heading) {
    _currentHeading = heading;
    if (_isNavigating) {
      _checkHeadingDeviation();
    }
  }

  /// Pedometer step delta listener.
  /// Automatically advances keypoints when reached (No screen tapping needed!).
  void onStep(int delta) async {
    if (!_isNavigating || _activeRoute == null || delta <= 0) return;

    final rad = _currentHeading * (math.pi / 180.0);
    final distanceDelta = delta * _stepLengthMeters;

    _currentX += distanceDelta * math.sin(rad);
    _currentY += distanceDelta * math.cos(rad);
    _stepsTakenInSegment += delta;
    _totalStepsTaken += delta;

    final target = currentTargetKeypoint;
    if (target == null) return;

    // Calculate distance to target keypoint
    final dx = target.x - _currentX;
    final dy = target.y - _currentY;
    final distToKeypoint = math.sqrt(dx * dx + dy * dy);

    // 1. Approaching Keypoint Warning (3-4 steps / 2.5m away)
    if (distToKeypoint <= 2.8 && distToKeypoint > 1.2 && !_approachingWarningSpoken) {
      _approachingWarningSpoken = true;
      final nextIdx = _currentKeypointIndex + 1;
      if (nextIdx < _activeRoute!.keypoints.length) {
        final nextTarget = _activeRoute!.keypoints[nextIdx];
        final turnWord = nextTarget.turnAngle > 20 ? "turn right" : (nextTarget.turnAngle < -20 ? "turn left" : "walk straight");
        final msg = "In about 3 steps, prepare to $turnWord.";
        await _audio.speak(
          text: msg,
          priority: AudioPriority.navigationInstruction,
        );
      }
    }

    // 2. Keypoint Reached! Advance hands-free without tapping
    if (distToKeypoint <= 1.5 || (_stepsTakenInSegment >= (target.cumulativeSteps - (_currentKeypointIndex > 0 ? _activeRoute!.keypoints[_currentKeypointIndex - 1].cumulativeSteps : 0)))) {
      await _advanceToNextKeypoint();
    }

    notifyListeners();
  }

  Future<void> _advanceToNextKeypoint() async {
    _currentKeypointIndex++;
    _stepsTakenInSegment = 0;
    _approachingWarningSpoken = false;

    // Check if terminal destination reached
    if (_currentKeypointIndex >= _activeRoute!.keypoints.length) {
      final dest = _activeRoute!.destinationName;
      stopRoute();
      final arrivalMsg = "You have arrived at $dest. Indoor route complete.";
      await _audio.speak(
        text: arrivalMsg,
        priority: AudioPriority.navigationInstruction,
      );
      return;
    }

    final keypoint = _activeRoute!.keypoints[_currentKeypointIndex];
    await _audio.speak(
      text: keypoint.instruction,
      priority: AudioPriority.navigationInstruction,
    );
  }

  /// Detect course deviation and provide corrective voice guidance.
  void _checkHeadingDeviation() async {
    final target = currentTargetKeypoint;
    if (target == null) return;

    final now = DateTime.now();
    // Throttle deviation speech to once every 4 seconds to prevent voice spam
    if (_lastCorrectionTime != null && now.difference(_lastCorrectionTime!).inSeconds < 4) {
      return;
    }

    // Calculate heading error between current phone orientation and target orientation
    final headingError = ((target.heading - _currentHeading + 540) % 360) - 180;

    if (headingError.abs() >= 40.0) {
      _lastCorrectionTime = now;
      String correction;
      if (headingError > 0) {
        correction = "Veering right. Turn slightly to your left.";
      } else {
        correction = "Veering left. Turn slightly to your right.";
      }

      await _audio.speak(
        text: correction,
        priority: AudioPriority.navigationInstruction,
      );
    }
  }

  /// Concurrently analyze camera frames with Gemini Vision for landmark verification.
  /// Deduplicates observations so the app doesn't repeat identical descriptions.
  void _startVisionObservationLoop() {
    _visionLoopTimer?.cancel();
    _visionLoopTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) async {
      if (!_isNavigating || _isEvaluatingVision || !_camera.isReady) return;

      _isEvaluatingVision = true;
      try {
        final frame = await _camera.captureFrame();
        if (frame == null || !_isNavigating) return;

        // 1. Instant Local Hazard Perception
        final hazard = await _localPerception.analyzeFrame(frame);
        if (hazard != null && hazard.confidence >= 0.7) {
          await _audio.speak(
            text: hazard.spokenWarning,
            priority: AudioPriority.urgentHazard,
          );
        }

        // 2. Supporting Gemini Vision Landmark Recognition
        final target = currentTargetKeypoint;
        final expected = target?.landmarkDescription;

        if (expected != null && expected.isNotEmpty) {
          final prompt = 'Is the landmark "$expected" visible in this view? In under 8 words, answer: "VISIBLE: [brief detail]" or "NONE".';
          final result = await _gemini.ask(
            question: prompt,
            imageBytes: frame,
            verbosity: VerbosityLevel.brief,
          );

          if (result.toUpperCase().contains('VISIBLE:') && !result.toLowerCase().contains('none')) {
            final cleanDesc = result.replaceFirst(RegExp(r'VISIBLE:\s*', caseSensitive: false), '').trim();

            // Avoid repeating identical visual observations
            if (cleanDesc != _lastSpokenVisualObservation && cleanDesc.isNotEmpty) {
              _lastSpokenVisualObservation = cleanDesc;
              await _audio.speak(
                text: "Landmark spotted: $cleanDesc.",
                priority: AudioPriority.conversationalResponse,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[ClewFollower] Vision evaluation error: $e');
      } finally {
        _isEvaluatingVision = false;
      }
    });
  }

  /// Stop current active route.
  void stopRoute() {
    _isNavigating = false;
    _activeRoute = null;
    _visionLoopTimer?.cancel();
    _visionLoopTimer = null;
    _currentKeypointIndex = 0;
    _lastSpokenVisualObservation = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopRoute();
    super.dispose();
  }
}
