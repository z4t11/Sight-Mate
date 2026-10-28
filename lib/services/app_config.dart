import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central config loaded from .env.
/// MOCK_MODE=true → all services return fake data (offline demo).
class AppConfig {
  static bool get isMockMode =>
      dotenv.env['MOCK_MODE']?.toLowerCase() == 'true';

  static String get geminiApiKey =>
      dotenv.env['GEMINI_API_KEY'] ?? '';

  /// Google Maps Platform API Key (from Google Cloud Console, starts with 'AIza...').
  static String get googleMapsApiKey =>
      dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  /// True if a dedicated Google Maps Platform key is configured.
  static bool get hasGoogleMapsApiKey =>
      googleMapsApiKey.trim().isNotEmpty && googleMapsApiKey.startsWith('AIza');

  /// Default to 'gemini-3.5-flash' for ultra-fast multimodal response latency.
  static String get geminiModel =>
      dotenv.env['GEMINI_MODEL']?.isNotEmpty == true
          ? dotenv.env['GEMINI_MODEL']!
          : 'gemini-3.5-flash';
}
