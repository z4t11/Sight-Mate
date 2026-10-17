/// Typed intents produced by the IntentRouter from spoken text.
enum AppIntentType {
  askCamera,    // "what's in front of me?", "describe this"
  whereAmI,     // "where am I?"
  navigate,     // "take me to ___"
  movieMode,    // "start movie mode"
  stopSpeech,   // "stop"
  setVerbosity, // "set verbosity to brief"
  moreDetail,   // "more detail"
  unknown,
}

class AppIntent {
  final AppIntentType type;
  /// Raw spoken query, preserved for downstream use (e.g., navigate target).
  final String rawText;
  /// Extracted slot, e.g. destination for navigate, level for verbosity.
  final String? slot;

  const AppIntent({
    required this.type,
    required this.rawText,
    this.slot,
  });

  @override
  String toString() => 'AppIntent(${type.name}, slot=$slot)';
}
