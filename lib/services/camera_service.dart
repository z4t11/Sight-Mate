import 'dart:typed_data';
import 'dart:ui' as ui;
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

  /// Capture one frame, downscale to ≤768px on the longest side, return PNG bytes.
  /// Returns null if camera not ready or capture fails.
  Future<Uint8List?> captureFrame() async {
    if (!isReady) return null;
    try {
      final xfile = await _controller!.takePicture();
      final rawBytes = await xfile.readAsBytes();
      return await _resize(rawBytes, 768);
    } catch (_) {
      return null;
    }
  }

  /// Resize using Flutter's built-in codec (no extra packages).
  Future<Uint8List> _resize(Uint8List bytes, int maxDim) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: maxDim,
    );
    final frame = await codec.getNextFrame();
    final byteData =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return byteData!.buffer.asUint8List();
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
