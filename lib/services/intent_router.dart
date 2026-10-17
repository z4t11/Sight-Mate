import '../models/app_intent.dart';

/// Maps spoken text -> typed AppIntent.
/// Pattern matching; no ML needed for the demo command set.
class IntentRouter {
  AppIntent route(String text) {
    final t = text.toLowerCase().trim();

    // ── Stop (highest priority, check first) ──────────────────────
    if (t == 'stop' || t == 'stop talking' || t == 'quiet') {
      return AppIntent(type: AppIntentType.stopSpeech, rawText: text);
    }

    // ── Movie Mode ────────────────────────────────────────────────
    if (_contains(t, ['start movie mode', 'movie mode', 'cinema mode',
                       'start movie', 'enable movie'])) {
      return AppIntent(type: AppIntentType.movieMode, rawText: text,
          slot: 'start');
    }
    if (_contains(t, ['stop movie', 'end movie', 'exit movie'])) {
      return AppIntent(type: AppIntentType.movieMode, rawText: text,
          slot: 'stop');
    }

    // ── Navigation ────────────────────────────────────────────────
    if (_contains(t, ['take me to', 'navigate to', 'go to', 'directions to',
                       'how do i get to'])) {
      final dest = _extractAfter(t, [
        'take me to', 'navigate to', 'go to', 'directions to',
        'how do i get to',
      ]);
      return AppIntent(type: AppIntentType.navigate, rawText: text, slot: dest);
    }

    // ── Where am I ───────────────────────────────────────────────
    if (_contains(t, ['where am i', 'where are we', 'what floor',
                       'what room', 'my location'])) {
      return AppIntent(type: AppIntentType.whereAmI, rawText: text);
    }

    // ── More detail ───────────────────────────────────────────────
    if (_contains(t, ['more detail', 'tell me more', 'more info',
                       'explain more'])) {
      return AppIntent(type: AppIntentType.moreDetail, rawText: text);
    }

    // ── Verbosity setting ─────────────────────────────────────────
    if (_contains(t, ['verbosity', 'set to brief', 'set to normal',
                       'set to detailed', 'brief mode', 'detailed mode'])) {
      String? level;
      if (t.contains('brief'))    level = 'brief';
      if (t.contains('normal'))   level = 'normal';
      if (t.contains('detailed')) level = 'detailed';
      return AppIntent(type: AppIntentType.setVerbosity, rawText: text,
          slot: level);
    }

    // ── Camera question (default for anything descriptive) ────────
    if (_contains(t, ['what', 'describe', 'read', 'tell me', 'look',
                       'see', 'color', 'colour', 'how many', 'is there',
                       'any', 'who'])) {
      return AppIntent(type: AppIntentType.askCamera, rawText: text);
    }

    return AppIntent(type: AppIntentType.unknown, rawText: text);
  }

  bool _contains(String text, List<String> phrases) =>
      phrases.any((p) => text.contains(p));

  String _extractAfter(String text, List<String> prefixes) {
    for (final p in prefixes) {
      final idx = text.indexOf(p);
      if (idx != -1) {
        return text.substring(idx + p.length).trim();
      }
    }
    return text;
  }
}
