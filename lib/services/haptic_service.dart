import 'package:vibration/vibration.dart';

/// Handles haptic feedback.
/// Principle 6: one short pulse for confirmations, different single pulse while waiting.
class HapticService {
  static const int _confirmDuration = 60;  // ms – short confirm
  static const int _thinkingDuration = 30; // ms – lighter "thinking"

  /// Call when user tap is registered / action confirmed.
  static Future<void> confirm() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      Vibration.vibrate(duration: _confirmDuration);
    }
  }

  /// Call while waiting for AI response (thinking cue).
  static Future<void> thinking() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      Vibration.vibrate(duration: _thinkingDuration);
    }
  }
}
