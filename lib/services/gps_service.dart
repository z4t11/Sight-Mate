import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'app_config.dart';

/// Service managing real-time GPS location and geofencing.
class GpsService {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;
  bool _hasPermission = false;

  Position? get currentPosition => _currentPosition;
  bool get hasPermission => _hasPermission;
  bool get isGpsAvailable => _currentPosition != null;

  /// Initialise and request GPS permissions.
  Future<bool> init() async {
    if (AppConfig.isMockMode) {
      _currentPosition = Position(
        latitude: 12.9716,
        longitude: 77.5946,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        altitude: 900.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      _hasPermission = true;
      return true;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      _hasPermission = true;

      // Get initial position
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      ).catchError((_) => null as dynamic);

      // Start continuous stream
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2, // notify every 2 metres
        ),
      ).listen((pos) {
        _currentPosition = pos;
      }, onError: (_) {});

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Distance in metres between current location and a target coordinate.
  double? distanceTo(double targetLat, double targetLon) {
    if (_currentPosition == null) return null;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      targetLat,
      targetLon,
    );
  }

  /// Bearing in degrees (0..360) from current location to target coordinate.
  double? bearingTo(double targetLat, double targetLon) {
    if (_currentPosition == null) return null;
    final b = Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      targetLat,
      targetLon,
    );
    return (b + 360) % 360;
  }

  void dispose() {
    _positionSub?.cancel();
  }
}
