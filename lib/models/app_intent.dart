/// Typed intents produced by the IntentRouter from spoken text.
enum AppIntentType {
  askCamera,    // "what's in front of me?", "describe this"
  whereAmI,     // "where am I?"
  navigate,     // "take me to ___"
  setLocation,  // "I am at ___", "I'm in ___", "start at ___"
  signBridgeMode, // "sign language", "bridge mode", "translate signs"
  movieMode,    // "start movie mode"
  safetyGuardian, // "start safety mode", "guardian mode", "watch for hazards"
  emergencySos,   // "emergency", "help", "send sos", "share location"
  runDiagnostics, // "run diagnostics", "system test", "check health", "test log"
  recordRoute,    // "record a route", "map a route", "scan route", "save route"
  readSign,       // "read the signboard", "what does the notice say", "read text"
  findObject,     // "find a chair", "where is the door", "locate my bag"
  switchFindObject, // "find the door instead", "switch to chair"
  continueSearch, // "keep looking", "continue searching"
  stopSearch,     // "stop searching", "cancel search"
  scanTurnCommand, // "turn left", "turn right"
  stopSpeech,   // "stop"
  confirmExit,  // "I am outside", "I've exited", "I stepped outside"
  confirmEntry, // "I am inside", "I entered the building", "I am indoors"
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
