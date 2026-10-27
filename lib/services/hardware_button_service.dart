import 'package:flutter/services.dart';

enum HardwareButton {
  volumeUp, // Double-click Volume Up: Speak / Push-to-Talk / Ask Question
  volumeDown, // Double-click Volume Down: Stop Speech / Cancel / Exit Mode
}

typedef HardwareButtonCallback = bool Function(HardwareButton button);

/// Intercepts physical hardware keys (Volume Up & Down) with double-click detection.
///
/// Features:
/// - Single clicks: Adjust Android media volume up/down normally.
/// - Double-click Volume Up: Speak / Ask a question in any mode.
/// - Double-click Volume Down: Instant Stop or Exit dedicated mode.
class HardwareButtonService {
  static final HardwareButtonService _instance =
      HardwareButtonService._internal();
  factory HardwareButtonService() => _instance;
  HardwareButtonService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.example.sight_mate/hardware_buttons');

  final List<HardwareButtonCallback> _listeners = [];
  bool _initialized = false;
  int _lastUpPressTime = 0;
  int _lastDownPressTime = 0;

  void init() {
    if (_initialized) return;
    _initialized = true;

    // 1. Android Native MethodChannel listener (fires on double-click from MainActivity)
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onVolumeUpDoubleTap':
        case 'onVolumeUp':
          _notify(HardwareButton.volumeUp);
          break;
        case 'onVolumeDownDoubleTap':
        case 'onVolumeDown':
          _notify(HardwareButton.volumeDown);
          break;
      }
    });

    // 2. Flutter HardwareKeyboard listener (Desktop, Emulators, Physical Keyboards)
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Dev shortcut keys ('S' = Speak, 'X' = Stop/Exit)
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      _notify(HardwareButton.volumeUp);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyX) {
      _notify(HardwareButton.volumeDown);
      return true;
    }

    // Physical Volume Keys on keyboard / desktop: require double-tap within 450ms
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      if (now - _lastUpPressTime < 450) {
        _lastUpPressTime = 0;
        _notify(HardwareButton.volumeUp);
        return true;
      }
      _lastUpPressTime = now;
      return false; // let single click adjust volume
    }

    if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      if (now - _lastDownPressTime < 450) {
        _lastDownPressTime = 0;
        _notify(HardwareButton.volumeDown);
        return true;
      }
      _lastDownPressTime = now;
      return false; // let single click adjust volume
    }

    return false;
  }

  void addListener(HardwareButtonCallback listener) {
    init();
    _listeners.add(listener);
  }

  void removeListener(HardwareButtonCallback listener) {
    _listeners.remove(listener);
  }

  void _notify(HardwareButton button) {
    // Notify in reverse order so the topmost active screen receives it first
    for (final listener
        in List<HardwareButtonCallback>.from(_listeners.reversed)) {
      final handled = listener(button);
      if (handled) break; // Consumed
    }
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _listeners.clear();
    _initialized = false;
  }
}
