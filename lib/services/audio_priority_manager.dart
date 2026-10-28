import 'dart:async';
import 'tts_service.dart';
import 'haptic_service.dart';

/// Priority levels for spoken audio feedback in Sight Mate.
enum AudioPriority {
  /// Priority 0: Immediate physical danger (drop-offs, collisions, steps). Preempts all ongoing speech.
  urgentHazard(0),

  /// Priority 1: Time-sensitive navigation instructions (turn now, prepare to turn).
  navigationInstruction(1),

  /// Priority 2: Conversational AI vision descriptions and answers to user queries.
  conversationalResponse(2),

  /// Priority 3: Non-urgent system status, confirmations, and settings announcements.
  systemNotice(3);

  final int level;
  const AudioPriority(this.level);

  bool hasHigherOrEqualPriorityThan(AudioPriority other) => level <= other.level;
}

/// A request to speak text with an assigned priority.
class AudioRequest {
  final String text;
  final AudioPriority priority;
  final DateTime timestamp;
  final bool interruptLower;
  final void Function()? onComplete;

  AudioRequest({
    required this.text,
    required this.priority,
    this.interruptLower = true,
    this.onComplete,
  }) : timestamp = DateTime.now();
}

/// Central audio dispatcher ensuring safety-critical hazard alerts
/// immediately interrupt routine conversational descriptions or route guidance.
class AudioPriorityManager {
  final TtsService _tts;
  AudioPriority? _currentSpeakingPriority;
  String? _lastSpokenHazardText;
  DateTime? _lastHazardSpokenTime;
  String? _lastSpokenText;
  DateTime? _lastSpokenTime;

  // Hazard cooldown to prevent repetitive ear fatigue (Section 4)
  static const Duration _hazardDuplicateCooldown = Duration(milliseconds: 3500);

  AudioPriorityManager(this._tts);

  AudioPriority? get currentSpeakingPriority => _currentSpeakingPriority;
  bool get isSpeaking => _tts.isSpeaking;

  /// Speak [text] at [priority]. If an urgent hazard arrives while a lower priority
  /// item is speaking, the lower priority speech is immediately cut off.
  Future<bool> speak({
    required String text,
    required AudioPriority priority,
    bool interruptSame = false,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return false;

    final now = DateTime.now();

    // 1. General speech deduplication: suppress duplicate speech within 2.5s (Req 6)
    if (_lastSpokenText == cleanText &&
        _lastSpokenTime != null &&
        now.difference(_lastSpokenTime!) < const Duration(milliseconds: 2500)) {
      return false;
    }

    // 2. Hazard deduplication and temporal cooldown
    if (priority == AudioPriority.urgentHazard) {
      if (_lastSpokenHazardText == cleanText &&
          _lastHazardSpokenTime != null &&
          now.difference(_lastHazardSpokenTime!) < _hazardDuplicateCooldown) {
        return false;
      }
      _lastSpokenHazardText = cleanText;
      _lastHazardSpokenTime = now;
    }

    // 3. Priority Preemption Check (Req 7):
    // Urgent Hazard (0) always preempts Navigation (1), Conversational (2), System (3).
    // Navigation (1) preempts Conversational (2) and System (3).
    // An equal or lower priority does not clobber ongoing speech unless interruptSame is true.
    if (_tts.isSpeaking && _currentSpeakingPriority != null) {
      final currentLevel = _currentSpeakingPriority!.level;
      final newLevel = priority.level;

      if (newLevel < currentLevel) {
        await _tts.stop();
      } else if (newLevel == currentLevel && interruptSame) {
        await _tts.stop();
      } else {
        return false;
      }
    }

    _lastSpokenText = cleanText;
    _lastSpokenTime = now;
    _currentSpeakingPriority = priority;

    try {
      if (priority == AudioPriority.urgentHazard) {
        await HapticService.hazardWarning();
      } else if (priority == AudioPriority.navigationInstruction) {
        await HapticService.confirm();
      }

      await _tts.speak(cleanText);
      return true;
    } finally {
      if (_currentSpeakingPriority == priority) {
        _currentSpeakingPriority = null;
      }
    }
  }

  /// Emergency silence: immediately cuts all speech and clears active priority.
  Future<void> stopAll() async {
    _currentSpeakingPriority = null;
    await _tts.stop();
  }
}
