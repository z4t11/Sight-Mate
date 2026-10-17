import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Wraps speech_to_text for single-utterance recording.
class SttService {
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _available = false;

  Future<bool> init() async {
    _available = await _stt.initialize(
      onError: (e) {},
      debugLogging: false,
    );
    return _available;
  }

  bool get isAvailable => _available;
  bool get isListening => _stt.isListening;

  /// Listen for one utterance; calls [onResult] with the final transcript.
  Future<void> listen({
    required void Function(String transcript) onResult,
    required void Function() onDone,
  }) async {
    if (!_available) {
      onResult('');
      onDone();
      return;
    }
    await _stt.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 4),
        listenMode: stt.ListenMode.confirmation,
      ),
    );
  }

  Future<void> stop() async {
    await _stt.stop();
  }

  Future<void> cancel() async {
    await _stt.cancel();
  }
}
