import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

/// Wraps flutter_tts.
/// Principle 2: silent by default.
/// Principle 5: "stop" cuts speech instantly.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;
  Completer<void>? _completer;

  // Normal speech profile
  static const double _normalRate   = 0.52;
  static const double _normalPitch  = 1.0;
  static const double _normalVolume = 1.0;

  // Movie Mode: slightly faster + softer
  static const double _movieRate    = 0.58;
  static const double _moviePitch   = 0.95;
  static const double _movieVolume  = 0.88;

  bool get isSpeaking => _speaking;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setLanguage('en-US');
    await _setNormalVoice();
    await _tts.awaitSpeakCompletion(true);

    _tts.setStartHandler(() {
      _speaking = true;
    });

    _tts.setCompletionHandler(() {
      _speaking = false;
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete();
      }
    });

    _tts.setCancelHandler(() {
      _speaking = false;
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete();
      }
    });

    _tts.setErrorHandler((_) {
      _speaking = false;
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete();
      }
    });

    _initialized = true;
  }

  Future<void> _setNormalVoice() async {
    await _tts.setSpeechRate(_normalRate);
    await _tts.setPitch(_normalPitch);
    await _tts.setVolume(_normalVolume);
  }

  Future<void> _setMovieVoice() async {
    await _tts.setSpeechRate(_movieRate);
    await _tts.setPitch(_moviePitch);
    await _tts.setVolume(_movieVolume);
  }

  /// Speak [text] and await completion. [movieMode] uses the softer voice.
  Future<void> speak(String text, {bool movieMode = false}) async {
    await init();
    if (movieMode) {
      await _setMovieVoice();
    } else {
      await _setNormalVoice();
    }
    _speaking = true;
    _completer = Completer<void>();
    print('SIGHT_MATE [SPOKEN TEXT]: "$text"');
    await _tts.speak(text);
    // Await completion so caller does not exit early
    try {
      await _completer?.future;
    } catch (_) {}
  }

  /// Stop immediately (Principle 5).
  Future<void> stop() async {
    _speaking = false;
    await _tts.stop();
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
  }
}
