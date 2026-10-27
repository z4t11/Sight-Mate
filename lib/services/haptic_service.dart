import 'package:vibration/vibration.dart';

/// Handles haptic feedback across all modes.
/// Principle 6: distinct tactile cues for confirmation, thinking, hazard alerts, and emergency SOS.
class HapticService {
  static const int _confirmDuration = 60; // ms – short confirm
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

  /// Short double buzz when voice is not recognized or an action fails.
  static Future<void> error() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      final hasCustom = await Vibration.hasCustomVibrationsSupport();
      if (hasCustom) {
        Vibration.vibrate(pattern: [0, 80, 60, 80]);
      } else {
        Vibration.vibrate(duration: 180);
      }
    }
  }

  /// Distinct double buzz for safety hazard detection (stairs down, drop-offs, low overhangs).
  static Future<void> hazardWarning() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      final hasCustom = await Vibration.hasCustomVibrationsSupport();
      if (hasCustom) {
        Vibration.vibrate(pattern: [0, 120, 70, 150]);
      } else {
        Vibration.vibrate(duration: 250);
      }
    }
  }

  /// Urgent pulsating SOS pattern for emergency beacon.
  static Future<void> emergencyAlert() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      final hasCustom = await Vibration.hasCustomVibrationsSupport();
      if (hasCustom) {
        Vibration.vibrate(pattern: [0, 180, 90, 180, 90, 350]);
      } else {
        Vibration.vibrate(duration: 500);
      }
    }
  }
}
