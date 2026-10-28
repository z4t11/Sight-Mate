import 'dart:async';
import 'dart:typed_data';
import 'camera_service.dart';
import 'gemini_service.dart';
import 'audio_priority_manager.dart';
import '../utils/scene_differ.dart';
import '../models/verbosity_level.dart';

/// Manages a continuous, hands-free Gemini Live multimodal observation session (Section 3).
/// Continues observing the camera after an instruction is issued, automatically processing
/// follow-up observations without requiring the user to tap the screen again.
class LiveVisionSession {
  final CameraService _camera;
  final GeminiService _gemini;
  final AudioPriorityManager _audio;
  final SceneDiffer _sceneDiffer = SceneDiffer();

  bool _isActive = false;
  bool _isEvaluating = false;
  String _activeGoal = '';
  Timer? _observationTimer;
  DateTime? _lastEvaluationTime;

  // Adaptive sampling interval (2.5 seconds balanced for battery, API quota, and responsiveness)
  static const Duration _samplingInterval = Duration(milliseconds: 2500);

  LiveVisionSession({
    required CameraService camera,
    required GeminiService gemini,
    required AudioPriorityManager audio,
  })  : _camera = camera,
        _gemini = gemini,
        _audio = audio;

  bool get isActive => _isActive;
  String get activeGoal => _activeGoal;

  /// Start a continuous live assistance session for [goal] (e.g. "Navigating to stairs" or "Room exploration").
  void startSession(String goal) {
    _isActive = true;
    _activeGoal = goal;
    _sceneDiffer.reset();

    _observationTimer?.cancel();
    _observationTimer = Timer.periodic(_samplingInterval, (_) => _evaluateFollowUpObservation());
  }

  /// Update the live target/goal as the user progresses or asks a new question.
  void updateGoal(String newGoal) {
    _activeGoal = newGoal;
  }

  /// Perform hands-free follow-up evaluation on the latest camera frame with backpressure.
  Future<void> _evaluateFollowUpObservation() async {
    // Backpressure: drop evaluation if previous AI call is still in flight or camera not ready
    if (!_isActive || _isEvaluating || !_camera.isReady) return;

    // Do not talk over the user or interrupt high-priority navigation turns
    if (_audio.isSpeaking) return;

    _isEvaluating = true;
    try {
      final Uint8List? frame = await _camera.captureFrame();
      if (frame == null) return;

      // Scene Differencing: skip Gemini API call if user hasn't moved / scene hasn't changed
      final hasChanged = await _sceneDiffer.hasSignificantChange(frame, thresholdPercent: 12.0);
      if (!hasChanged) return;

      final now = DateTime.now();
      if (_lastEvaluationTime != null && now.difference(_lastEvaluationTime!).inSeconds < 3) {
        return; // Minimum 3s spacing between conversational follow-ups
      }

      final prompt = "Current user goal: '$_activeGoal'. "
          "Evaluate what changed in front of the user. "
          "If the path is clear or user is on track, reply with 'CLEAR'. "
          "Otherwise, give a concise 1-sentence actionable observation.";

      final response = await _gemini.ask(
        question: prompt,
        imageBytes: frame,
        verbosity: VerbosityLevel.normal,
      );

      final clean = response.trim();
      if (clean.isNotEmpty &&
          !clean.toUpperCase().startsWith('CLEAR') &&
          !clean.toLowerCase().contains('no change') &&
          _isActive) {
        _lastEvaluationTime = DateTime.now();
        await _audio.speak(
          text: clean,
          priority: AudioPriority.conversationalResponse,
        );
      }
    } catch (_) {
      // Graceful error tolerance: network drop does not crash the session
    } finally {
      _isEvaluating = false;
    }
  }

  /// Stop the continuous session and release timers.
  void stopSession() {
    _isActive = false;
    _activeGoal = '';
    _observationTimer?.cancel();
    _observationTimer = null;
    _sceneDiffer.reset();
  }
}
