import 'dart:async';
import 'package:flutter/services.dart';
import 'app_config.dart';

/// Audio Gate Service for Movie Mode (Milestone 4).
///
/// Continuously monitors ambient room sound:
/// - Detects when movie dialogue is active (RMS > threshold).
/// - Detects dialogue pauses / gaps (RMS < threshold for >= 1.5 seconds).
/// - Informs the movie describer loop when it is safe to speak without talking over actors.
class AudioGateService {
  static const MethodChannel _channel =
      MethodChannel('com.example.sight_mate/hardware_buttons');

  /// RMS threshold above which ambient sound is considered movie dialogue.
  final double dialogueThresholdRms;

  /// Continuous quiet duration required before opening the gate.
  final Duration silenceDurationRequired;

  bool _isRunning = false;
  bool _isGateOpen = false;
  bool _isMutedForTts = false;
  double _currentRms = 0.0;
  DateTime _lastLoudTime = DateTime.now();
  Timer? _evalTimer;
  Timer? _mockTimer;

  final _gateStateController = StreamController<bool>.broadcast();
  Stream<bool> get onGateStateChanged => _gateStateController.stream;

  AudioGateService({
    this.dialogueThresholdRms = 850.0,
    this.silenceDurationRequired = const Duration(milliseconds: 1500),
  });

  bool get isRunning => _isRunning;
  bool get isGateOpen => _isGateOpen && !_isMutedForTts;
  double get currentRms => _currentRms;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    _lastLoudTime = DateTime.now();
    _isGateOpen = false;

    // Listen to native platform channel audio level events
    _channel.setMethodCallHandler(_handlePlatformCall);

    try {
      await _channel.invokeMethod('startAudioGate');
    } catch (_) {
      // Non-Android or channel error: fallback to simulation timer
    }

    // Evaluation timer: checks if 1.5s of silence has elapsed
    _evalTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _evaluateGate();
    });

    // Mock Mode fallback: periodically cycle between dialogue (loud) and pauses (quiet)
    if (AppConfig.isMockMode) {
      _startMockCycle();
    }
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'onAudioLevel') {
      final double? rms = (call.arguments is num) ? (call.arguments as num).toDouble() : null;
      if (rms != null) {
        _onAudioSample(rms);
      }
    }
  }

  void _onAudioSample(double rms) {
    if (!_isRunning || _isMutedForTts) return;
    _currentRms = rms;

    if (rms >= dialogueThresholdRms) {
      _lastLoudTime = DateTime.now();
      if (_isGateOpen) {
        _isGateOpen = false;
        _gateStateController.add(false);
      }
    }
  }

  void _evaluateGate() {
    if (!_isRunning || _isMutedForTts) return;

    final quietMs = DateTime.now().difference(_lastLoudTime).inMilliseconds;
    final shouldBeOpen = quietMs >= silenceDurationRequired.inMilliseconds;

    if (shouldBeOpen != _isGateOpen) {
      _isGateOpen = shouldBeOpen;
      _gateStateController.add(_isGateOpen);
    }
  }

  /// Temporarily ignore mic while TTS is speaking its 15-word audio description.
  void setMutedForTts(bool muted) {
    _isMutedForTts = muted;
    if (muted) {
      _isGateOpen = false;
      _gateStateController.add(false);
    } else {
      // Give a 400ms buffer after TTS ends before measuring silence
      _lastLoudTime = DateTime.now();
    }
  }

  void _startMockCycle() {
    int tick = 0;
    _mockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_isRunning || _isMutedForTts) return;
      tick++;
      // Every 12 ticks (6s): 8 ticks of simulated dialogue (loud), 4 ticks of gap (quiet)
      final inDialogue = (tick % 12) < 7;
      if (inDialogue) {
        _onAudioSample(1200.0);
      } else {
        _onAudioSample(150.0);
      }
    });
  }

  Future<void> stop() async {
    _isRunning = false;
    _isGateOpen = false;
    _evalTimer?.cancel();
    _mockTimer?.cancel();
    _evalTimer = null;
    _mockTimer = null;

    try {
      await _channel.invokeMethod('stopAudioGate');
    } catch (_) {}
  }

  void dispose() {
    stop();
    _gateStateController.close();
  }
}
