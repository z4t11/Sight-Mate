import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central config loaded from .env.
/// MOCK_MODE=true → all services return fake data (offline demo).
class AppConfig {
  static bool get isMockMode =>
      dotenv.env['MOCK_MODE']?.toLowerCase() == 'true';

  static String get geminiApiKey =>
      dotenv.env['GEMINI_API_KEY'] ?? '';

  /// Default to 'gemini-3.5-flash-lite' for 2x higher rate limits (30 RPM vs 15 RPM)
  /// and 3x faster response latency on Google AI free tier.
  static String get geminiModel =>
      dotenv.env['GEMINI_MODEL']?.isNotEmpty == true
          ? dotenv.env['GEMINI_MODEL']!
          : 'gemini-3.5-flash-lite';
}
