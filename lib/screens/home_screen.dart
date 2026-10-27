import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../services/gps_service.dart';
import '../services/hardware_button_service.dart';
import 'bridge_mode_screen.dart';
import 'movie_mode_screen.dart';
import 'test_log_screen.dart';
import 'route_recorder_screen.dart';

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
  final _gps      = GpsService();
  final _hwButtons = HardwareButtonService();

  late PositioningService _positioning;
  late NavigationService  _nav;

  StreamSubscription<int>? _stepSub;
  _ListenState _state      = _ListenState.idle;
  String       _statusMsg  = 'Double-click Vol Up or tap to ask';
  String       _transcript = '';
  int          _mockIdx    = 0;

  // Milestone 5: Safety Guardian state
  bool _isSafetyGuardianActive = false;
  Timer? _safetyScanTimer;
  bool _isScanningHazard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hwButtons.addListener(_onHardwareButton);
    _positioning = PositioningService(_map, _gps);
    _nav = NavigationService(map: _map, positioning: _positioning, gps: _gps);
    _stepSub = _positioning.onStepStream.listen(_onPedometerStep);
    _init();
  }

  /// Live step listener: automatically guides the user through each turn as steps are taken.
  void _onPedometerStep(int delta) async {
    if (!_positioning.state.isNavigating) return;

    final update = _nav.onStep(delta);
    if (update == null) return;

    if (mounted) {
      setState(() {
        _statusMsg = update.message;
      });
    }

    if (update.shouldSpeak) {
      await HapticService.confirm();
      await _tts.speak(update.message);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (mounted) setState(() {});
      _camera.dispose().then((_) {
        if (mounted) setState(() {});
      });
    } else if (state == AppLifecycleState.resumed) {
      if (!_camera.isReady) {
        _camera.init().then((_) {
          if (mounted) setState(() {});
        });
      }
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
      Permission.location,
    ].request();

    final sttOk = await _stt.init();
    if (!sttOk && mounted) {
      setState(() => _statusMsg = 'Microphone permission needed');
    }

    await _camera.init();
    await _gps.init();
    _positioning.start();

    if (mounted) setState(() {});
    if (AppConfig.isMockMode && mounted) {
      setState(() => _statusMsg = 'MOCK MODE — Tap anywhere to ask');
    }
  }

  // ── Voice loop ──────────────────────────────────────────────────────────

  Future<void> _startListening() async {
    // 1. Cut any ongoing speech immediately before recording
    await _tts.stop();

    await HapticService.confirm();
    _setListenState(_ListenState.listening, 'Listening…');

    if (!_stt.isAvailable) {
      final ok = await _stt.init();
      if (!ok) {
        if (AppConfig.isMockMode) {
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
        } else {
          await HapticService.error();
          await _tts.speak(
              "Speech recognizer not ready. Double-click Volume Up to try again.");
          _setListenState(
              _ListenState.idle, 'Mic not ready. Double-click Vol Up to retry.');
          return;
        }
      }
    }

    await _stt.listen(
      onResult: _handleTranscript,
      onDone: () {
        if (_state == _ListenState.listening) {
          _setListenState(_ListenState.idle, 'Double-click Vol Up or tap to ask');
        }
      },
    );
  }

  Future<void> _onTap() async {
    // If currently listening: tapping cancels/stops
    if (_state == _ListenState.listening) {
      await _stt.cancel();
      await HapticService.confirm();
      _setListenState(_ListenState.idle, 'Stopped. Double-click Vol Up or tap to ask.');
      return;
    }

    // If currently processing or TTS is speaking: tapping cuts speech immediately
    if (_state == _ListenState.processing || _tts.isSpeaking) {
      await _tts.stop();
      await HapticService.confirm();
      _setListenState(_ListenState.idle, 'Stopped. Double-click Vol Up or tap to ask.');
      return;
    }

    // If currently navigating: tapping provides live camera obstacle check & step deviation!
    if (_positioning.state.isNavigating) {
      await _provideNextObstacleAwareStep();
      return;
    }

    await _startListening();
  }

  Future<void> _handleTranscript(String text) async {
    if (text.isEmpty) {
      _setListenState(
          _ListenState.idle, "I didn't hear anything. Double-click Vol Up or tap to ask.");
      await HapticService.error();
      await _tts.speak("I didn't hear anything. Double-click Volume Up or tap to speak.");
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
        if (_positioning.state.isNavigating) {
          _nav.cancelNavigation();
          await _tts.speak('Navigation stopped.');
        }
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

        // 1. Try OCR match if no known location
        if (!_positioning.state.hasKnownLocation) {
          await _positioning.tryOcrMatch(_camera.controller);
        }

        // 2. If still unknown, visually recognize scene with Gemini
        if (!_positioning.state.hasKnownLocation && _camera.isReady) {
          final frame = await _camera.captureFrame();
          if (frame != null) {
            final scene = await _gemini.recognizeLocationFromScene(frame);
            if (scene != null) {
              _positioning.setCustomLocation(scene);
            }
          }
        }

        final desc = _positioning.describeLocation();
        await _tts.speak(desc);

      // ── Set Location / Starting Point ────────────────────────────────────
      case AppIntentType.setLocation:
        final loc = intent.slot?.trim();
        if (loc == null || loc.isEmpty) {
          await _tts.speak("Tell me where you are, for example 'I am at Point A' or 'I am at the entrance'.");
        } else {
          _positioning.setCustomLocation(loc);
          await _tts.speak("Got it. I've set your starting location to $loc.");
        }

      // ── Navigate (GPS + Map + Camera Obstacle Avoidance) ────────────────
      case AppIntentType.navigate:
        await HapticService.thinking();
        final rawDest = intent.slot?.trim();
        final dest = (rawDest != null && rawDest.isNotEmpty)
            ? rawDest
            : 'forward';

        // Check if destination is on the campus graph or query specifies "from X to Y"
        final isCampusDest = _map.findByName(dest) != null || dest.contains(' to ');

        if (isCampusDest) {
          _setListenState(_ListenState.processing, 'Routing to $dest…');

          // If starting node unknown, default intelligently based on query (e.g. staff room for lab/class, or entrance)
          if (_positioning.state.currentNodeId == null) {
            final qLower = dest.toLowerCase();
            final defaultStart = (qLower.contains('lab') || qLower.contains('class') || qLower.contains('software'))
                ? (_map.findByName('staff room')?.id ?? 'staff_room')
                : (_map.nodes.isNotEmpty ? _map.nodes.keys.first : 'entrance');
            _positioning.confirmLocation(defaultStart);
          }

          final routeMsg = _nav.handleNavigateCommand(dest);
          await _tts.speak(routeMsg);
          _setListenState(
            _ListenState.idle,
            'Navigating to $dest. Walk forward; app will guide every turn.',
          );
        } else {
          // Visual Micro-Navigation with Obstacle Avoidance & Step Deviations
          _positioning.setCustomLocation("Current spot");
          _positioning.updateState(_positioning.state.copyWith(
            isNavigating: true,
            activeDestination: dest,
          ));
          await _provideNextObstacleAwareStep(dest);
        }
        return;

      // ── Route Recorder Mode ("Scan & Save") ──────────────────────────────
      case AppIntentType.recordRoute:
        await _openRouteRecorder();
        return;

      // ── Sign Language Bridge Mode ────────────────────────────────────────
      case AppIntentType.signBridgeMode:
        await _openBridgeMode();
        return;

      // ── Movie Mode ──────────────────────────────────────────────────────
      case AppIntentType.movieMode:
        await _openMovieMode();
        return;

      // ── Safety Guardian Mode (Milestone 5) ──────────────────────────────
      case AppIntentType.safetyGuardian:
        if (intent.slot == 'stop') {
          await _toggleSafetyGuardian(false);
        } else {
          await _toggleSafetyGuardian(true);
        }
        return;

      // ── Emergency SOS (Milestone 5) ─────────────────────────────────────
      case AppIntentType.emergencySos:
        await _triggerEmergencySos();
        return;

      // ── System Diagnostics (Milestone 5) ────────────────────────────────
      case AppIntentType.runDiagnostics:
        await _openDiagnostics();
        return;

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

  Future<void> _openRouteRecorder() async {
    await _tts.stop();
    await _stt.stop();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteRecorderScreen(
          mapLoader: _map,
          positioning: _positioning,
          tts: _tts,
          stt: _stt,
        ),
      ),
    );

    if (mounted) setState(() {});
    await _tts.speak('Route recorder closed. Back to home.');
    _setListenState(_ListenState.idle, 'Double-click Vol Up or tap to ask');
  }

  Future<void> _openBridgeMode() async {
    await _tts.stop();
    await _stt.stop();
    await _camera.dispose();
    if (mounted) setState(() {});

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BridgeModeScreen(
          tts: _tts,
          stt: _stt,
        ),
      ),
    );

    // Re-initialize camera when returning to Home
    await _camera.init();
    if (mounted) setState(() {});
    await _tts.speak('Switched back to normal mode.');
    _setListenState(_ListenState.idle, 'Double-click Vol Up or tap to ask');
  }

  // ── Milestone 5: Safety Guardian Mode ──────────────────────────────────

  Future<void> _toggleSafetyGuardian(bool enable) async {
    if (enable == _isSafetyGuardianActive) return;

    if (enable) {
      setState(() => _isSafetyGuardianActive = true);
      await HapticService.confirm();
      await _tts.speak(
        "Safety Guardian active. Scanning continuously for drop-offs, stairs, and head-height hazards. Double-click Volume Down to exit.",
      );
      _safetyScanTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _runSafetyScan());
    } else {
      _safetyScanTimer?.cancel();
      _safetyScanTimer = null;
      setState(() => _isSafetyGuardianActive = false);
      await HapticService.confirm();
      await _tts.speak("Safety Guardian stopped.");
    }
    _setListenState(_ListenState.idle, 'Double-click Vol Up or tap to ask');
  }

  Future<void> _runSafetyScan() async {
    if (!_isSafetyGuardianActive || _isScanningHazard || !mounted) return;
    if (_state != _ListenState.idle) return;

    _isScanningHazard = true;
    try {
      final frame = await _camera.captureFrame();
      if (frame != null) {
        final hazard = await _gemini.scanForImmediateHazards(frame);
        if (hazard != null && mounted && _isSafetyGuardianActive) {
          await HapticService.hazardWarning();
          _setListenState(_ListenState.processing, 'HAZARD: $hazard');
          await _tts.speak(hazard);
          _setListenState(
              _ListenState.idle, 'Double-click Vol Up or tap to ask');
        }
      }
    } catch (_) {
    } finally {
      _isScanningHazard = false;
    }
  }

  // ── Milestone 5: Emergency SOS ──────────────────────────────────────────

  Future<void> _triggerEmergencySos() async {
    await _tts.stop();
    await _stt.stop();
    await HapticService.emergencyAlert();

    _setListenState(_ListenState.processing, 'EMERGENCY SOS TRIGGERED');

    final pos = _gps.currentPosition;
    String locationText = '';

    if (pos != null) {
      final lat = pos.latitude.toStringAsFixed(5);
      final lng = pos.longitude.toStringAsFixed(5);
      locationText = "GPS coordinates: $lat by $lng";
      final mapUrl = "https://maps.google.com/?q=$lat,$lng";
      await Clipboard.setData(ClipboardData(
          text: "EMERGENCY: I need help. My current location is: $mapUrl"));
    } else {
      locationText = _positioning.describeLocation();
    }

    final frame = await _camera.captureFrame();
    String sceneContext = '';
    if (frame != null) {
      final scene = await _gemini.recognizeLocationFromScene(frame);
      if (scene != null) {
        sceneContext = " Near $scene.";
      }
    }

    final speechMsg =
        "Emergency alert activated. $locationText.$sceneContext Emergency map link copied to clipboard.";
    await _tts.speak(speechMsg);
    _setListenState(
        _ListenState.idle, 'SOS active. Double-click Vol Down to stop.');
  }

  // ── Milestone 5: System Diagnostics ────────────────────────────────────

  Future<void> _openDiagnostics() async {
    await _tts.stop();
    await _stt.stop();
    await _camera.dispose();
    if (mounted) setState(() {});

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TestLogScreen(
          tts: _tts,
          stt: _stt,
        ),
      ),
    );

    // Re-initialize camera when returning to Home
    await _camera.init();
    if (mounted) setState(() {});
    _setListenState(_ListenState.idle, 'Double-click Vol Up or tap to ask');
  }

  Future<void> _openMovieMode() async {
    await _tts.stop();
    await _stt.stop();
    await _camera.dispose();
    if (mounted) setState(() {});

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovieModeScreen(
          tts: _tts,
          stt: _stt,
        ),
      ),
    );

    // Re-initialize camera when returning to Home
    await _camera.init();
    if (mounted) setState(() {});
    await _tts.speak('Switched back to normal mode.');
    _setListenState(_ListenState.idle, 'Double-click Vol Up or tap to ask');
  }

  void _setListenState(_ListenState state, String msg) {
    if (!mounted) return;
    setState(() {
      _state     = state;
      _statusMsg = msg;
    });
  }

  /// Combined Map + GPS + Camera Live Obstacle Avoidance & Step Deviation Guidance
  Future<void> _provideNextObstacleAwareStep([String? targetDest]) async {
    final dest = targetDest ??
        _positioning.state.activeDestination ??
        'your destination';

    _setListenState(_ListenState.processing, 'Scanning path to $dest…');
    await HapticService.thinking();

    final frame = await _camera.captureFrame();
    final remainingSteps = _nav.getRemainingSteps();
    final state = _positioning.state;

    // Ask Gemini for obstacle-aware micro-guidance with exact step deviations
    final instruction = await _gemini.askObstacleAwareNavigation(
      destination: dest,
      imageBytes: frame,
      currentPosition: state.locationDisplayName,
      headingDegrees: state.headingDegrees,
      stepsRemaining: remainingSteps,
    );

    _setListenState(_ListenState.processing, 'Speaking…');
    await _tts.speak(instruction);
    _setListenState(
      _ListenState.idle,
      'Navigating to $dest. Tap screen for next step or obstacle check.',
    );
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

              // Safety Guardian Active Banner (Milestone 5)
              if (_isSafetyGuardianActive)
                Positioned(
                  top: 50,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A3D22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.greenAccent, width: 2),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_rounded,
                            color: Colors.greenAccent, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'SAFETY GUARDIAN ACTIVE • SCANNING',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Route Recorder (Scan & Save) Quick Access Pill
                Positioned(
                  top: 48,
                  right: 20,
                  child: Semantics(
                    button: true,
                    label: 'Map Route. Scan and record a building corridor path.',
                    child: GestureDetector(
                      onTap: _openRouteRecorder,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.cyanAccent, width: 1.5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_road_rounded,
                                color: Colors.cyanAccent, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'MAP ROUTE',
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
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
                          const SizedBox(width: 16),
                          _statusDot(_gps.isGpsAvailable || AppConfig.isMockMode, 'GPS'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      excludeSemantics: true,
                      child: Text(
                        'Vol Up (2x): Speak  •  Vol Down (2x): Stop  •  1x: Vol',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
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

  bool _onHardwareButton(HardwareButton button) {
    if (!mounted) return false;

    if (button == HardwareButton.volumeUp) {
      // Physical Volume Up Double-Click: Voice Input in ANY state!
      if (_state == _ListenState.listening) {
        _stt.cancel().then((_) => _startListening());
      } else {
        _startListening();
      }
      return true;
    } else if (button == HardwareButton.volumeDown) {
      // Physical Volume Down Double-Click: Instant STOP (Speech, STT, Navigation, or Safety Guardian)
      _tts.stop();
      _stt.cancel();
      if (_isSafetyGuardianActive) {
        _toggleSafetyGuardian(false);
      }
      if (_positioning.state.isNavigating) {
        _nav.cancelNavigation();
      }
      HapticService.confirm();
      _setListenState(_ListenState.idle, 'Stopped. Double-click Vol Up or tap to ask.');
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepSub?.cancel();
    _safetyScanTimer?.cancel();
    _hwButtons.removeListener(_onHardwareButton);
    _stt.stop();
    _tts.stop();
    _gps.dispose();
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
