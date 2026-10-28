import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'app_config.dart';

/// Service managing real-time GPS location and geofencing.
class GpsService extends ChangeNotifier {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;
  bool _hasPermission = false;
  bool _isServiceEnabled = false;

  Position? get currentPosition => _currentPosition;
  bool get hasPermission => _hasPermission;
  bool get isServiceEnabled => _isServiceEnabled;
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
      _isServiceEnabled = true;
      notifyListeners();
      return true;
    }

    try {
      _isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_isServiceEnabled) {
        debugPrint('[GPS] Location service is disabled on device');
        notifyListeners();
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[GPS] Location permission denied by user');
          notifyListeners();
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[GPS] Location permission permanently denied');
        notifyListeners();
        return false;
      }

      _hasPermission = true;

      // 1. Instantly populate with system cached location (<20ms)
      try {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null) {
          _currentPosition = cached;
          debugPrint('[GPS] Last known position loaded: ${cached.latitude}, ${cached.longitude} (acc: ${cached.accuracy}m)');
          notifyListeners();
        }
      } catch (e) {
        debugPrint('[GPS] getLastKnownPosition error: $e');
      }

      // 2. Request fresh position asynchronously (balanced accuracy for quick fix indoors/outdoors)
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      ).then((pos) {
        _currentPosition = pos;
        debugPrint('[GPS] Fresh position locked: ${pos.latitude}, ${pos.longitude}');
        notifyListeners();
      }).catchError((err) {
        debugPrint('[GPS] Initial getCurrentPosition timed out or failed: $err');
      });

      // 3. Start continuous stream with AndroidSettings for high-rate updates
      _startContinuousStream();

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[GPS] init exception: $e');
      return false;
    }
  }

  void _startContinuousStream() {
    _positionSub?.cancel();
    try {
      final locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, // notify every 1 metre
        intervalDuration: const Duration(seconds: 2),
      );

      _positionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((pos) {
        _currentPosition = pos;
        notifyListeners();
      }, onError: (err) {
        debugPrint('[GPS] AndroidSettings stream error, falling back: $err');
        _startFallbackStream();
      });
    } catch (_) {
      _startFallbackStream();
    }
  }

  void _startFallbackStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 1,
      ),
    ).listen((pos) {
      _currentPosition = pos;
      notifyListeners();
    }, onError: (err) {
      debugPrint('[GPS] Fallback stream error: $err');
    });
  }

  /// Open device system location settings if user turned off GPS.
  Future<bool> openLocationSettings() async {
    final opened = await Geolocator.openLocationSettings();
    if (opened) {
      await init();
    }
    return opened;
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

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}
