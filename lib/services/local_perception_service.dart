import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

/// Types of safety hazards detected by on-device computer vision.
enum LocalHazardType {
  pathBlocked,
  obstacleAhead,
  approachingObject,
  stepOrDropOffAhead,
  headHeightHazard,
  none,
}

/// Spoken alert information from the local perception layer.
class LocalHazardAlert {
  final LocalHazardType type;
  final String spokenWarning;
  final double confidence;
  final bool requiresImmediateStop;
  final DateTime timestamp;

  const LocalHazardAlert({
    required this.type,
    required this.spokenWarning,
    required this.confidence,
    this.requiresImmediateStop = false,
    required this.timestamp,
  });
}

/// Fast on-device computer vision perception layer (Section 4).
/// Analyzes camera frames locally in <50ms without network dependence,
/// detecting floor obstacles, path blockages, approaching objects, and steps.
class LocalPerceptionService {
  // Tracking state across consecutive frames (temporal smoothing)
  int _consecutiveHazardFrames = 0;
  LocalHazardType _lastDetectedType = LocalHazardType.none;
  double _lastObstacleOccupancy = 0.0;
  DateTime? _lastAlertTime;

  static const Duration _cooldown = Duration(milliseconds: 3000);

  /// Analyze a raw image frame (PNG or JPEG byte array) entirely on-device.
  /// Downscales to 120x90 thumbnail for sub-30ms execution on CPU.
  Future<LocalHazardAlert?> analyzeFrame(Uint8List frameBytes) async {
    try {
      // 1. Decode and downscale to low-res thumbnail for high-speed analysis
      final codec = await ui.instantiateImageCodec(
        frameBytes,
        targetWidth: 120,
        targetHeight: 90,
      );
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;

      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();

      if (byteData == null) return null;

      final pixels = byteData.buffer.asUint8List();
      const width = 120;
      const height = 90;

      // 2. Compute Corridor & Ground Plane Metrics
      // Walking corridor = central 40% (x from 36 to 84)
      // Ground plane = lower 40% (y from 54 to 90)
      // Middle corridor = y from 25 to 65

      int centralObstaclePixelCount = 0;
      int totalCentralPixels = 0;

      int horizontalEdgeCountLower = 0;
      int lowerGroundPixels = 0;

      // Horizontal edge detection & gradient analysis
      for (int y = 5; y < height - 5; y++) {
        for (int x = 5; x < width - 5; x++) {
          final isCentralCorridor = (x >= 36 && x <= 84);
          final isLowerGround = (y >= 54);

          final idx = (y * width + x) * 4;
          final r = pixels[idx];
          final g = pixels[idx + 1];
          final b = pixels[idx + 2];
          final lum = (0.299 * r + 0.587 * g + 0.114 * b);

          // Horizontal neighbor gradient
          final idxRight = (y * width + (x + 1)) * 4;
          final lumRight = (0.299 * pixels[idxRight] + 0.587 * pixels[idxRight + 1] + 0.114 * pixels[idxRight + 2]);
          final gradX = (lum - lumRight).abs();

          // Vertical neighbor gradient
          final idxDown = ((y + 1) * width + x) * 4;
          final lumDown = (0.299 * pixels[idxDown] + 0.587 * pixels[idxDown + 1] + 0.114 * pixels[idxDown + 2]);
          final gradY = (lum - lumDown).abs();

          final edgeStrength = gradX + gradY;

          if (isCentralCorridor) {
            totalCentralPixels++;
            // High gradient variance inside central corridor indicates an obstacle or person
            if (edgeStrength > 42.0) {
              centralObstaclePixelCount++;
            }
          }

          if (isLowerGround) {
            lowerGroundPixels++;
            // Strong horizontal edge in lower ground plane (stairs / step transition)
            if (gradY > 48.0 && gradX < 24.0) {
              horizontalEdgeCountLower++;
            }
          }
        }
      }

      final corridorOccupancy = totalCentralPixels > 0
          ? centralObstaclePixelCount / totalCentralPixels
          : 0.0;

      final stepIndicatorRatio = lowerGroundPixels > 0
          ? horizontalEdgeCountLower / lowerGroundPixels
          : 0.0;

      // 3. Classify Hazard Candidate
      LocalHazardType candidateType = LocalHazardType.none;
      String spokenWarning = '';
      bool immediateStop = false;
      double confidence = 0.0;

      // A: Step or Floor Level Change (repetitive horizontal boundary on floor)
      if (stepIndicatorRatio > 0.14) {
        candidateType = LocalHazardType.stepOrDropOffAhead;
        spokenWarning = "Possible step or change in floor level ahead.";
        confidence = math.min(1.0, stepIndicatorRatio * 5.0);
      }
      // B: Immediate Dense Blockage in Central Path
      else if (corridorOccupancy >= 0.58) {
        candidateType = LocalHazardType.pathBlocked;
        spokenWarning = "Stop. The path ahead is blocked.";
        immediateStop = true;
        confidence = 0.92;
      }
      // C: Approaching Obstacle / Person (rapidly expanding occupancy)
      else if (corridorOccupancy >= 0.38) {
        final isApproaching = (_lastObstacleOccupancy > 0.15 &&
            (corridorOccupancy - _lastObstacleOccupancy) > 0.12);

        if (isApproaching) {
          candidateType = LocalHazardType.approachingObject;
          spokenWarning = "Object approaching in your path.";
          confidence = 0.85;
        } else {
          candidateType = LocalHazardType.obstacleAhead;
          spokenWarning = "Obstacle ahead on your path.";
          confidence = 0.78;
        }
      }

      _lastObstacleOccupancy = corridorOccupancy;

      // 4. Temporal Smoothing (Filter single-frame noise)
      if (candidateType != LocalHazardType.none) {
        if (candidateType == _lastDetectedType) {
          _consecutiveHazardFrames++;
        } else {
          _consecutiveHazardFrames = 1;
          _lastDetectedType = candidateType;
        }
      } else {
        _consecutiveHazardFrames = 0;
        _lastDetectedType = LocalHazardType.none;
        return null;
      }

      // Require 2 consecutive frames for warnings (or immediate if critical stop)
      final bool meetsTemporalThreshold =
          immediateStop || _consecutiveHazardFrames >= 2;

      if (!meetsTemporalThreshold) {
        return null;
      }

      // Check cooldown
      final now = DateTime.now();
      if (_lastAlertTime != null && now.difference(_lastAlertTime!) < _cooldown) {
        if (!immediateStop) {
          return null; // Suppress routine repeat during cooldown
        }
      }

      _lastAlertTime = now;

      return LocalHazardAlert(
        type: candidateType,
        spokenWarning: spokenWarning,
        confidence: confidence,
        requiresImmediateStop: immediateStop,
        timestamp: now,
      );
    } catch (_) {
      return null;
    }
  }

  /// Reset tracking state when session ends or restarts.
  void reset() {
    _consecutiveHazardFrames = 0;
    _lastDetectedType = LocalHazardType.none;
    _lastObstacleOccupancy = 0.0;
    _lastAlertTime = null;
  }
}
