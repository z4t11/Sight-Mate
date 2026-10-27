import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Ultra-responsive, bullet-proof speech recognition service.
///
/// Features:
/// - Real-time streaming partial results.
/// - 1200ms natural debounce when user finishes speaking words.
/// - Generous 4-second silence tolerance (never cuts off user before they speak).
/// - Dictation mode for natural multi-word phrases and sentences.
/// - Failsafe dispatch: guarantees onDone/onResult callbacks fire on completion or timeout.
/// - Auto-reinitializes on demand.
class SttService {
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _available = false;

  void Function(String transcript)? _activeOnResult;
  void Function()? _activeOnDone;
  bool _dispatched = false;
  String _lastWords = '';
  Timer? _silenceDebounceTimer;

  Future<bool> init() async {
    try {
      _available = await _stt.initialize(
        onError: (e) {
          print('SIGHT_MATE [STT ERROR]: ${e.errorMsg} (permanent: ${e.permanent})');
          _onRecognitionComplete(error: e.errorMsg);
        },
        onStatus: (status) {
          print('SIGHT_MATE [STT STATUS]: $status');
          if (status == 'done') {
            _onRecognitionComplete();
          }
        },
        debugLogging: false,
      );
    } catch (e) {
      print('SIGHT_MATE [STT INIT EXCEPTION]: $e');
      _available = false;
    }
    return _available;
  }

  bool get isAvailable => _available;
  bool get isListening => _stt.isListening;

  Future<void> listen({
    required void Function(String transcript) onResult,
    required void Function() onDone,
  }) async {
    if (!_available) {
      await init();
    }
    if (!_available) {
      onResult('');
      onDone();
      return;
    }

    _activeOnResult = onResult;
    _activeOnDone = onDone;
    _dispatched = false;
    _lastWords = '';
    _silenceDebounceTimer?.cancel();

    try {
      await _stt.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _lastWords = words;
          }

          // Debounce: when user has spoken words and pauses for 1200ms, dispatch immediately
          _silenceDebounceTimer?.cancel();
          if (_lastWords.isNotEmpty) {
            _silenceDebounceTimer = Timer(const Duration(milliseconds: 1200), () {
              if (!_dispatched && _lastWords.isNotEmpty) {
                _stt.stop();
                _dispatch(_lastWords);
              }
            });
          }

          // If speech recognizer gives final confirmation, dispatch immediately
          if (result.finalResult && _lastWords.isNotEmpty) {
            _silenceDebounceTimer?.cancel();
            _dispatch(_lastWords);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 4),
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
      );
    } catch (e) {
      print('SIGHT_MATE [STT LISTEN EXCEPTION]: $e');
      _onRecognitionComplete(error: e.toString());
    }
  }

  void _onRecognitionComplete({String? error}) {
    _silenceDebounceTimer?.cancel();
    if (_dispatched) return;

    if (_lastWords.trim().isNotEmpty) {
      _dispatch(_lastWords);
    } else {
      _dispatch('');
    }
  }

  void _dispatch(String text) {
    if (_dispatched) return;
    _dispatched = true;
    _silenceDebounceTimer?.cancel();

    final cb = _activeOnResult;
    final done = _activeOnDone;
    _activeOnResult = null;
    _activeOnDone = null;

    cb?.call(text);
    done?.call();
  }

  Future<void> stop() async {
    _silenceDebounceTimer?.cancel();
    _onRecognitionComplete();
    try {
      await _stt.stop();
    } catch (_) {}
  }

  Future<void> cancel() async {
    _silenceDebounceTimer?.cancel();
    _dispatched = true;
    _activeOnResult = null;
    _activeOnDone = null;
    try {
      await _stt.cancel();
    } catch (_) {}
  }
}
