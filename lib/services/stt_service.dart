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
    bool completed = false;
    String lastWords = '';

    void dispatch(String text) {
      if (completed) return;
      completed = true;
      onResult(text);
      onDone();
    }

    await _stt.listen(
      onResult: (result) {
        lastWords = result.recognizedWords;
        if (result.finalResult && lastWords.trim().isNotEmpty) {
          dispatch(lastWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(milliseconds: 1400),
        listenMode: stt.ListenMode.search,
        cancelOnError: true,
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
