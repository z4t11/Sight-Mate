import '../models/app_intent.dart';

/// Maps spoken text -> typed AppIntent.
/// Pattern matching; no ML needed for the demo command set.
class IntentRouter {
  AppIntent route(String text) {
    final t = text.toLowerCase().trim();

    // ── Stop Object Search (Explicit cancel) ──────────────────────
    if (_contains(t, [
      'stop searching', 'cancel search', 'stop looking', 'end search', 'cancel looking',
    ])) {
      return AppIntent(type: AppIntentType.stopSearch, rawText: text);
    }

    // ── Stop (highest priority, check first) ──────────────────────
    if (t == 'stop' || t == 'stop talking' || t == 'quiet' || t == 'cancel') {
      return AppIntent(type: AppIntentType.stopSpeech, rawText: text);
    }

    // ── Building Exit / Entry Confirmation ────────────────────────
    if (_contains(t, [
      'i am outside', "i'm outside", 'stepped outside', 'i reached outside',
      'i have exited', "i've exited", 'exit confirmed',
    ])) {
      return AppIntent(type: AppIntentType.confirmExit, rawText: text);
    }
    if (_contains(t, [
      'i am inside', "i'm inside", 'entered the building', 'i reached inside',
      'i am indoors', "i'm indoors", 'entered building', 'inside the building',
    ])) {
      return AppIntent(type: AppIntentType.confirmEntry, rawText: text);
    }

    // ── Resume Object Search ("Keep looking") ──────────────────────
    if (_contains(t, [
      'keep looking', 'keep searching', 'continue searching',
      'continue looking', 'keep tracking', 'look again', 'find it again',
    ])) {
      return AppIntent(type: AppIntentType.continueSearch, rawText: text);
    }

    // ── Scan Turn Direction ("Turn left" / "Turn right") ──────────
    if (t == 'turn left' || t == 'scan left' || t == 'look left' || t == 'pan left') {
      return AppIntent(type: AppIntentType.scanTurnCommand, rawText: text, slot: 'left');
    }
    if (t == 'turn right' || t == 'scan right' || t == 'look right' || t == 'pan right') {
      return AppIntent(type: AppIntentType.scanTurnCommand, rawText: text, slot: 'right');
    }

    // ── Switch Object Search Target ("Find the door instead") ─────
    if (t.contains('instead') || t.startsWith('switch to')) {
      final obj = _extractTargetObject(t);
      if (obj.isNotEmpty) {
        return AppIntent(type: AppIntentType.switchFindObject, rawText: text, slot: obj);
      }
    }

    // ── Emergency SOS (Priority 2) ────────────────────────────────
    if (_contains(t, [
      'emergency', 'help', 'send sos', 'i need help', 'sos',
      'share my location', 'send my location', 'alert someone',
    ])) {
      return AppIntent(type: AppIntentType.emergencySos, rawText: text);
    }

    // ── Safety Guardian Mode ──────────────────────────────────────
    if (_contains(t, [
      'stop safety mode', 'exit safety mode', 'end safety mode',
      'stop guardian', 'stop safety',
    ])) {
      return AppIntent(
          type: AppIntentType.safetyGuardian, rawText: text, slot: 'stop');
    }
    if (_contains(t, [
      'start safety mode', 'safety mode', 'guardian mode', 'watch for hazards',
      'hazard scan', 'hazard mode', 'safety guardian', 'scan hazards',
    ])) {
      return AppIntent(
          type: AppIntentType.safetyGuardian, rawText: text, slot: 'start');
    }

    // ── Diagnostics / Self-Test ───────────────────────────────────
    if (_contains(t, [
      'run diagnostics', 'system test', 'check health', 'test log',
      'test app', 'self test', 'diagnostics', 'health check',
    ])) {
      return AppIntent(type: AppIntentType.runDiagnostics, rawText: text);
    }

    // ── Route Recorder Mode ("Scan & Save") ─────────────────────────
    if (_contains(t, [
      'record a route', 'record route', 'map a route', 'map route',
      'scan route', 'save route', 'save a route', 'scan and save',
      'record path', 'record hallway', 'start route recording',
    ])) {
      return AppIntent(type: AppIntentType.recordRoute, rawText: text);
    }

    // ── Sign Language Bridge Mode ─────────────────────────────────
    if (_contains(t, [
      'sign language', 'sign mode', 'bridge mode', 'translate signs',
      'deaf mode', 'mute mode', 'sign to voice', 'start sign', 'hand sign',
      'enable sign mode', 'switch to sign mode', 'activate sign mode',
      'open sign mode'
    ])) {
      return AppIntent(type: AppIntentType.signBridgeMode, rawText: text);
    }

    // ── Movie Mode ────────────────────────────────────────────────
    if (_contains(t, [
      'start movie mode', 'movie mode', 'cinema mode', 'start movie',
      'enable movie', 'open movie mode', 'switch to movie mode',
      'audio describer', 'movie describer', 'describe movie',
      'cinema companion', 'watch movie', 'watching a movie',
    ])) {
      return AppIntent(type: AppIntentType.movieMode, rawText: text,
          slot: 'start');
    }
    if (_contains(t, ['stop movie', 'end movie', 'exit movie', 'close movie'])) {
      return AppIntent(type: AppIntentType.movieMode, rawText: text,
          slot: 'stop');
    }

    // ── Set Location / Origin ─────────────────────────────────────
    if (_contains(t, [
      'i am standing at', "i'm standing at",
      'i am at', "i'm at", 'i am in', "i'm in",
      'start from', 'start at', 'my location is', 'set location to',
    ])) {
      final loc = _extractAfter(t, [
        'i am standing at', "i'm standing at",
        'i am at', "i'm at", 'i am in', "i'm in",
        'start from', 'start at', 'my location is', 'set location to',
      ]);
      return AppIntent(type: AppIntentType.setLocation, rawText: text, slot: loc);
    }

    // ── Navigation ────────────────────────────────────────────────
    if (_contains(t, [
      'take me to', 'navigate me to', 'navigate to', 'guide me to',
      'take me', 'directions to', 'how do i get to', 'go to', 'walk to',
      'lead me to', 'navigate from', 'route from', 'how to reach',
    ])) {
      final dest = _extractAfter(t, [
        'take me to', 'navigate me to', 'navigate to', 'guide me to',
        'take me', 'directions to', 'how do i get to', 'go to', 'walk to',
        'lead me to', 'navigate from', 'route from', 'how to reach',
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

    // ── Dedicated Signboard & Noticeboard OCR Reading (Section 4) ─
    if (_contains(t, [
      'read the sign', 'read signboard', 'read the signboard',
      'what does that sign say', 'what does the sign say',
      'what does that notice say', 'what does the notice say',
      'read notice', 'read the notice', 'read board', 'read the board',
      'read poster', 'read the poster', 'read text on', 'read label',
    ])) {
      return AppIntent(type: AppIntentType.readSign, rawText: text);
    }

    // ── Persistent 360° Object Search ("Find a chair", "Where is the door") ─
    if (_isFindObjectQuery(t)) {
      final obj = _extractTargetObject(t);
      if (obj.isNotEmpty) {
        return AppIntent(type: AppIntentType.findObject, rawText: text, slot: obj);
      }
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
        var res = text.substring(idx + p.length).trim();
        res = res.replaceAll(RegExp(r'[\?\.\!]$'), '').trim();
        if (res.startsWith('the ')) res = res.substring(4).trim();
        if (res.startsWith('a ')) res = res.substring(2).trim();
        if (res.startsWith('an ')) res = res.substring(3).trim();
        return res;
      }
    }
    return text;
  }

  bool _isFindObjectQuery(String t) {
    if (t.startsWith('take me') ||
        t.startsWith('navigate') ||
        t.startsWith('guide me') ||
        t.startsWith('walk to') ||
        t.startsWith('directions to')) {
      return false;
    }
    return _contains(t, [
      'find a ', 'find the ', 'find my ', 'find an ', 'find ',
      'where is a ', 'where is the ', 'where is my ', 'where are my ', 'where are the ', 'where is ',
      'locate a ', 'locate the ', 'locate my ', 'locate an ', 'locate ',
      'look for a ', 'look for the ', 'look for my ', 'look for an ', 'look for ',
      'search for a ', 'search for the ', 'search for my ', 'search for an ', 'search for ',
      'spot the ', 'spot a ', 'can you find ', 'help me find ',
    ]);
  }

  String _extractTargetObject(String text) {
    var clean = text.toLowerCase().trim();
    clean = clean.replaceAll('instead', '').replaceAll('switch to', '').trim();

    final prefixes = [
      'can you find a ', 'can you find the ', 'can you find an ', 'can you find ',
      'help me find a ', 'help me find the ', 'help me find an ', 'help me find ',
      'where are my ', 'where are the ', 'where is my ', 'where is the ', 'where is a ', 'where is an ', 'where is ',
      'look for a ', 'look for the ', 'look for my ', 'look for an ', 'look for ',
      'search for a ', 'search for the ', 'search for my ', 'search for an ', 'search for ',
      'locate a ', 'locate the ', 'locate my ', 'locate an ', 'locate ',
      'find a ', 'find the ', 'find my ', 'find an ', 'find ',
      'spot a ', 'spot the ', 'spot an ', 'spot ',
    ];

    for (final p in prefixes) {
      if (clean.startsWith(p)) {
        clean = clean.substring(p.length).trim();
        break;
      }
    }

    clean = clean.replaceAll(RegExp(r'[\?\.\!]$'), '').trim();

    final suffixes = [
      ' for me',
      ' for us',
      ' please',
      ' around here',
      ' in here',
      ' here',
      ' right now',
    ];
    for (final s in suffixes) {
      if (clean.endsWith(s)) {
        clean = clean.substring(0, clean.length - s.length).trim();
      }
    }

    if (clean.startsWith('a ')) clean = clean.substring(2).trim();
    if (clean.startsWith('an ')) clean = clean.substring(3).trim();
    if (clean.startsWith('the ')) clean = clean.substring(4).trim();
    return clean;
  }
}
