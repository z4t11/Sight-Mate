import 'dart:async';
import 'package:flutter/material.dart';
import '../models/map_node.dart';
import '../models/map_edge.dart';
import '../services/map_loader.dart';
import '../services/positioning_service.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../services/haptic_service.dart';
import '../services/hardware_button_service.dart';
import '../services/route_recorder_service.dart';
import '../utils/compass_helper.dart';

enum _RecorderPhase { setStart, recordingWalk, setDestination, completed }

/// Accessible screen allowing users, students, or coordinators to map and save
/// any building route (e.g. Staff Room to Software Lab) by walking it.
class RouteRecorderScreen extends StatefulWidget {
  final MapLoader mapLoader;
  final PositioningService positioning;
  final TtsService tts;
  final SttService stt;

  const RouteRecorderScreen({
    super.key,
    required this.mapLoader,
    required this.positioning,
    required this.tts,
    required this.stt,
  });

  @override
  State<RouteRecorderScreen> createState() => _RouteRecorderScreenState();
}

class _RouteRecorderScreenState extends State<RouteRecorderScreen> {
  final _recorder = RouteRecorderService();
  final _hwButtons = HardwareButtonService();
  final _startController = TextEditingController(text: 'Staff Room');
  final _destController = TextEditingController(text: 'Software Lab');

  _RecorderPhase _phase = _RecorderPhase.setStart;
  StreamSubscription<int>? _stepSub;
  Timer? _headingPollTimer;
  String _statusMessage = 'Tap anywhere or speak to set starting room.';

  @override
  void initState() {
    super.initState();
    _hwButtons.addListener(_onHardwareButton);

    // Listen to real-time pedometer steps
    _stepSub = widget.positioning.onStepStream.listen((delta) {
      if (_phase == _RecorderPhase.recordingWalk) {
        setState(() {
          _recorder.onStep(delta);
        });
      }
    });

    // Poll live compass heading
    _headingPollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_phase == _RecorderPhase.recordingWalk) {
        _recorder.updateHeading(widget.positioning.currentHeading);
        if (mounted) setState(() {});
      }
    });

    _announceStart();
  }

  Future<void> _announceStart() async {
    await widget.tts.speak(
      "Route Recorder active. Say or confirm your starting room name, like Staff Room.",
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
      // Push-to-talk / Add waypoint
      if (_phase == _RecorderPhase.recordingWalk) {
        _addTurnWaypoint();
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
      _statusMessage =
          'Walk down the corridor towards the turn. Tap screen at each corner.';
    });

    await HapticService.confirm();
    await widget.tts.speak(
      "Starting at $startName. Walk forward along the corridor. "
      "Tap the screen when you reach a corner, turn, or doorway.",
    );
  }

  void _addTurnWaypoint() async {
    final summary = _recorder.addWaypoint();
    await HapticService.confirm();
    setState(() {
      _statusMessage = '$summary Now continue towards the next turn or door.';
    });
    await widget.tts.speak(
      "$summary Now turn into the hallway and keep walking. "
      "Tap when you reach the next turn or destination door.",
    );
  }

  void _promptDestination() async {
    await HapticService.confirm();
    setState(() {
      _phase = _RecorderPhase.setDestination;
      _statusMessage = 'At destination door. Confirm room name.';
    });
    await widget.tts.speak(
      "You have reached the destination door. "
      "What is the destination room name? For example, Software Lab.",
    );
  }

  Future<void> _saveRoute() async {
    final destName = _destController.text.trim();
    if (destName.isEmpty) return;

    final result = await _recorder.finishRecording(destName);
    final newNodes = (result['nodes'] as List).cast<MapNode>();
    final newEdges = (result['edges'] as List).cast<MapEdge>();

    // Inject into active MapLoader in memory immediately
    widget.mapLoader.addCustomGraph(newNodes, newEdges);

    setState(() {
      _phase = _RecorderPhase.completed;
      _statusMessage =
          'Route saved successfully between ${_startController.text} and $destName!';
    });

    await HapticService.confirm();
    await widget.tts.speak(
      "Route successfully saved between ${_startController.text} and $destName! "
      "You can now ask to navigate between them anytime.",
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
    _recorder.cancelRecording();
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
        title: const Text('Route Recorder (Scan & Save)'),
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
              // Status Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber[900]?.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber, width: 2),
                ),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 20),

              // Phase 1: Set Start Room
              if (_phase == _RecorderPhase.setStart) ...[
                const Text(
                  'Starting Room / Class:',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _startController,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[850],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: 'e.g. Staff Room, Class 1',
                    hintStyle: const TextStyle(color: Colors.white38),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _beginWalkRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 28, color: Colors.white),
                  label: const Text(
                    'START WALKING & RECORD',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],

              // Phase 2: Live Walk & Waypoint Capture
              if (_phase == _RecorderPhase.recordingWalk) ...[
                Expanded(
                  child: InkWell(
                    onTap: _addTurnWaypoint,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blueGrey[900],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.cyanAccent, width: 3),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.turn_right, size: 64, color: Colors.cyanAccent),
                          const SizedBox(height: 12),
                          Text(
                            '${_recorder.currentLegSteps} STEPS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Heading: ${dirWord.toUpperCase()} (${widget.positioning.currentHeading.toStringAsFixed(0)}°)',
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 20),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Waypoints Recorded: ${_recorder.waypointsCount}',
                            style: const TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.cyan[800],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'TAP ANYWHERE AT CORNER / TURN',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _promptDestination,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[700],
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  icon: const Icon(Icons.flag, color: Colors.white),
                  label: const Text(
                    'ARRIVED AT DESTINATION DOOR',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],

              // Phase 3: Set Destination Room Name
              if (_phase == _RecorderPhase.setDestination) ...[
                const Text(
                  'Destination Room / Lab Name:',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _destController,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[850],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: 'e.g. Software Lab, Class 2',
                    hintStyle: const TextStyle(color: Colors.white38),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _saveRoute,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  icon: const Icon(Icons.check_circle, size: 28, color: Colors.white),
                  label: const Text(
                    'SAVE & ENABLE ROUTE',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
