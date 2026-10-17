/// Verbosity levels for TTS responses.
enum VerbosityLevel {
  brief,   // ≤2 sentences
  normal,  // 3–4 sentences
  detailed // full description
}

extension VerbosityLevelX on VerbosityLevel {
  String get label {
    switch (this) {
      case VerbosityLevel.brief:    return 'brief';
      case VerbosityLevel.normal:   return 'normal';
      case VerbosityLevel.detailed: return 'detailed';
    }
  }

  static VerbosityLevel fromString(String s) {
    switch (s.toLowerCase()) {
      case 'brief':    return VerbosityLevel.brief;
      case 'detailed': return VerbosityLevel.detailed;
      default:         return VerbosityLevel.normal;
    }
  }
}
