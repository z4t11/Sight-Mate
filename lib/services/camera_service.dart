import 'dart:typed_data';
import 'package:camera/camera.dart';

/// Handles camera initialisation and single-frame capture.
/// Principle 9: frames are processed transiently, never saved.
class CameraService {
  CameraController? _controller;
  bool _initialized = false;

  CameraController? get controller => _controller;
  bool get isReady =>
      _initialized &&
      _controller != null &&
      (_controller?.value.isInitialized ?? false);

  Future<void> init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        back,
        ResolutionPreset.medium, // ~720p — enough for Gemini, fast to capture
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  /// Capture one frame as JPEG bytes (~720p from hardware ISP).
  /// Fast and lightweight — no software PNG re-encoding overhead.
  /// Returns null if camera not ready or capture fails.
  Future<Uint8List?> captureFrame() async {
    if (!isReady) return null;
    try {
      final xfile = await _controller!.takePicture();
      return await xfile.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    _initialized = false;
    final c = _controller;
    _controller = null;
    try {
      await c?.dispose();
    } catch (_) {}
  }
}
