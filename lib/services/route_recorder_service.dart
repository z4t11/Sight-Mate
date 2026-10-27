import '../models/map_node.dart';
import '../models/map_edge.dart';
import 'user_route_storage.dart';
import '../utils/compass_helper.dart';

/// Service managing the live recording of new corridor routes ("Scan & Save").
class RouteRecorderService {
  bool _isRecording = false;
  String _startRoom = '';
  int _currentLegSteps = 0;
  double _currentHeading = 0.0;
  final List<RecordedLeg> _legs = [];

  bool get isRecording => _isRecording;
  String get startRoom => _startRoom;
  int get currentLegSteps => _currentLegSteps;
  double get currentHeading => _currentHeading;
  int get waypointsCount => _legs.length;
  List<RecordedLeg> get legs => List.unmodifiable(_legs);

  /// Start recording a new corridor route from [startRoomName].
  void startRecording(String startRoomName) {
    _isRecording = true;
    _startRoom = startRoomName.trim();
    _currentLegSteps = 0;
    _legs.clear();
  }

  /// Register physical steps taken on the current leg.
  void onStep(int delta) {
    if (!_isRecording) return;
    _currentLegSteps += delta;
  }

  /// Update the live compass heading.
  void updateHeading(double heading) {
    _currentHeading = heading;
  }

  /// Record a turn, corner, or junction along the corridor.
  String addWaypoint({String? label}) {
    if (!_isRecording) return "Not recording.";

    final steps = _currentLegSteps > 0 ? _currentLegSteps : 10;
    final legLabel = label ?? 'Turn ${waypointsCount + 1}';
    final leg = RecordedLeg(
      label: legLabel,
      steps: steps,
      heading: _currentHeading,
    );
    _legs.add(leg);
    _currentLegSteps = 0;

    final dirWord = CompassHelper.headingToWord(_currentHeading);
    return "$legLabel recorded: $steps steps heading $dirWord.";
  }

  /// Finish recording at the destination room door.
  Future<Map<String, dynamic>> finishRecording(String destinationRoom) async {
    if (!_isRecording) {
      return {'nodes': <MapNode>[], 'edges': <MapEdge>[]};
    }

    final dest = destinationRoom.trim();
    final steps = _currentLegSteps > 0 ? _currentLegSteps : 10;

    // Add final leg to destination
    _legs.add(RecordedLeg(
      label: dest,
      steps: steps,
      heading: _currentHeading,
    ));

    final result = await UserRouteStorage.saveRoute(
      startName: _startRoom,
      destName: dest,
      legs: _legs,
    );

    _isRecording = false;
    _currentLegSteps = 0;
    _legs.clear();
    return result;
  }

  /// Cancel current recording session without saving.
  void cancelRecording() {
    _isRecording = false;
    _currentLegSteps = 0;
    _legs.clear();
    _startRoom = '';
  }
}
