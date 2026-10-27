import 'package:flutter/material.dart';
import 'package:flutter_hand_gesture/flutter_hand_gesture.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../services/haptic_service.dart';
import '../services/sign_language_service.dart';
import '../services/hardware_button_service.dart';
import '../services/app_config.dart';

/// Dedicated Offline Sign Language Mode for Blind User.
///
/// Features:
/// - Translates sign language from a non-verbal person into spoken audio in real time.
/// - The blind user speaks directly with their own voice (the non-verbal person can hear them).
/// - Completely offline, zero cloud latency.
/// - 100% hands-free screenless controls via physical hardware buttons:
///   - Volume Down: Instant exit back to normal mode
///   - Volume Up: Voice command listening (or speak keyword)
/// - Fallback: Double-tap or close button to exit.
class BridgeModeScreen extends StatefulWidget {
  final TtsService tts;
  final SttService stt;

  const BridgeModeScreen({
    super.key,
    required this.tts,
    required this.stt,
  });

  @override
  State<BridgeModeScreen> createState() => _BridgeModeScreenState();
}

class _BridgeModeScreenState extends State<BridgeModeScreen> {
  final _signService = SignLanguageService();
  final _hwButtons = HardwareButtonService();

  String _lastTranslatedSign = "Waiting for hand sign…";
  String _lastEmoji = "🖐";
  bool _isListeningForCommand = false;

  @override
  void initState() {
    super.initState();
    _hwButtons.addListener(_onHardwareButton);
    _announceMode();
  }

  bool _onHardwareButton(HardwareButton button) {
    if (!mounted) return false;

    if (button == HardwareButton.volumeDown) {
      // Physical Volume Down: Exit immediately back to normal mode!
      HapticService.confirm();
      Navigator.of(context).pop();
      return true;
    } else if (button == HardwareButton.volumeUp) {
      // Physical Volume Up: Listen for voice command
      _listenForVoiceCommand();
      return true;
    }
    return false;
  }

  Future<void> _announceMode() async {
    await widget.tts.speak(
      "Sign Language Mode active. Point camera at the person signing. Double-click Volume Down to exit.",
    );
  }

  void _onGestureDetected(HandGesture gesture) async {
    final translation = _signService.translateGesture(
      gesture.type,
      confidence: gesture.confidence,
    );

    if (translation != null) {
      await HapticService.confirm();
      if (!mounted) return;
      setState(() {
        _lastTranslatedSign = translation;
        _lastEmoji = gesture.emoji;
      });

      // Speak out the translation so the blind user hears it
      await widget.tts.speak("Person says: $translation");
    }
  }

  Future<void> _listenForVoiceCommand() async {
    if (_isListeningForCommand) {
      await widget.stt.stop();
      setState(() => _isListeningForCommand = false);
      return;
    }

    await HapticService.confirm();
    setState(() => _isListeningForCommand = true);

    if (!widget.stt.isAvailable) {
      if (AppConfig.isMockMode) {
        final mock = _signService.getNextMockTranslation();
        _onMockGesture(mock);
      }
      setState(() => _isListeningForCommand = false);
      return;
    }

    await widget.stt.listen(
      onResult: (text) {
        if (!mounted) return;
        final clean = text.toLowerCase().trim();

        // Check for keyword to exit and return to normal mode
        if (clean.contains('normal') ||
            clean.contains('exit') ||
            clean.contains('stop') ||
            clean.contains('back') ||
            clean.contains('home') ||
            clean.contains('cancel') ||
            clean.contains('quit')) {
          widget.stt.stop();
          Navigator.of(context).pop();
        } else {
          widget.tts.speak("Press Volume Down to exit.");
        }
      },
      onDone: () {
        if (mounted) setState(() => _isListeningForCommand = false);
      },
    );
  }

  void _onMockGesture(String translation) async {
    await HapticService.confirm();
    setState(() {
      _lastTranslatedSign = translation;
      _lastEmoji = "🤟";
    });
    await widget.tts.speak("Person says: $translation");
  }

  @override
  void dispose() {
    _hwButtons.removeListener(_onHardwareButton);
    widget.tts.stop();
    widget.stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _listenForVoiceCommand,
        onDoubleTap: () {
          HapticService.confirm();
          Navigator.of(context).pop();
        },
        child: Stack(
          children: [
            // 1. Fullscreen Offline Hand Gesture Camera
            if (!AppConfig.isMockMode)
              Positioned.fill(
                child: GestureCameraView(
                  config: const GestureConfig(
                    minConfidence: 0.70,
                    debounceDuration: Duration(milliseconds: 300),
                  ),
                  showGestureLabel: true,
                  showLandmarks: true,
                  onGestureDetected: _onGestureDetected,
                ),
              )
            else
              Positioned.fill(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _lastEmoji,
                        style: const TextStyle(fontSize: 80),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'MOCK MODE: Tap anywhere to cycle sign translations',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),

            // 2. High-Contrast Overlay
            SafeArea(
              child: Column(
                children: [
                  // Top Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.greenAccent, width: 1.5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.offline_bolt, color: Colors.greenAccent, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'OFFLINE SIGN TRANSLATOR',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 28),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // 3. Translated Sign Display (Spoken aloud to Blind user)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SIGN TRANSLATION (SPOKEN ALOUD):',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              _lastEmoji,
                              style: const TextStyle(fontSize: 36),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _lastTranslatedSign,
                                style: const TextStyle(
                                  color: Colors.yellowAccent,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 4. Accessible Controls Indicator
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _isListeningForCommand
                          ? const Color(0xFF003366)
                          : Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isListeningForCommand ? Colors.lightBlueAccent : Colors.white12,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isListeningForCommand ? Icons.mic : Icons.volume_down,
                          color: _isListeningForCommand ? Colors.lightBlueAccent : Colors.white54,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isListeningForCommand
                              ? 'LISTENING… (Double-click Vol Down to exit)'
                              : 'Vol Down (2x): Exit  •  Vol Up (2x): Speak  •  1x: Vol',
                          style: TextStyle(
                            color: _isListeningForCommand ? Colors.lightBlueAccent : Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
