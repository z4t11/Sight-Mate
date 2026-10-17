import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_intent.dart';
import '../models/verbosity_level.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import '../services/haptic_service.dart';
import '../services/intent_router.dart';
import '../services/settings_service.dart';
import '../services/app_config.dart';
import '../services/camera_service.dart';
import '../services/gemini_service.dart';
import '../services/map_loader.dart';
import '../services/positioning_service.dart';
import '../services/navigation_service.dart';

enum _ListenState { idle, listening, processing }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // ── Services ─────────────────────────────────────────────────────────────
  final _stt      = SttService();
  final _tts      = TtsService();
  final _router   = IntentRouter();
  final _settings = SettingsService();
  final _camera   = CameraService();
  final _gemini   = GeminiService();
  final _map      = MapLoader();

  late PositioningService _positioning;
  late NavigationService  _nav;

  _ListenState _state      = _ListenState.idle;
  String       _statusMsg  = 'Tap anywhere to ask a question';
  String       _transcript = '';
  int          _mockIdx    = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _positioning = PositioningService(_map);
    _nav = NavigationService(map: _map, positioning: _positioning);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (mounted) setState(() {});
      _camera.dispose().then((_) {
        if (mounted) setState(() {});
      });
    } else if (state == AppLifecycleState.resumed) {
      _camera.init().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _init() async {
    await _settings.init();
    await _tts.init();
    await _map.load();

    await [
      Permission.microphone,
      Permission.camera,
      Permission.activityRecognition,
    ].request();

    final sttOk = await _stt.init();
    if (!sttOk && mounted) {
      setState(() => _statusMsg = 'Microphone permission needed');
    }

    await _camera.init();
    _positioning.start();

    if (mounted) setState(() {});
    if (AppConfig.isMockMode && mounted) {
      setState(() => _statusMsg = 'MOCK MODE — Tap anywhere to ask');
    }
  }

  // ── Voice loop ──────────────────────────────────────────────────────────

  Future<void> _onTap() async {
    if (_state != _ListenState.idle) {
      await _tts.stop();
      await _stt.cancel();
      _setListenState(_ListenState.idle, 'Stopped. Tap to ask again.');
      return;
    }

    await HapticService.confirm();
    _setListenState(_ListenState.listening, 'Listening…');

    if (!_stt.isAvailable) {
      // STT truly unavailable — cycle mock commands for demo
      await Future.delayed(const Duration(seconds: 1));
      final mockCmds = [
        'where am I',
        'take me to HOD office',
        'what is in front of me',
        'take me to canteen',
      ];
      final cmd = mockCmds[_mockIdx % mockCmds.length];
      _mockIdx++;
      await _handleTranscript(cmd);
      return;
    }

    await _stt.listen(
      onResult: _handleTranscript,
      onDone: () {
        if (_state == _ListenState.listening) {
          _setListenState(_ListenState.idle, 'Tap anywhere to ask a question');
        }
      },
    );
  }

  Future<void> _handleTranscript(String text) async {
    if (text.isEmpty) {
      _setListenState(
          _ListenState.idle, "I didn't catch that. Tap to try again.");
      return;
    }
    setState(() => _transcript = text);
    _setListenState(_ListenState.processing, 'Got it: "$text"');
    await _dispatchIntent(_router.route(text));
  }

  Future<void> _dispatchIntent(AppIntent intent) async {
    switch (intent.type) {
      case AppIntentType.stopSpeech:
        await _tts.stop();
        _setListenState(_ListenState.idle, 'Stopped. Tap to ask.');
        return;

      // ── Camera Q&A ──────────────────────────────────────────────────────
      case AppIntentType.askCamera:
        await HapticService.thinking();
        _setListenState(_ListenState.processing, 'Looking…');
        final frame = await _camera.captureFrame();
        final answer = await _gemini.ask(
          question: intent.rawText,
          imageBytes: frame,
          verbosity: _settings.verbosity,
        );
        _setListenState(_ListenState.processing, 'Speaking…');
        await _tts.speak(answer);

      // ── More detail ─────────────────────────────────────────────────────
      case AppIntentType.moreDetail:
        await HapticService.thinking();
        final answer = await _gemini.ask(
          question: 'Tell me more detail about what you just described.',
          imageBytes: null,
          verbosity: VerbosityLevel.detailed,
        );
        await _tts.speak(answer);

      // ── Verbosity ───────────────────────────────────────────────────────
      case AppIntentType.setVerbosity:
        final level = VerbosityLevelX.fromString(intent.slot ?? 'normal');
        await _settings.setVerbosity(level);
        await _tts.speak('Verbosity set to ${level.label}.');

      // ── Where am I? ─────────────────────────────────────────────────────
      case AppIntentType.whereAmI:
        await HapticService.thinking();
        _setListenState(_ListenState.processing, 'Checking position…');

        // Try OCR match first
        await _positioning.tryOcrMatch(_camera.controller);

        final desc = _positioning.describeLocation();
        await _tts.speak(desc);

      // ── Navigate ────────────────────────────────────────────────────────
      case AppIntentType.navigate:
        await HapticService.thinking();
        final dest = intent.slot?.isNotEmpty == true
            ? intent.slot!
            : 'that destination';
        _setListenState(_ListenState.processing, 'Planning route to $dest…');

        // Ensure we know position
        if (_positioning.state.currentNodeId == null) {
          await _positioning.tryOcrMatch(_camera.controller);
        }

        final result = _nav.handleNavigateCommand(dest);
        await _tts.speak(result);

      // ── Movie Mode ──────────────────────────────────────────────────────
      case AppIntentType.movieMode:
        await _tts.speak('Movie mode coming in milestone 4.');

      // ── Unknown ─────────────────────────────────────────────────────────
      case AppIntentType.unknown:
        await _tts.speak(
            "I'm not sure what you meant. "
            "Try asking what's in front of you, "
            "or say take me to followed by a place.");
    }

    _setListenState(_ListenState.idle, 'Tap anywhere to ask a question');
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void _setListenState(_ListenState state, String msg) {
    if (!mounted) return;
    setState(() {
      _state     = state;
      _statusMsg = msg;
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isListening  = _state == _ListenState.listening;
    final isProcessing = _state == _ListenState.processing;
    final isNav = _positioning.state.isNavigating;

    final Color bgColor = isListening
        ? const Color(0xFF003366)
        : isProcessing
            ? const Color(0xFF1A1A2E)
            : isNav
                ? const Color(0xFF1A2E1A)
                : Colors.black;

    final String semanticHint = isListening
        ? 'Listening for your question. Tap to stop.'
        : isProcessing
            ? 'Processing your request. Tap to stop.'
            : isNav
                ? 'Navigating. Tap to hear the next instruction or ask a question.'
                : 'Tap anywhere to ask Sight Mate a question.';

    return Scaffold(
      backgroundColor: bgColor,
      body: Semantics(
        label: semanticHint,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: Stack(
            children: [
              // Camera preview (dimmed)
              if (_camera.isReady && _camera.controller != null)
                Positioned.fill(
                  child: Semantics(
                    excludeSemantics: true,
                    child: Opacity(
                      opacity: 0.25,
                      child: _SafeCameraPreview(controller: _camera.controller!),
                    ),
                  ),
                ),

              // Dark gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.5),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
              ),

              // Foreground content
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon
                    Semantics(
                      excludeSemantics: true,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          isListening
                              ? Icons.mic
                              : isProcessing
                                  ? Icons.hourglass_top_rounded
                                  : isNav
                                      ? Icons.navigation_rounded
                                      : Icons.mic_none,
                          key: ValueKey('$_state$isNav'),
                          size: 80,
                          color: isListening
                              ? Colors.lightBlueAccent
                              : isNav
                                  ? Colors.greenAccent
                                  : Colors.white54,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Status
                    Semantics(
                      excludeSemantics: true,
                      child: Text(
                        _statusMsg,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),

                    // Transcript
                    if (_transcript.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      Semantics(
                        excludeSemantics: true,
                        child: Text(
                          '"$_transcript"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 60),

                    // Mock badge
                    if (AppConfig.isMockMode)
                      Semantics(
                        excludeSemantics: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'MOCK MODE',
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 13,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),

                    // Status row: camera + map
                    const SizedBox(height: 12),
                    Semantics(
                      excludeSemantics: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _statusDot(_camera.isReady, 'Cam'),
                          const SizedBox(width: 16),
                          _statusDot(!_map.isEmpty, 'Map'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusDot(bool ok, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          size: 14,
          color: ok
              ? Colors.greenAccent.withValues(alpha: 0.7)
              : Colors.red.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stt.stop();
    _tts.stop();
    _camera.dispose();
    _positioning.dispose();
    super.dispose();
  }
}

/// Guards CameraPreview against native CameraX detachment and disposal race conditions.
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
        if (!value.isInitialized) {
          return const SizedBox.shrink();
        }
        try {
          return controller.buildPreview();
        } catch (_) {
          return const SizedBox.shrink();
        }
      },
    );
  }
}
