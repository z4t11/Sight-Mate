import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'gps_service.dart';
import 'app_config.dart';
import '../utils/compass_helper.dart';

/// A single maneuver step in a pedestrian route.
class PedestrianStep {
  final String instruction;
  final String streetName;
  final double distanceMeters;
  final double durationSeconds;
  final double endLat;
  final double endLng;
  final String modifier; // left, right, straight, etc.

  const PedestrianStep({
    required this.instruction,
    required this.streetName,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.endLat,
    required this.endLng,
    required this.modifier,
  });
}

/// A complete pedestrian route from OSRM.
class PedestrianRoute {
  final String destinationName;
  final double totalDistanceMeters;
  final double totalDurationSeconds;
  final List<PedestrianStep> steps;

  const PedestrianRoute({
    required this.destinationName,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.steps,
  });
}

/// Service providing real pedestrian routing and turn-by-turn outdoor guidance
/// using OpenStreetMap Nominatim Geocoding and OSRM Foot Routing (Section 2.A).
class OutdoorRoutingService {
  final GpsService _gps;
  PedestrianRoute? _activeRoute;
  int _currentStepIndex = 0;
  bool _approachingTurnSpoken = false;

  OutdoorRoutingService(this._gps);

  PedestrianRoute? get activeRoute => _activeRoute;
  bool get isNavigating => _activeRoute != null;
  int get currentStepIndex => _currentStepIndex;

  PedestrianStep? get currentStep {
    if (_activeRoute == null || _currentStepIndex >= _activeRoute!.steps.length) {
      return null;
    }
    return _activeRoute!.steps[_currentStepIndex];
  }

  /// Geocode [destinationQuery] and calculate pedestrian turn-by-turn route.
  Future<String?> planRoute(String destinationQuery) async {
    var curPos = _gps.currentPosition;
    if (curPos == null) {
      try {
        curPos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }
    if (curPos == null) {
      if (!_gps.isServiceEnabled) {
        return "Device location is turned off. Please enable Location in your phone settings.";
      }
      return "Acquiring GPS satellite fix. Please try again in a few seconds.";
    }

    // 1. If Google Maps Platform API key is configured, use Google Maps Directions API
    if (AppConfig.hasGoogleMapsApiKey) {
      final googleRoute = await _planWithGoogleMaps(destinationQuery, curPos);
      if (googleRoute != null) return googleRoute;
    }

    // 2. OpenStreetMap + OSRM Foot Routing Engine (Default & Fallback)
    return await _planWithOsmOsrm(destinationQuery, curPos);
  }

  /// Query Google Maps Platform Directions API for real-time pedestrian walking routes.
  Future<String?> _planWithGoogleMaps(String destinationQuery, Position curPos) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=${curPos.latitude},${curPos.longitude}&destination=${Uri.encodeComponent(destinationQuery)}&mode=walking&key=${AppConfig.googleMapsApiKey}',
      );
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 7));
      if (res.statusCode != 200) return null;

      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json['status'] != 'OK') {
        debugPrint('[GoogleMaps] Directions API status: ${json['status']}, message: ${json['error_message']}');
        return null;
      }

      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final primary = routes[0] as Map<String, dynamic>;
      final legs = primary['legs'] as List? ?? [];
      if (legs.isEmpty) return null;

      final leg = legs[0] as Map<String, dynamic>;
      final totalDist = (leg['distance']?['value'] as num?)?.toDouble() ?? 0.0;
      final totalDur = (leg['duration']?['value'] as num?)?.toDouble() ?? 0.0;
      final endAddress = (leg['end_address'] as String?)?.split(',').first ?? destinationQuery;

      if (totalDist > 25000) {
        return "I found '$endAddress' on Google Maps, but it is ${(totalDist / 1000).round()} kilometres away, which is too far for walking navigation.";
      }

      final stepsList = <PedestrianStep>[];
      for (final s in (leg['steps'] as List? ?? [])) {
        final rawHtml = s['html_instructions'] as String? ?? 'Walk forward';
        final cleanInst = rawHtml.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        final dist = (s['distance']?['value'] as num?)?.toDouble() ?? 0.0;
        final dur = (s['duration']?['value'] as num?)?.toDouble() ?? 0.0;
        final endLoc = s['end_location'] as Map<String, dynamic>? ?? {};
        final lat = (endLoc['lat'] as num?)?.toDouble() ?? curPos.latitude;
        final lng = (endLoc['lng'] as num?)?.toDouble() ?? curPos.longitude;
        final maneuver = s['maneuver'] as String? ?? 'straight';

        stepsList.add(PedestrianStep(
          instruction: cleanInst,
          streetName: '',
          distanceMeters: dist,
          durationSeconds: dur,
          endLat: lat,
          endLng: lng,
          modifier: maneuver,
        ));
      }

      _activeRoute = PedestrianRoute(
        destinationName: endAddress,
        totalDistanceMeters: totalDist,
        totalDurationSeconds: totalDur,
        steps: stepsList,
      );

      _currentStepIndex = 0;
      _approachingTurnSpoken = false;

      final distMeters = totalDist.round();
      final initialStep = stepsList.isNotEmpty ? stepsList.first.instruction : "Walk forward.";
      return "Starting Google Maps walking route to $endAddress, approximately $distMeters metres away. $initialStep";
    } catch (e) {
      debugPrint('[GoogleMaps] Error planning route: $e');
      return null;
    }
  }

  /// OpenStreetMap Nominatim Geocoding + OSRM Foot Routing Engine.
  Future<String?> _planWithOsmOsrm(String destinationQuery, Position curPos) async {
    try {
      // 1. Geocode destination using Nominatim with local proximity viewbox
      final client = HttpClient();
      final geocodeUri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(destinationQuery)}&format=json&limit=1&viewbox=${curPos.longitude - 0.25},${curPos.latitude + 0.25},${curPos.longitude + 0.25},${curPos.latitude - 0.25}&bounded=0',
      );
      final geocodeReq = await client.getUrl(geocodeUri);
      geocodeReq.headers.set('User-Agent', 'SightMate-AccessibilityApp/1.0');
      final geocodeRes = await geocodeReq.close().timeout(const Duration(seconds: 6));

      if (geocodeRes.statusCode != 200) {
        return _fallbackDirectNavigation(destinationQuery, curPos);
      }

      final geocodeBody = await geocodeRes.transform(utf8.decoder).join();
      final geocodeJson = jsonDecode(geocodeBody) as List;

      if (geocodeJson.isEmpty) {
        return _fallbackDirectNavigation(destinationQuery, curPos);
      }

      final targetLat = double.parse(geocodeJson[0]['lat'] as String);
      final targetLng = double.parse(geocodeJson[0]['lon'] as String);
      final displayName = geocodeJson[0]['display_name'] as String? ?? destinationQuery;
      final shortName = displayName.split(',').first;

      // Distance Sanity Check: reject distant locations (>25km) to prevent absurd distances/steps
      final straightLineDist = Geolocator.distanceBetween(
        curPos.latitude,
        curPos.longitude,
        targetLat,
        targetLng,
      );
      if (straightLineDist > 25000) {
        return "I found '$shortName', but it is ${(straightLineDist / 1000).round()} kilometres away, which is too far for walking navigation. Please specify a nearby destination.";
      }

      // 2. Query OSRM pedestrian foot routing
      final routeUri = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/${curPos.longitude},${curPos.latitude};$targetLng,$targetLat?overview=false&steps=true',
      );
      final routeReq = await client.getUrl(routeUri);
      routeReq.headers.set('User-Agent', 'SightMate-AccessibilityApp/1.0');
      final routeRes = await routeReq.close().timeout(const Duration(seconds: 6));

      if (routeRes.statusCode != 200) {
        return _fallbackDirectNavigation(shortName, curPos, targetLat, targetLng);
      }

      final routeBody = await routeRes.transform(utf8.decoder).join();
      final routeJson = jsonDecode(routeBody) as Map<String, dynamic>;

      final routes = routeJson['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        return _fallbackDirectNavigation(shortName, curPos, targetLat, targetLng);
      }

      final primary = routes[0] as Map<String, dynamic>;
      final totalDist = (primary['distance'] as num?)?.toDouble() ?? 0.0;
      if (totalDist > 30000) {
        return "The walking route to $shortName is ${(totalDist / 1000).round()} kilometres, which is too far for pedestrian navigation.";
      }

      final legs = primary['legs'] as List? ?? [];
      final stepsList = <PedestrianStep>[];

      for (final leg in legs) {
        for (final s in (leg['steps'] as List? ?? [])) {
          final maneuver = s['maneuver'] as Map<String, dynamic>? ?? {};
          final type = maneuver['type'] as String? ?? 'turn';
          final modifier = maneuver['modifier'] as String? ?? 'straight';
          final name = s['name'] as String? ?? '';
          final dist = (s['distance'] as num?)?.toDouble() ?? 0.0;
          final dur = (s['duration'] as num?)?.toDouble() ?? 0.0;
          final location = maneuver['location'] as List? ?? [0.0, 0.0];

          String inst = _formatManeuver(type, modifier, name, dist);
          stepsList.add(PedestrianStep(
            instruction: inst,
            streetName: name,
            distanceMeters: dist,
            durationSeconds: dur,
            endLat: (location.length > 1) ? (location[1] as num).toDouble() : targetLat,
            endLng: (location.isNotEmpty) ? (location[0] as num).toDouble() : targetLng,
            modifier: modifier,
          ));
        }
      }

      _activeRoute = PedestrianRoute(
        destinationName: shortName,
        totalDistanceMeters: (primary['distance'] as num?)?.toDouble() ?? 0.0,
        totalDurationSeconds: (primary['duration'] as num?)?.toDouble() ?? 0.0,
        steps: stepsList,
      );

      _currentStepIndex = 0;
      _approachingTurnSpoken = false;

      final distMeters = _activeRoute!.totalDistanceMeters.round();
      final initialStep = stepsList.isNotEmpty ? stepsList.first.instruction : "Walk forward.";
      return "Starting outdoor pedestrian route to $shortName, approximately $distMeters metres away. $initialStep";
    } catch (_) {
      return _fallbackDirectNavigation(destinationQuery, curPos);
    }
  }

  /// Update user progress on GPS coordinate stream.
  /// Returns a spoken turn instruction if a maneuver is reached, or null.
  String? onPositionUpdate(Position position) {
    if (_activeRoute == null || _currentStepIndex >= _activeRoute!.steps.length) {
      return null;
    }

    final step = _activeRoute!.steps[_currentStepIndex];
    final distToStepEnd = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      step.endLat,
      step.endLng,
    );

    // 1. Approaching prompt (12 metres before turn)
    if (distToStepEnd <= 12 && distToStepEnd > 4 && !_approachingTurnSpoken && step.distanceMeters > 20) {
      _approachingTurnSpoken = true;
      final nextIdx = _currentStepIndex + 1;
      if (nextIdx < _activeRoute!.steps.length) {
        final next = _activeRoute!.steps[nextIdx];
        return "In about 10 metres, prepare to ${next.modifier} onto ${next.streetName.isNotEmpty ? next.streetName : 'the path'}.";
      }
    }

    // 2. Step Completed: Advance maneuver
    if (distToStepEnd <= 6) {
      _currentStepIndex++;
      _approachingTurnSpoken = false;

      if (_currentStepIndex >= _activeRoute!.steps.length) {
        final dest = _activeRoute!.destinationName;
        _activeRoute = null;
        return "You have arrived at $dest. Outdoor navigation complete.";
      }

      final nextStep = _activeRoute!.steps[_currentStepIndex];
      return "${nextStep.instruction} Continue for ${nextStep.distanceMeters.round()} metres.";
    }

    return null;
  }

  /// Direct bearing fallback when network routing is offline.
  String _fallbackDirectNavigation(String dest, Position curPos, [double? targetLat, double? targetLng]) {
    if (targetLat != null && targetLng != null) {
      final dist = Geolocator.distanceBetween(curPos.latitude, curPos.longitude, targetLat, targetLng).round();
      final bearing = Geolocator.bearingBetween(curPos.latitude, curPos.longitude, targetLat, targetLng);
      final dirWord = CompassHelper.headingToWord((bearing + 360) % 360);
      return "Outdoor navigation to $dest active. Head $dirWord for approximately $dist metres.";
    }
    return "Navigating towards $dest. Head forward along the sidewalk.";
  }

  String _formatManeuver(String type, String modifier, String street, double dist) {
    final streetPart = street.isNotEmpty ? " onto $street" : "";
    final distPart = dist > 0 ? " for ${dist.round()} metres" : "";
    switch (type) {
      case 'turn':
        return "Turn $modifier$streetPart$distPart.";
      case 'depart':
        return "Head $modifier$streetPart$distPart.";
      case 'arrive':
        return "Arrive at destination.";
      default:
        return "Continue $modifier$streetPart$distPart.";
    }
  }

  /// Cancel current outdoor navigation.
  void stopNavigation() {
    _activeRoute = null;
    _currentStepIndex = 0;
    _approachingTurnSpoken = false;
  }
}
