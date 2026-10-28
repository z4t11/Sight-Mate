import 'dart:async';
import 'package:flutter/material.dart';
import '../services/map_loader.dart';
import '../services/positioning_service.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../services/haptic_service.dart';
import '../services/hardware_button_service.dart';
import '../services/camera_service.dart';
import '../services/gemini_service.dart';
import '../services/clew_route_recorder.dart';
import '../utils/compass_helper.dart';

enum _RecorderPhase { setStart, recordingWalk, setDestination, completed }

/// Clew-inspired Route Recorder Screen.
/// Allows blind and low-vision users to record an indoor route completely hands-free.
/// Tracks phone movement, auto-drops spatial crumbs, detects turns, and saves the route locally.
class RouteRecorderScreen extends StatefulWidget {
  final MapLoader mapLoader;
  final PositioningService positioning;
  final TtsService tts;
  final SttService stt;
  final CameraService? camera;
  final GeminiService? gemini;

  const RouteRecorderScreen({
    super.key,
    required this.mapLoader,
    required this.positioning,
    required this.tts,
    required this.stt,
    this.camera,
    this.gemini,
  });

  @override
  State<RouteRecorderScreen> createState() => _RouteRecorderScreenState();
}

class _RouteRecorderScreenState extends State<RouteRecorderScreen> {
  late final ClewRouteRecorder _recorder;
  final _hwButtons = HardwareButtonService();
  final _startController = TextEditingController(text: 'Staff Room');
  final _destController = TextEditingController(text: 'Software Lab');

  _RecorderPhase _phase = _RecorderPhase.setStart;
  StreamSubscription<int>? _stepSub;
  Timer? _headingPollTimer;
  String _statusMessage = 'Speak or confirm starting room name.';

  @override
  void initState() {
    super.initState();
    _recorder = ClewRouteRecorder(
      camera: widget.camera,
      gemini: widget.gemini,
    );
    _recorder.addListener(_onRecorderUpdate);
    _hwButtons.addListener(_onHardwareButton);

    // Listen to real-time pedometer steps for hands-free dead reckoning
    _stepSub = widget.positioning.onStepStream.listen((delta) {
      if (_phase == _RecorderPhase.recordingWalk) {
        _recorder.onStep(delta);
      }
    });

    // Poll live compass heading
    _headingPollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_phase == _RecorderPhase.recordingWalk) {
        _recorder.updateHeading(widget.positioning.currentHeading);
      }
    });

    _announceStart();
  }

  void _onRecorderUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _announceStart() async {
    await widget.tts.speak(
      "Clew Route Recorder active. Say or confirm your starting point, like Staff Room.",
    );
  }

  bool _onHardwareButton(HardwareButton button) {
    if (!mounted) return false;

    if (button == HardwareButton.volumeDown) {
      // Exit Route Recorder immediately
      HapticService.confirm();
      _recorder.cancelRecording();
      Navigator.of(context).pop();
      return true;
    } else if (button == HardwareButton.volumeUp) {
      // Hands-free action trigger
      if (_phase == _RecorderPhase.recordingWalk) {
        _finishWalkAndPromptDestination();
      } else {
        _listenForRoomName();
      }
      return true;
    }
    return false;
  }

  Future<void> _listenForRoomName() async {
    await HapticService.confirm();
    await widget.stt.listen(
      onResult: (text) {
        if (!mounted || text.isEmpty) return;
        setState(() {
          if (_phase == _RecorderPhase.setStart) {
            _startController.text = text;
          } else if (_phase == _RecorderPhase.setDestination) {
            _destController.text = text;
          }
        });
      },
      onDone: () {},
    );
  }

  void _beginWalkRecording() async {
    final startName = _startController.text.trim();
    if (startName.isEmpty) return;

    _recorder.startRecording(startName);
    setState(() {
      _phase = _RecorderPhase.recordingWalk;
      _statusMessage = 'Recording walk from $startName. Walk freely without tapping.';
    });

    await HapticService.confirm();
    await widget.tts.speak(
      "Started recording at $startName. Walk normally to your destination. "
      "Sight Mate will drop crumbs and detect turns automatically. "
      "When you reach your destination, tap the screen or double-click Volume Up.",
    );
  }

  void _finishWalkAndPromptDestination() async {
    await HapticService.confirm();
    setState(() {
      _phase = _RecorderPhase.setDestination;
      _statusMessage = 'Walk finished (${_recorder.totalSteps} steps). Confirm destination name.';
    });

    await widget.tts.speak(
      "Reached destination after ${_recorder.totalSteps} steps. "
      "What is the destination name? For example, Software Lab.",
    );
  }

  Future<void> _saveRoute() async {
    final destName = _destController.text.trim();
    if (destName.isEmpty) return;

    final route = await _recorder.finishAndSave(destName);

    setState(() {
      _phase = _RecorderPhase.completed;
      _statusMessage =
          'Route saved: ${route.name} (${route.totalSteps} steps, ${route.keypoints.length} keypoints)!';
    });

    await HapticService.confirm();
    await widget.tts.speak(
      "Route successfully saved between ${route.startName} and ${route.destinationName}! "
      "Return route was also generated automatically. You can now retrace this path anytime.",
    );

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _stepSub?.cancel();
    _headingPollTimer?.cancel();
    _hwButtons.removeListener(_onHardwareButton);
    _recorder.removeListener(_onRecorderUpdate);
    _recorder.dispose();
    _startController.dispose();
    _destController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dirWord = CompassHelper.headingToWord(widget.positioning.currentHeading);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Clew Route Tracker (Indoor)'),
        backgroundColor: Colors.grey[900],
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Phase 1: Set Starting Location ──
              if (_phase == _RecorderPhase.setStart) ...[
                const Text(
                  '1. Starting Location',
                  style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _startController,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: InputDecoration(
                    hintText: 'e.g. Staff Room',
                    hintStyle: const TextStyle(color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.mic, color: Colors.amber),
                      onPressed: _listenForRoomName,
                    ),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.directions_walk, size: 28),
                  label: const Text('START WALKING RECORD', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _beginWalkRecording,
                ),
              ],

              // ── Phase 2: Live Hands-free Walk Recording ──
              if (_phase == _RecorderPhase.recordingWalk) ...[
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _finishWalkAndPromptDestination,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey[900],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.cyan, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.track_changes, size: 64, color: Colors.cyanAccent),
                          const SizedBox(height: 16),
                          Text(
                            '${_recorder.totalSteps} STEPS',
                            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${_recorder.totalDistanceMeters.toStringAsFixed(1)} m · ${_recorder.crumbCount} crumbs · ${_recorder.keypointCount} keypoints',
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 16),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Facing: $dirWord (${widget.positioning.currentHeading.round()}°)',
                            style: const TextStyle(color: Colors.amber, fontSize: 18),
                          ),
                          if (_recorder.latestVisionLandmark != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Landmark: ${_recorder.latestVisionLandmark}',
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 15),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const Spacer(),
                          const Text(
                            'Tap screen or double-click Vol Up\nwhen you reach destination door',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.flag, size: 28),
                  label: const Text('ARRIVED AT DESTINATION', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _finishWalkAndPromptDestination,
                ),
              ],

              // ── Phase 3: Set Destination Name & Save ──
              if (_phase == _RecorderPhase.setDestination) ...[
                const Text(
                  '2. Destination Name',
                  style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _destController,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: InputDecoration(
                    hintText: 'e.g. Software Lab',
                    hintStyle: const TextStyle(color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.mic, color: Colors.amber),
                      onPressed: _listenForRoomName,
                    ),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Recorded ${_recorder.totalSteps} steps (${_recorder.totalDistanceMeters.toStringAsFixed(1)}m) across ${_recorder.keypointCount} keypoints.',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save, size: 28),
                  label: const Text('SAVE ROUTE & RETURN PATH', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _saveRoute,
                ),
              ],

              // ── Phase 4: Completed ──
              if (_phase == _RecorderPhase.completed) ...[
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 80),
                      SizedBox(height: 16),
                      Text(
                        'Route Successfully Saved!',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              // Status notice
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
