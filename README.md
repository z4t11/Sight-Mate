# Sight Mate

Voice-controlled camera companion for blind and low-vision users. Class project — demo reliability over scale.

## Features (by milestone)
- **M1**: Tap-to-listen, TTS reply, "Stop", haptics, verbosity setting
- **M2**: Camera Q&A via Gemini, conversation memory
- **M3**: Indoor navigation — OCR positioning + Dijkstra routing
- **M4**: Movie Mode — audio-gated visual descriptions in dialogue gaps
- **M5**: Safety alerts, test log, limitations report

## Quick Start
1. Copy `.env` and fill in `GEMINI_API_KEY`. Set `MOCK_MODE=true` for offline demo.
2. `flutter pub get`
3. `flutter run`

## Folder Structure
```
lib/services/    GeminiService, TtsService, SttService, HapticService, IntentRouter
lib/models/      VerbosityLevel, AppIntent, MapNode, MapEdge, NavState
lib/screens/     HomeScreen, AboutScreen, NavScreen, MovieScreen, TestLogScreen
lib/utils/       Dijkstra, CompassHelper, Throttle
assets/maps/     campus_map.json
```

## Notes
- MOCK_MODE in .env disables real API calls — safe for demo with no internet.
- App never stores camera frames or audio.
- Not a safety device. See About screen.
