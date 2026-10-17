# DECISIONS.md
One-line log of design choices made during development.

- 2026-10-13: Package `com.example.sight_mate`, min SDK 24, Flutter 3.47.7
- 2026-10-13: MOCK_MODE=true in .env enables offline demo with fake AI responses
- 2026-10-13: Flat services/ folder chosen over sub-grouped for demo simplicity
- 2026-10-13: Gemini API behind GeminiService (swappable); google_generative_ai package
- 2026-10-13: IntentRouter maps spoken text to typed intents before dispatching
- 2026-10-13: Verbosity levels: brief/normal/detailed; stored in SharedPreferences
- 2026-10-13: "Stop" command halts TTS immediately via flutter_tts.stop()
- 2026-10-13: Whole screen is one Semantics tap target (Principle 1)
- 2026-10-14: Installed NDK 28.2.13676358 via Android CLI to support native JNI builds
- 2026-10-14: Upgraded camera to ^0.12.1 and vibration to ^3.2.1 for Android SDK 36 compatibility
- 2026-10-14: Removed conflicting record package from pubspec until Milestone 4
- 2026-10-14: Enforced compileSdk = 36 for subprojects to satisfy modern androidx lifecycle constraints
- 2026-10-14: M2: CameraService uses dart:ui resize to 768px PNG — no extra package needed
- 2026-10-14: M2: GeminiService uses gemini-1.5-flash; conversation history capped at 6 turns
- 2026-10-14: M2: Camera preview shown at 25% opacity as background — useful for demo, invisible for TalkBack
- 2026-10-14: M2: Verbosity injected as text prefix in each Gemini message (not re-init model)
- 2026-10-14: M3: Campus map as JSON graph in assets/maps/campus_map.json — 12 sample nodes, bidirectional edges
- 2026-10-14: M3: Positioning via OCR sign-matching (MLKit) + magnetometer heading + pedometer steps
- 2026-10-14: M3: Dijkstra uses simple list-scan (no PriorityQueue) — sufficient for small campus graphs
- 2026-10-14: M3: NavigationService gives one instruction at a time with relative direction + hazard warnings
- 2026-10-14: M3: Low confidence triggers confirmation prompt ("I think you're near Room 204, is that right?")
- 2026-10-14: M3: Mock mode auto-places user at entrance, routes work on sample map without sensors
- 2026-10-15: Updated Gemini vision model from gemini-1.5-flash to gemini-2.5-flash for current API support
- 2026-10-16: Updated Gemini vision model to gemini-3.8-flash per Google API requirement for new users
- 2026-10-16: Switched default vision model to `gemini-3.5-flash-lite` (configurable via `GEMINI_MODEL` in `.env`): 2x higher rate limit (30 RPM vs 15 RPM), 4x token bandwidth (4M TPM vs 1M TPM), and 3x faster response speed (~1.9s vs ~6s) on the free tier.
- 2026-10-18: Latency optimization: STT silence detection reduced from 4.0s to 1.4s with search mode; CameraService switched to direct hardware JPEG bytes (bypassing slow 800ms software PNG re-encoding and cutting network payload by 80%).
- 2026-10-18: Positioning & Navigation enhancement: Added spoken location setting ("I am at Point A"), Gemini visual scene relocalization for "Where am I?", and dual-layer navigation: campus graph Dijkstra routing for campus nodes, plus Gemini visual spatial micro-guidance for real-world visible targets (e.g. Point A -> Point B, doors, objects).
