import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../services/haptic_service.dart';
import '../services/camera_service.dart';
import '../services/gemini_service.dart';
import '../services/audio_gate_service.dart';
import '../services/hardware_button_service.dart';
import '../utils/scene_differ.dart';

/// Milestone 4: Movie Mode Screen (Cinema Companion).
///
/// Provides automated audio descriptions for blind and low-vision viewers:
/// 1. Audio Gate: Monitors ambient sound and only speaks during dialogue gaps (>= 1.5s quiet).
/// 2. Visual Differ: Detects scene cuts and motion (skips static shots).
/// 3. Rate Limit: At most once every 6 seconds.
/// 4. 15-Word Prompt: Real-time, ultra-concise visual description.
/// 5. Softer/Faster Voice: Blends naturally between dialogue lines.
/// 6. Hands-Free Controls:
///    - Double-click Volume Down: Exit Movie Mode.
///    - Double-click Volume Up or Tap: Force instant on-demand description.
class MovieModeScreen extends StatefulWidget {
  final TtsService tts;
  final SttService stt;

  const MovieModeScreen({
    super.key,
    required this.tts,
    required this.stt,
  });

  @override
  State<MovieModeScreen> createState() => _MovieModeScreenState();
}

class _MovieModeScreenState extends State<MovieModeScreen> {
  final _camera = CameraService();
  final _gemini = GeminiService();
  final _audioGate = AudioGateService();
  final _differ = SceneDiffer();
  final _hwButtons = HardwareButtonService();

  Timer? _loopTimer;
  StreamSubscription<bool>? _gateSub;

  String _latestDescription = "Point camera at the movie screen…";
  bool _isGateOpen = false;
  bool _isDescribing = false;
  DateTime _lastDescribeTime = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _minInterval = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _hwButtons.addListener(_onHardwareButton);
    _initMovieMode();
  }

  Future<void> _initMovieMode() async {
    await _camera.init();
    if (mounted) setState(() {});

    await _audioGate.start();
    _gateSub = _audioGate.onGateStateChanged.listen((open) {
      if (mounted) setState(() => _isGateOpen = open);
    });

    await widget.tts.speak(
      "Movie Mode active. Point camera at the screen. "
      "I will describe scenes during dialogue gaps. "
      "Double-click Volume Down to exit.",
      movieMode: true,
    );

    // Periodic evaluation loop: checks every 1 second
    _loopTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _evaluateAndDescribe();
    });
  }

  bool _onHardwareButton(HardwareButton button) {
    if (!mounted) return false;

    if (button == HardwareButton.volumeDown) {
      // Physical Volume Down Double-Click: Instant Exit back to Normal Mode!
      HapticService.confirm();
      Navigator.of(context).pop();
      return true;
    } else if (button == HardwareButton.volumeUp) {
      // Physical Volume Up Double-Click: Instant On-Demand Description!
      _forceInstantDescription();
      return true;
    }
    return false;
  }

  Future<void> _evaluateAndDescribe() async {
    if (_isDescribing || !mounted) return;

    // 1. Throttle: Must be at least 6 seconds since last description
    final elapsed = DateTime.now().difference(_lastDescribeTime);
    if (elapsed < _minInterval) return;

    // 2. Audio Gate: Only describe during dialogue pauses
    if (!_audioGate.isGateOpen) return;

    // 3. Capture camera frame
    final frame = await _camera.captureFrame();
    if (frame == null) return;

    // 4. Visual Differ: Check if scene changed
    final changed = await _differ.hasSignificantChange(frame);
    if (!changed) return;

    // 5. Generate and speak 15-word description
    await _speakDescription(frame);
  }

  /// Forced manual description triggered by tap or double-clicking Volume Up.
  Future<void> _forceInstantDescription() async {
    if (_isDescribing || !mounted) return;
    await HapticService.confirm();

    final frame = await _camera.captureFrame();
    if (frame == null) {
      await widget.tts.speak("Camera not ready.", movieMode: true);
      return;
    }

    await _speakDescription(frame);
  }

  Future<void> _speakDescription(dynamic frame) async {
    setState(() => _isDescribing = true);
    _audioGate.setMutedForTts(true);

    try {
      final desc = await _gemini.describeMovieScene(frame);
      if (!mounted) return;

      setState(() => _latestDescription = desc);
      _lastDescribeTime = DateTime.now();

      await widget.tts.speak(desc, movieMode: true);
    } catch (_) {
    } finally {
      // Small pause after speech ends before listening to room audio again
      await Future.delayed(const Duration(milliseconds: 400));
      _audioGate.setMutedForTts(false);
      if (mounted) setState(() => _isDescribing = false);
    }
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _gateSub?.cancel();
    _hwButtons.removeListener(_onHardwareButton);
    _audioGate.dispose();
    _camera.dispose();
    widget.tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _forceInstantDescription,
        child: Stack(
          children: [
            // 1. Dimmed Camera Preview (aimed at TV / theater screen)
            if (_camera.isReady && _camera.controller != null)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.35,
                  child: _SafeCameraPreview(controller: _camera.controller!),
                ),
              ),

            // 2. High-Contrast Overlay UI
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Bar with Exit
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.amberAccent, width: 1.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.movie_filter_rounded,
                                  color: Colors.amberAccent, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'CINEMA COMPANION',
                                style: TextStyle(
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 28),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Audio Gate Status Indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _isGateOpen
                            ? const Color(0xFF0D3820)
                            : const Color(0xFF382200),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isGateOpen
                              ? Colors.greenAccent
                              : Colors.amberAccent.withValues(alpha: 0.7),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isGateOpen
                                ? Icons.graphic_eq_rounded
                                : Icons.hearing_rounded,
                            color: _isGateOpen
                                ? Colors.greenAccent
                                : Colors.amberAccent,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isGateOpen
                                      ? 'DIALOGUE GAP DETECTED'
                                      : 'DIALOGUE ACTIVE (WAITING FOR PAUSE)',
                                  style: TextStyle(
                                    color: _isGateOpen
                                        ? Colors.greenAccent
                                        : Colors.amberAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isGateOpen
                                      ? 'Safe to speak without talking over actors'
                                      : 'Descriptions pause during speech & music',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Latest 15-Word Audio Description Card
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _isDescribing
                              ? Colors.amberAccent
                              : Colors.white24,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'AUDIO DESCRIPTION (≤15 WORDS):',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              if (_isDescribing)
                                const Text(
                                  'SPEAKING…',
                                  style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _latestDescription,
                            style: const TextStyle(
                              color: Colors.yellowAccent,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Accessible Controls Footer Hint
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app,
                              color: Colors.white54, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Vol Down (2x): Exit  •  Vol Up (2x) / Tap: Describe now',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafeCameraPreview extends StatelessWidget {
  final CameraController controller;
  const _SafeCameraPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (!value.isInitialized) return const SizedBox.shrink();
        try {
          return controller.buildPreview();
        } catch (_) {
          return const SizedBox.shrink();
        }
      },
    );
  }
}
