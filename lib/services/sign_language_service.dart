import 'package:flutter_hand_gesture/flutter_hand_gesture.dart';

/// Offline Sign-Language-to-Voice translator for non-verbal / deaf-mute communication.
/// Translates recognized hand gestures into natural spoken English for a blind listener.
class SignLanguageService {
  GestureType? _lastSpokenGesture;
  DateTime _lastSpokenTime = DateTime.fromMillisecondsSinceEpoch(0);
  int _mockIndex = 0;

  /// Minimum duration to wait before repeating the exact same gesture (prevents spamming).
  static const Duration _repeatCooldown = Duration(milliseconds: 2500);

  /// Human-friendly spoken translations for standard gestures.
  static const Map<GestureType, String> _signTranslations = {
    GestureType.openPalm: "Hello, I am here.",
    GestureType.thumbsUp: "Yes, I agree.",
    GestureType.thumbsDown: "No, I disagree.",
    GestureType.okSign: "Everything is okay.",
    GestureType.peace: "Peace, or please wait two minutes.",
    GestureType.pointing: "Look straight ahead in front of you.",
    GestureType.fist: "Please help me.",
    GestureType.callMe: "Can you call someone for me?",
    GestureType.rockSign: "I appreciate you.",
    GestureType.vulcanSalute: "Goodbye, have a good day.",
  };

  /// Translate a detected gesture to a spoken sentence.
  /// Returns null if the gesture is unknown, low confidence, or still on cooldown.
  String? translateGesture(GestureType type, {double confidence = 1.0}) {
    if (type == GestureType.unknown || confidence < 0.65) {
      return null;
    }

    final now = DateTime.now();
    final isSameGesture = _lastSpokenGesture == type;
    final timeSinceLast = now.difference(_lastSpokenTime);

    // Debounce repeated gestures
    if (isSameGesture && timeSinceLast < _repeatCooldown) {
      return null;
    }

    final phrase = _signTranslations[type];
    if (phrase != null) {
      _lastSpokenGesture = type;
      _lastSpokenTime = now;
      return phrase;
    }

    return null;
  }

  /// Reset the debounce state (e.g. when hand leaves frame).
  void resetDebounce() {
    _lastSpokenGesture = null;
  }

  /// Returns sample signs for offline simulation or testing.
  String getNextMockTranslation() {
    final list = _signTranslations.values.toList();
    final item = list[_mockIndex % list.length];
    _mockIndex++;
    return item;
  }

  /// List of supported gestures with their descriptions.
  Map<String, String> get supportedSignDescriptions => {
        "🖐 Open Palm": "Hello, I am here",
        "👍 Thumbs Up": "Yes, I agree",
        "👎 Thumbs Down": "No, I disagree",
        "👌 OK Sign": "Everything is okay",
        "✌️ Peace": "Please wait / Peace",
        "👆 Pointing": "Look straight ahead",
        "✊ Fist": "Please help me",
        "🤙 Call Me": "Please call someone for me",
        "🤘 Rock": "I appreciate you",
      };
}
