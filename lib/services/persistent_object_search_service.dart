import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/object_search_models.dart';
import 'audio_priority_manager.dart';
import 'camera_service.dart';
import 'gemini_service.dart';
import 'haptic_service.dart';
import 'local_perception_service.dart';
import 'positioning_service.dart';

/// Persistent 360° Object Search Service with Natural Voice Guidance.
///
/// Features:
/// 1. If object is already in view, immediately describes its location (no robotic preamble).
/// 2. If search takes time, acknowledges briefly with "Sure, I'll look."
/// 3. If object is not visible, guides the user with progressive, conversational scan cues.
/// 4. Once found, describes direction and distance, and stops repeating search announcements.
/// 5. Strictly prioritises safety hazard alerts over ordinary descriptions.
class PersistentObjectSearchService extends ChangeNotifier {
  final CameraService _camera;
  final GeminiService _gemini;
  final AudioPriorityManager _audio;
  final PositioningService _positioning;
  final LocalPerceptionService _localPerception;

  ObjectSearchState _state = ObjectSearchState.idle;
  String? _activeTarget;
  String? _lastAnnouncement;
  String _scanDirection = 'left';

  int _sessionId = 0;
  bool _isProcessingFrame = false;
  Timer? _loopTimer;
  DateTime? _lastSpokenGuidanceTime;
  int _consecutiveNotFoundFrames = 0;
  int _framesAnalyzed = 0;
  double _startHeading = 0.0;

  ObjectSearchState get state => _state;
  String? get activeTarget => _activeTarget;
  String? get lastAnnouncement => _lastAnnouncement;
  String get scanDirection => _scanDirection;
  bool get isSearching =>
      _state == ObjectSearchState.searching || _state == ObjectSearchState.guiding;

  PersistentObjectSearchService({
    required CameraService camera,
    required GeminiService gemini,
    required AudioPriorityManager audio,
    required PositioningService positioning,
    required LocalPerceptionService localPerception,
  })  : _camera = camera,
        _gemini = gemini,
        _audio = audio,
        _positioning = positioning,
        _localPerception = localPerception;

  /// Begin a persistent search for [targetObject] using natural conversational pacing.
  Future<void> startSearch(String targetObject) async {
    final clean = targetObject.trim();
    if (clean.isEmpty) return;

    _sessionId++;
    final currentSession = _sessionId;

    _activeTarget = clean;
    _state = ObjectSearchState.searching;
    _consecutiveNotFoundFrames = 0;
    _framesAnalyzed = 0;
    _scanDirection = 'left';
    _startHeading = _positioning.currentHeading;
    _lastSpokenGuidanceTime = DateTime.now();

    _lastAnnouncement = 'Looking for $clean…';
    notifyListeners();

    // Start with prompt acknowledgment
    final startNotice = 'Looking for $clean…';
    _lastAnnouncement = startNotice;
    notifyListeners();
    _audio.speak(
      text: "Looking for the $clean.",
      priority: AudioPriority.conversationalResponse,
    );

    // Inspect current camera frame with Gemini Live stream
    try {
      final frame = await _camera.captureFrame();
      if (frame != null && _sessionId == currentSession) {
        // Continuous safety check runs in background without blocking vision query
        _localPerception.analyzeFrame(frame).then((localAlert) {
          if (localAlert != null && localAlert.confidence >= 0.7 && _sessionId == currentSession) {
            _audio.speak(
              text: "${localAlert.spokenWarning} Stand still while scanning.",
              priority: AudioPriority.urgentHazard,
            );
          }
        });

        final sentenceBuffer = StringBuffer();
        bool firstSentenceSpoken = false;

        final result = await _gemini.locateObjectLive(
          targetObject: clean,
          imageBytes: frame,
          onStreamChunk: (chunk) {
            sentenceBuffer.write(chunk);
            final full = sentenceBuffer.toString();
            if (!firstSentenceSpoken && (full.contains('.') || full.contains('!') || full.contains('?'))) {
              firstSentenceSpoken = true;
              final firstSentence = full.split(RegExp(r'[.!?]')).first.trim();
              if (firstSentence.isNotEmpty && _sessionId == currentSession && !_audio.isSpeaking) {
                _lastAnnouncement = firstSentence;
                notifyListeners();
                _audio.speak(
                  text: firstSentence,
                  priority: AudioPriority.conversationalResponse,
                );
              }
            }
          },
        );

        if (_sessionId == currentSession && _state != ObjectSearchState.idle) {
          if (result.status == TargetDetectionStatus.found) {
            await _handleTargetFound(result, currentSession);
            return;
          } else if (result.status == TargetDetectionStatus.uncertain) {
            await _handleTargetUncertain(result, currentSession);
          } else {
            if (!firstSentenceSpoken && result.description.isNotEmpty && !result.description.contains('Unable to analyze')) {
              _lastAnnouncement = result.description;
              notifyListeners();
              await _audio.speak(
                text: result.description,
                priority: AudioPriority.conversationalResponse,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ObjectSearch] Initial frame error: $e');
    }

    // Start recurring scan loop for subsequent frames if not already found
    if (_sessionId == currentSession && _state != ObjectSearchState.found) {
      _startSearchLoop(currentSession);
    }
  }

  /// Switch the active target to [newTarget] immediately without terminating the pipeline.
  Future<void> switchTarget(String newTarget) async {
    final clean = newTarget.trim();
    if (clean.isEmpty) return;

    if (clean.toLowerCase() == _activeTarget?.toLowerCase() &&
        _state == ObjectSearchState.found) {
      await resumeSearch();
      return;
    }

    _sessionId++;
    final currentSession = _sessionId;

    _activeTarget = clean;
    _state = ObjectSearchState.searching;
    _consecutiveNotFoundFrames = 0;
    _framesAnalyzed = 0;
    _lastSpokenGuidanceTime = DateTime.now();

    final switchMsg = "Looking for the $clean now.";
    _lastAnnouncement = switchMsg;
    notifyListeners();

    await _audio.speak(
      text: switchMsg,
      priority: AudioPriority.conversationalResponse,
    );

    _startSearchLoop(currentSession);
  }

  /// Resume or keep searching for the active target if paused or already found.
  Future<void> resumeSearch() async {
    if (_activeTarget == null) {
      await _audio.speak(
        text: "What would you like me to find?",
        priority: AudioPriority.conversationalResponse,
      );
      return;
    }

    _sessionId++;
    final currentSession = _sessionId;

    _state = ObjectSearchState.searching;
    _consecutiveNotFoundFrames = 0;
    _lastSpokenGuidanceTime = DateTime.now();

    final resumeMsg =
        "Checking again for the $_activeTarget. Slowly turn your phone.";
    _lastAnnouncement = resumeMsg;
    notifyListeners();

    await _audio.speak(
      text: resumeMsg,
      priority: AudioPriority.conversationalResponse,
    );

    _startSearchLoop(currentSession);
  }

  /// Manually steer the scan direction (e.g., user says "turn left" or "turn right").
  Future<void> setScanDirection(String direction) async {
    final dir = direction.toLowerCase().contains('right') ? 'right' : 'left';
    _scanDirection = dir;
    _lastSpokenGuidanceTime = DateTime.now();

    final msg = "Scanning $dir.";
    _lastAnnouncement = msg;
    notifyListeners();

    await _audio.speak(
      text: msg,
      priority: AudioPriority.conversationalResponse,
    );
  }

  /// Explicitly stop the active object search ("stop searching", "cancel", Volume Down).
  void stopSearch({bool speakNotice = true}) {
    _sessionId++;
    _state = ObjectSearchState.idle;
    _loopTimer?.cancel();
    _loopTimer = null;
    _isProcessingFrame = false;

    _lastAnnouncement = "Stopped.";
    notifyListeners();

    if (speakNotice) {
      _audio.speak(
        text: "Stopped.",
        priority: AudioPriority.systemNotice,
      );
    }
  }

  /// Master loop running every 1.8 seconds.
  void _startSearchLoop(int session) {
    _loopTimer?.cancel();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (_sessionId != session || _state == ObjectSearchState.idle) {
        _loopTimer?.cancel();
        return;
      }
      if (_state == ObjectSearchState.found) {
        // Target found: pause frame analysis to prevent voice spam
        return;
      }
      _processNextFrame(session);
    });
  }

  Future<void> _processNextFrame(int session) async {
    if (_isProcessingFrame) return;
    if (_sessionId != session) return;
    if (!_camera.isReady) return;
    if (_audio.isSpeaking) return;

    _isProcessingFrame = true;

    try {
      // 1. Capture current frame from camera (native compact JPEG)
      final frame = await _camera.captureFrame();
      if (frame == null || _sessionId != session) {
        _isProcessingFrame = false;
        return;
      }

      _framesAnalyzed++;

      // 2. Safety check runs in background without blocking vision stream
      _localPerception.analyzeFrame(frame).then((localAlert) {
        if (localAlert != null && localAlert.confidence >= 0.7 && _sessionId == session) {
          _audio.speak(
            text: "${localAlert.spokenWarning} Stand still while scanning.",
            priority: AudioPriority.urgentHazard,
          );
        }
      });

      // 3. Stream Gemini Live multimodal observation
      final sentenceBuffer = StringBuffer();
      bool firstSentenceSpoken = false;

      final result = await _gemini.locateObjectLive(
        targetObject: _activeTarget!,
        imageBytes: frame,
        onStreamChunk: (chunk) {
          sentenceBuffer.write(chunk);
          final full = sentenceBuffer.toString();
          if (!firstSentenceSpoken && (full.contains('.') || full.contains('!') || full.contains('?'))) {
            firstSentenceSpoken = true;
            final firstSentence = full.split(RegExp(r'[.!?]')).first.trim();
            if (firstSentence.isNotEmpty && _sessionId == session && !_audio.isSpeaking) {
              _lastAnnouncement = firstSentence;
              notifyListeners();
              _audio.speak(
                text: firstSentence,
                priority: AudioPriority.conversationalResponse,
              );
            }
          }
        },
      );

      // Verify session hasn't been cancelled or replaced during async call
      if (_sessionId != session || _state == ObjectSearchState.idle) {
        _isProcessingFrame = false;
        return;
      }

      // 4. Handle detection results
      if (result.status == TargetDetectionStatus.found) {
        await _handleTargetFound(result, session);
      } else if (result.status == TargetDetectionStatus.uncertain) {
        await _handleTargetUncertain(result, session);
      } else {
        if (!firstSentenceSpoken) {
          await _handleTargetNotFound(session, liveGuidance: result.description);
        } else {
          _state = ObjectSearchState.guiding;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[ObjectSearch] Error processing frame: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _handleTargetFound(ObjectSearchResult result, int session) async {
    _state = ObjectSearchState.found;
    _consecutiveNotFoundFrames = 0;
    await HapticService.confirm();

    String announcement;
    if (result.description.isNotEmpty && !result.description.contains('Unable to analyze')) {
      announcement = result.description;
    } else {
      final dir = result.direction;
      final dist = result.distance != 'unknown' ? ', ${result.distance}' : '';
      announcement = "Found the $_activeTarget$dist. ${dir.turnInstruction}";
    }

    _lastAnnouncement = announcement;
    notifyListeners();

    await _audio.speak(
      text: announcement,
      priority: AudioPriority.conversationalResponse,
      interruptSame: true,
    );
  }

  Future<void> _handleTargetUncertain(
      ObjectSearchResult result, int session) async {
    _state = ObjectSearchState.guiding;
    notifyListeners();

    final now = DateTime.now();
    if (_lastSpokenGuidanceTime != null &&
        now.difference(_lastSpokenGuidanceTime!) < const Duration(milliseconds: 3500)) {
      return;
    }

    _lastSpokenGuidanceTime = now;
    final hint = result.direction != ObjectDirection.unknown
        ? "near the ${result.direction.label}"
        : "in view";
    final msg =
        "I might see a possible $_activeTarget $hint. Turn your phone a little closer to confirm.";

    _lastAnnouncement = msg;
    notifyListeners();

    await _audio.speak(
      text: msg,
      priority: AudioPriority.conversationalResponse,
    );
  }

  Future<void> _handleTargetNotFound(int session, {String? liveGuidance}) async {
    _state = ObjectSearchState.guiding;
    _consecutiveNotFoundFrames++;
    notifyListeners();

    final now = DateTime.now();
    // Paced guidance interval
    if (_lastSpokenGuidanceTime != null &&
        now.difference(_lastSpokenGuidanceTime!) < const Duration(milliseconds: 3000)) {
      return;
    }

    _lastSpokenGuidanceTime = now;

    final curHeading = _positioning.currentHeading;
    final diff = ((curHeading - _startHeading).abs() % 360).round();
    debugPrint('[ObjectSearch] Frame $_framesAnalyzed for $_activeTarget (heading: ${curHeading.toStringAsFixed(0)}°, rot: $diff°)');

    String guidance;
    if (liveGuidance != null &&
        liveGuidance.isNotEmpty &&
        !liveGuidance.contains('Object not visible') &&
        !liveGuidance.contains('Unable to analyze')) {
      guidance = liveGuidance;
    } else {
      final count = _consecutiveNotFoundFrames;
      if (count <= 2) {
        guidance = "Still looking. Slowly turn to your $_scanDirection.";
      } else if (count <= 5) {
        guidance = "Keep turning slowly, looking for the $_activeTarget.";
      } else {
        guidance = "Keep turning slowly at chest height.";
      }
    }

    _lastAnnouncement = guidance;
    notifyListeners();

    await _audio.speak(
      text: guidance,
      priority: AudioPriority.conversationalResponse,
    );
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _loopTimer = null;
    super.dispose();
  }
}
