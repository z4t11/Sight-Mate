import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/clew_route_models.dart';
import '../models/verbosity_level.dart';
import 'camera_service.dart';
import 'gemini_service.dart';
import 'clew_route_storage.dart';

/// Clew-inspired Route Recorder.
/// Records phone movement and spatial checkpoints hands-free using dead reckoning
/// (pedometer steps + magnetometer compass), supplemented by Gemini vision landmark detection.
class ClewRouteRecorder extends ChangeNotifier {
  final CameraService? _camera;
  final GeminiService? _gemini;

  bool _isRecording = false;
  String _startName = 'Start';
  String _destinationName = 'Destination';

  // Real-time tracking coordinates (local meters)
  double _currentX = 0.0;
  double _currentY = 0.0;
  double _currentHeading = 0.0;
  int _totalSteps = 0;
  double _totalDistanceMeters = 0.0;
  static const double _stepLengthMeters = 0.70;

  // Breadcrumbs and Keypoint accumulation
  final List<ClewCrumb> _crumbs = [];
  final List<ClewKeypoint> _keypoints = [];

  // Heading turn detection
  double _segmentStartHeading = 0.0;
  int _segmentStartStep = 0;
  double _lastTurnHeading = 0.0;

  // Gemini vision landmark scanning
  Timer? _visionScanTimer;
  String? _latestVisionLandmark;
  bool _isScanningVision = false;

  ClewRouteRecorder({
    CameraService? camera,
    GeminiService? gemini,
  })  : _camera = camera,
        _gemini = gemini;

  bool get isRecording => _isRecording;
  int get totalSteps => _totalSteps;
  double get totalDistanceMeters => _totalDistanceMeters;
  double get currentHeading => _currentHeading;
  int get crumbCount => _crumbs.length;
  int get keypointCount => _keypoints.length;
  double get segmentStartHeading => _segmentStartHeading;
  String? get latestVisionLandmark => _latestVisionLandmark;

  /// Start recording a new Clew route from [startName].
  void startRecording(String startName) {
    _isRecording = true;
    _startName = startName.trim().isEmpty ? 'Start' : startName.trim();
    _currentX = 0.0;
    _currentY = 0.0;
    _totalSteps = 0;
    _totalDistanceMeters = 0.0;
    _segmentStartStep = 0;
    _segmentStartHeading = _currentHeading;
    _lastTurnHeading = _currentHeading;
    _crumbs.clear();
    _keypoints.clear();
    _latestVisionLandmark = null;

    // Drop Initial Breadcrumb and Start Keypoint (Keypoint 0)
    final now = DateTime.now();
    _crumbs.add(ClewCrumb(
      x: 0.0,
      y: 0.0,
      heading: _currentHeading,
      stepCount: 0,
      timestamp: now,
      visualLandmark: '$_startName entrance',
    ));

    _keypoints.add(ClewKeypoint(
      index: 0,
      x: 0.0,
      y: 0.0,
      heading: _currentHeading,
      turnAngle: 0.0,
      cumulativeSteps: 0,
      cumulativeMeters: 0.0,
      instruction: 'Start at $_startName. Walk forward.',
      landmarkDescription: '$_startName entrance',
    ));

    _startVisionScanner();
    notifyListeners();
  }

  /// Update current compass heading from sensor.
  void updateHeading(double heading) {
    _currentHeading = heading;
    notifyListeners();
  }

  /// Handle incoming pedometer step delta (Hands-free dead reckoning!).
  void onStep(int delta) {
    if (!_isRecording || delta <= 0) return;

    final rad = _currentHeading * (math.pi / 180.0);
    final distanceDelta = delta * _stepLengthMeters;

    // Relative movement in local coordinates
    _currentX += distanceDelta * math.sin(rad);
    _currentY += distanceDelta * math.cos(rad);
    _totalSteps += delta;
    _totalDistanceMeters += distanceDelta;

    // Drop breadcrumb automatically
    _crumbs.add(ClewCrumb(
      x: _currentX,
      y: _currentY,
      heading: _currentHeading,
      stepCount: _totalSteps,
      timestamp: DateTime.now(),
      visualLandmark: _latestVisionLandmark,
    ));

    // Automatic turn detection (Clew-style keypoint extraction)
    final headingDelta = ((_currentHeading - _lastTurnHeading + 540) % 360) - 180;
    final stepsSinceTurn = _totalSteps - _segmentStartStep;

    // If user turned >= 35 degrees and sustained it for at least 3 steps
    if (headingDelta.abs() >= 35.0 && stepsSinceTurn >= 3) {
      _extractTurnKeypoint(headingDelta);
    }

    notifyListeners();
  }

  void _extractTurnKeypoint(double turnAngle) {
    final turnWord = turnAngle > 0 ? "right" : "left";
    final angleRound = turnAngle.abs().round();
    final stepsInPrevSegment = _totalSteps - _segmentStartStep;

    final keypoint = ClewKeypoint(
      index: _keypoints.length,
      x: _currentX,
      y: _currentY,
      heading: _currentHeading,
      turnAngle: turnAngle,
      cumulativeSteps: _totalSteps,
      cumulativeMeters: _totalDistanceMeters,
      instruction: 'Turn $turnWord (approx $angleRound°) and walk straight.',
      landmarkDescription: _latestVisionLandmark ?? 'Turn junction',
    );

    _keypoints.add(keypoint);
    _lastTurnHeading = _currentHeading;
    _segmentStartStep = _totalSteps;
    _segmentStartHeading = _currentHeading;
    debugPrint('[ClewRecorder] Auto-extracted turn keypoint #${keypoint.index}: Turn $turnWord $angleRound° after $stepsInPrevSegment steps');
  }

  /// Concurrently analyze camera frames with Gemini for supporting visual context.
  void _startVisionScanner() {
    _visionScanTimer?.cancel();
    _visionScanTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) async {
      if (!_isRecording || _isScanningVision || _camera == null || _gemini == null) return;
      if (!_camera!.isReady) return;

      _isScanningVision = true;
      try {
        final frame = await _camera!.captureFrame();
        if (frame != null && _isRecording) {
          final description = await _gemini!.ask(
            question: "In under 5 words, identify any prominent indoor landmark in front of you (e.g. 'door on left', 'water cooler', 'hallway corner', 'staircase') or say 'NONE'.",
            imageBytes: frame,
            verbosity: VerbosityLevel.brief,
          );

          if (description.isNotEmpty &&
              !description.toLowerCase().contains('none') &&
              !description.toLowerCase().contains('no response')) {
            _latestVisionLandmark = description.replaceAll(RegExp(r'[\.\n]'), '').trim();
            debugPrint('[ClewRecorder] Detected supporting visual landmark: $_latestVisionLandmark');
          }
        }
      } catch (e) {
        debugPrint('[ClewRecorder] Vision scan error: $e');
      } finally {
        _isScanningVision = false;
      }
    });
  }

  /// Finalize and save the route with [destinationName].
  Future<ClewRoute> finishAndSave(String destinationName) async {
    _isRecording = false;
    _visionScanTimer?.cancel();
    _destinationName = destinationName.trim().isEmpty ? 'Destination' : destinationName.trim();

    // Add final destination keypoint
    _keypoints.add(ClewKeypoint(
      index: _keypoints.length,
      x: _currentX,
      y: _currentY,
      heading: _currentHeading,
      turnAngle: 0.0,
      cumulativeSteps: _totalSteps,
      cumulativeMeters: _totalDistanceMeters,
      instruction: 'You have arrived at $_destinationName.',
      landmarkDescription: '$_destinationName doorway',
    ));

    final route = ClewRoute(
      id: 'clew_${DateTime.now().millisecondsSinceEpoch}',
      name: '$_startName to $_destinationName',
      startName: _startName,
      destinationName: _destinationName,
      createdAt: DateTime.now(),
      crumbs: List.unmodifiable(_crumbs),
      keypoints: List.unmodifiable(_keypoints),
      totalSteps: _totalSteps,
      totalDistanceMeters: _totalDistanceMeters,
    );

    await ClewRouteStorage.saveRoute(route);
    notifyListeners();
    return route;
  }

  void cancelRecording() {
    _isRecording = false;
    _visionScanTimer?.cancel();
    _crumbs.clear();
    _keypoints.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _visionScanTimer?.cancel();
    super.dispose();
  }
}
