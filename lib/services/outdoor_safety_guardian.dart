import 'dart:async';
import 'dart:typed_data';
import 'camera_service.dart';
import 'gemini_service.dart';
import 'audio_priority_manager.dart';
import 'local_perception_service.dart';
import '../utils/scene_differ.dart';
import '../models/verbosity_level.dart';

/// Outdoor Environmental Awareness & Road Crossing Safety Guardian (Section 2.B).
/// Runs continuously alongside outdoor GPS navigation, observing curbs, vehicles,
/// pedestrian zebra crossings, signals, and obstacles with strict conservative safety rules.
class OutdoorSafetyGuardian {
  final CameraService _camera;
  final GeminiService _gemini;
  final AudioPriorityManager _audio;
  final LocalPerceptionService _localPerception;
  final SceneDiffer _sceneDiffer = SceneDiffer();

  bool _isActive = false;
  bool _isProcessing = false;
  Timer? _guardianTimer;
  DateTime? _lastSpokenObservationTime;

  OutdoorSafetyGuardian({
    required CameraService camera,
    required GeminiService gemini,
    required AudioPriorityManager audio,
    required LocalPerceptionService localPerception,
  })  : _camera = camera,
        _gemini = gemini,
        _audio = audio,
        _localPerception = localPerception;

  bool get isActive => _isActive;

  /// Start concurrent environmental observation during outdoor navigation.
  void start() {
    _isActive = true;
    _sceneDiffer.reset();
    _guardianTimer?.cancel();
    _guardianTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) => _evaluateOutdoorScene());
  }

  /// Stop environmental observation.
  void stop() {
    _isActive = false;
    _guardianTimer?.cancel();
    _guardianTimer = null;
    _sceneDiffer.reset();
  }

  Future<void> _evaluateOutdoorScene() async {
    if (!_isActive || _isProcessing || !_camera.isReady) return;
    if (_audio.isSpeaking) return;

    _isProcessing = true;
    try {
      final Uint8List? frame = await _camera.captureFrame();
      if (frame == null) return;

      // 1. Fast Local Perception (<30ms offline check for sudden path blockages)
      final localAlert = await _localPerception.analyzeFrame(frame);
      if (localAlert != null && _isActive) {
        await _audio.speak(
          text: localAlert.spokenWarning,
          priority: AudioPriority.urgentHazard,
        );
        return;
      }

      // 2. SceneDiffer check to avoid unnecessary cloud calls
      final hasChanged = await _sceneDiffer.hasSignificantChange(frame, thresholdPercent: 12.0);
      if (!hasChanged) return;

      final now = DateTime.now();
      if (_lastSpokenObservationTime != null &&
          now.difference(_lastSpokenObservationTime!).inSeconds < 4) {
        return;
      }

      // 3. Multimodal Outdoor Safety Evaluation
      const outdoorSafetyPrompt = '''
You are an outdoor sighted guide observing the environment in front of a blind pedestrian walking on a sidewalk.
Examine this camera image for key outdoor features:
1. Approaching vehicles, bicycles, or cars turning.
2. Curbs, drop-offs into roads, or sidewalk edge.
3. Pedestrian zebra crossings, tactile paving, or traffic lights.
4. Obstacles, posts, tree branches, or people directly in the walking line.

SAFETY RULES (STRICT):
- Never tell the user to cross the road or that it is safe to cross.
- If a pedestrian crossing or zebra marking is spotted: Say "Possible pedestrian crossing ahead. Stop before entering the road."
- If a vehicle is approaching: Say "Vehicle approaching ahead. Please pause."
- If a curb or drop-off is visible: Say "Curb edge ahead. Step down with care."
- If the path is clear: Reply with "CLEAR".
- Keep responses strictly under 10 words.
''';

      final observation = await _gemini.ask(
        question: outdoorSafetyPrompt,
        imageBytes: frame,
        verbosity: VerbosityLevel.brief,
      );

      final clean = observation.trim();
      if (clean.isNotEmpty &&
          !clean.toUpperCase().startsWith('CLEAR') &&
          !clean.toLowerCase().contains('clear') &&
          _isActive) {
        _lastSpokenObservationTime = DateTime.now();

        // Check if urgent (vehicles, road entries)
        final isUrgent = clean.toLowerCase().contains('stop') ||
            clean.toLowerCase().contains('vehicle') ||
            clean.toLowerCase().contains('curb');

        await _audio.speak(
          text: clean,
          priority: isUrgent ? AudioPriority.urgentHazard : AudioPriority.conversationalResponse,
        );
      }
    } catch (_) {
    } finally {
      _isProcessing = false;
    }
  }
}
