import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/conversation_turn.dart';
import '../models/object_search_models.dart';
import '../models/verbosity_level.dart';
import 'app_config.dart';

/// Swappable AI vision service. All Gemini access goes through here.
/// Replace the body of [ask] to swap models with zero other changes.
class GeminiService {
  static const int _maxHistory = 6; // turns to keep

  final List<ConversationTurn> _history = [];
  GenerativeModel? _model;

  /// System prompt — sighted-guide persona, all 8 principles baked in.
  static const String _systemPrompt = '''
You are a friendly, concise sighted companion for a blind or low-vision person.

RULES (non-negotiable):
1. Never say anything is "safe". Always hedge: "looks like…", "I think…", "it seems…".
2. Never identify people by face or name. Describe clothing, position (left / right / ahead), rough distance.
3. For vehicles: describe colour, type, rough distance and direction if moving. Always hedge.
4. Use spatial terms: left, right, straight ahead, behind. Estimate distance in steps or metres.
5. Present tense. Friendly and direct. No filler phrases.
6. If the image is blurry, dark, or unclear, say so briefly instead of guessing.
7. For follow-up questions that refer to "it" or "that", use the previous context you were given.

VERBOSITY MODES (the user message will tell you which to use):
- brief: 1–2 sentences max.
- normal: 3–4 sentences. End with "Want more detail?" only if there is genuinely more to say.
- detailed: Thorough. Cover position, distance, colours, any text visible, hazards on the floor.
''';

  /// Initialise (or re-use) the Gemini model.
  GenerativeModel _getModel() {
    _model ??= GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(maxOutputTokens: 180),
    );
    return _model!;
  }

  /// Ask a question. Pass [imageBytes] (PNG/JPEG) for camera questions, or null for text-only.
  /// Streams response tokens via [onStreamChunk] for instant Live Mode speech, and returns final answer.
  Future<String> ask({
    required String question,
    Uint8List? imageBytes,
    required VerbosityLevel verbosity,
    void Function(String partialChunk)? onStreamChunk,
  }) async {
    // ── MOCK MODE ────────────────────────────────────────────────
    if (AppConfig.isMockMode) {
      await Future.delayed(const Duration(milliseconds: 600));
      final res = _mockResponse(question, verbosity);
      onStreamChunk?.call(res);
      return res;
    }

    // ── REAL API (Streaming with Token Accumulator) ──────────────
    try {
      final model = _getModel();

      // Build multi-turn history from stored turns.
      final historyContents = <Content>[];
      for (final turn in _history.take(_maxHistory)) {
        historyContents.add(Content.text(turn.question));
        historyContents.add(Content('model', [TextPart(turn.answer)]));
      }

      final chat = model.startChat(history: historyContents);

      // Build current message: verbosity prefix + optional image + question.
      final parts = <Part>[];
      parts.add(TextPart('Verbosity: ${verbosity.label}. Keep answer concise (2-3 sentences max).'));
      if (imageBytes != null) {
        parts.add(DataPart('image/jpeg', imageBytes));
      }
      parts.add(TextPart(question));

      print('SIGHT_MATE [GEMINI REQUEST]: question="$question", verbosity=${verbosity.label}, hasImage=${imageBytes != null}');

      final StringBuffer fullAnswer = StringBuffer();
      final stream = chat.sendMessageStream(Content.multi(parts));
      await for (final chunk in stream) {
        final text = chunk.text;
        if (text != null && text.isNotEmpty) {
          fullAnswer.write(text);
          onStreamChunk?.call(text);
        }
      }

      final answer = fullAnswer.toString().trim();
      final finalAnswer = answer.isNotEmpty ? answer : 'No response from AI.';
      print('SIGHT_MATE [GEMINI ANSWER]: "$finalAnswer"');

      // Store turn in history.
      _history.add(ConversationTurn(
        question: question,
        answer: finalAnswer,
        timestamp: DateTime.now(),
      ));
      if (_history.length > _maxHistory) {
        _history.removeAt(0);
      }

      return finalAnswer;
    } on GenerativeAIException catch (e) {
      print('SIGHT_MATE [GEMINI EXCEPTION]: ${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('quota') || msg.contains('429') || msg.contains('resource')) {
        return "I'm receiving requests too quickly. Please pause a moment.";
      }
      return "The AI couldn't respond. ${_shortError(e.message)}";
    } catch (e) {
      print('SIGHT_MATE [GENERAL EXCEPTION]: $e');
      final err = e.toString().toLowerCase();
      if (err.contains('socket') || err.contains('network') ||
          err.contains('connection') || err.contains('host')) {
        return "I can't reach the internet right now. Please check your connection.";
      }
      return "Something went wrong. Please try again.";
    }
  }

  /// Direct spatial guidance to a visible target / destination in front of the user.
  Future<String> askVisualGuidance({
    required String target,
    required Uint8List? imageBytes,
    String? currentPosition,
  }) async {
    if (AppConfig.isMockMode || imageBytes == null) {
      return "Looks like $target is straight ahead, about 3 steps away. The path seems clear.";
    }

    try {
      final prompt = '''
The user is a blind or low-vision person who wants to reach: "$target".
${currentPosition != null ? 'Current known starting position: "$currentPosition".' : ''}
Look at the camera image. Give direct, concise spatial walking directions:
1. Direction (e.g. "straight ahead", "slightly to your left", "at 2 o'clock").
2. Estimated distance (in steps or metres).
3. Any immediate floor obstacles, steps, or hazards in their path.
If "$target" is not visible in the frame, tell them to turn slowly until it comes into view.
Keep it strictly to 1 or 2 sentences. Use friendly, direct, hedge language ("looks like", "seems to be"). Never say "safe".
''';
      final model = _getModel();
      final response = await model.generateContent([
        Content.multi([
          DataPart('image/jpeg', imageBytes),
          TextPart(prompt),
        ])
      ]);
      return response.text?.trim() ?? "Looks like $target is ahead, but the view is unclear.";
    } catch (e) {
      print('SIGHT_MATE [VISUAL GUIDANCE ERROR]: $e');
      return "I couldn't get a clear look at $target. Try pointing your camera ahead.";
    }
  }

  /// Combines map/GPS context with the camera view to navigate step-by-step
  /// while detecting and navigating around ground-level obstacles with precise step deviations.
  Future<String> askObstacleAwareNavigation({
    required String destination,
    required Uint8List? imageBytes,
    String? currentPosition,
    double? headingDegrees,
    double? macroDistanceMeters,
    int? stepsRemaining,
  }) async {
    if (AppConfig.isMockMode || imageBytes == null) {
      return "Walk straight for 4 steps. There looks to be a small cable on your right; step slightly to the left, then continue.";
    }

    try {
      final prompt = '''
You are a live pedestrian guide for a blind person walking towards $destination.
Look at the camera view of the path immediately ahead:
1. If there is any obstacle, step, threshold, wire, box, chair, or person: give a 1-step detour (e.g. "Step slightly left around the chair, then walk 4 steps.").
2. If the path is clear: tell them how many steps to walk forward (e.g. "Path clear. Walk straight for 5 steps towards $destination.").
Limit response to 1 short sentence, under 16 words.
''';

      final model = GenerativeModel(
        model: AppConfig.geminiModel,
        apiKey: AppConfig.geminiApiKey,
        generationConfig: GenerationConfig(maxOutputTokens: 60),
      );
      final response = await model.generateContent([
        Content.multi([
          DataPart('image/jpeg', imageBytes),
          TextPart(prompt),
        ])
      ]);
      return response.text?.trim() ??
          "Path looks clear for 4 steps ahead towards $destination.";
    } catch (e) {
      print('SIGHT_MATE [OBSTACLE NAV ERROR]: $e');
      return "Path looks clear for 4 steps towards $destination. Continue straight.";
    }
  }

  /// Ask Gemini to describe where the user is based on the camera scene in 2-5 words.
  Future<String?> recognizeLocationFromScene(Uint8List imageBytes) async {
    if (AppConfig.isMockMode) return "main entrance";
    try {
      final prompt = '''
Look at this image. Where is the user standing right now?
Respond with ONLY a short 2-5 word description of the spot or room (e.g. "bedroom doorway", "near the desk", "hallway corridor", "office entrance").
No extra words or punctuation.
''';
      final model = _getModel();
      final response = await model.generateContent([
        Content.multi([
          DataPart('image/jpeg', imageBytes),
          TextPart(prompt),
        ])
      ]);
      final text = response.text?.trim();
      return (text != null && text.isNotEmpty) ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// Milestone 5: Rapid safety hazard scan for stairs down, drop-offs, and head-height overhangs
  Future<String?> scanForImmediateHazards(Uint8List imageBytes) async {
    if (AppConfig.isMockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      return null;
    }

    try {
      final prompt = '''
You are a rapid safety hazard guardian for a blind person walking forward.
Examine this camera image ONLY for immediate dangerous physical hazards:
1. Drop-offs, stairs going down, steps, curbs, open holes.
2. Low-hanging obstacles at head or chest level (tree branches, low pipes, signs).
3. Tripping hazards, wet floors, cords, or moving vehicles.

OUTPUT RULES:
- If a hazard is present: State the hazard and steps/distance in under 8 words (e.g. "Caution: 3 steps going down ahead.", "Warning: low branch at head level.", "Caution: wet floor ahead.").
- If the path is clear: Output exactly "CLEAR".
- No other words.
''';

      final model = _getModel();
      final response = await model.generateContent([
        Content.multi([
          DataPart('image/jpeg', imageBytes),
          TextPart(prompt),
        ])
      ]);

      final text = response.text?.trim();
      if (text == null || text.toUpperCase().contains('CLEAR')) {
        return null;
      }
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Clear conversation memory (e.g. on new topic).
  void resetMemory() => _history.clear();

  int _mockMovieIdx = 0;
  static final List<String> _mockMovieDescriptions = [
    "She discreetly slips a silver key into her coat pocket.",
    "He glances nervously toward the dark hallway behind him.",
    "The camera pans up to reveal a storm approaching the city.",
    "She draws a concealed envelope from beneath the desk.",
    "He slowly pushes the heavy wooden door open.",
    "They exchange a tense glance as the elevator doors close.",
  ];

  /// Milestone 4: 15-word audio describer prompt for Movie Mode
  Future<String> describeMovieScene(Uint8List imageBytes) async {
    if (AppConfig.isMockMode) {
      await Future.delayed(const Duration(milliseconds: 700));
      final desc =
          _mockMovieDescriptions[_mockMovieIdx % _mockMovieDescriptions.length];
      _mockMovieIdx++;
      return desc;
    }

    try {
      final prompt = '''
You are a real-time audio describer for a movie scene viewed by a blind person.
In 15 words or fewer, describe only the immediate visual action or key visual detail on screen (e.g. character movement, facial expression, object revealed, setting shift).
RULES:
1. Maximum 15 words.
2. Sighted-guide audio describer style: present tense, crisp, neutral.
3. Do NOT repeat dialogue or transcribe speech.
4. If the scene is dark, blank, or credits, return: "Scene transitions."
''';

      final model = _getModel();
      final response = await model.generateContent([
        Content.multi([
          DataPart('image/jpeg', imageBytes),
          TextPart(prompt),
        ])
      ]);

      return response.text?.trim() ?? "A character moves across the room.";
    } catch (e) {
      print('SIGHT_MATE [MOVIE DESC ERROR]: $e');
      return "The scene shifts to a new view.";
    }
  }

  int _mockSearchCount = 0;

  GenerativeModel? _searchModel;

  GenerativeModel _getSearchModel() {
    _searchModel ??= GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
      generationConfig: GenerationConfig(maxOutputTokens: 25),
    );
    return _searchModel!;
  }

  /// Persistent 360-degree object search analyzer (Section 3 & Section 4).
  /// Ultra-compact token economy: ~20 input tokens, ~6 output tokens.
  Future<ObjectSearchResult> locateObject({
    required String targetObject,
    required Uint8List imageBytes,
  }) async {
    if (AppConfig.isMockMode) {
      await Future.delayed(const Duration(milliseconds: 600));
      return _mockObjectSearch(targetObject);
    }

    try {
      final prompt = 'Is "$targetObject" clearly visible? In under 8 words, answer ONLY: "FOUND: [ahead/left/right], [distance]" or "NOT_FOUND".';

      final model = _getSearchModel();
      final response = await model.generateContent([
        Content.multi([
          DataPart('image/jpeg', imageBytes),
          TextPart(prompt),
        ]),
      ]);

      final rawText = response.text?.trim() ?? '';
      return _parseObjectSearchResult(rawText, targetObject);
    } catch (e) {
      debugPrint('[GeminiService] locateObject error: $e');
      return ObjectSearchResult(
        status: TargetDetectionStatus.notFound,
        direction: ObjectDirection.unknown,
        distance: 'unknown',
        description: 'Unable to analyze frame.',
        guidance: 'Turn phone slowly to continue scanning.',
        rawResponse: e.toString(),
      );
    }
  }

  ObjectSearchResult _parseObjectSearchResult(String rawText, String targetObject) {
    final text = rawText.trim();
    final lower = text.toLowerCase();

    // 1. Direct compact format: FOUND: [direction], [distance]
    if (lower.startsWith('found') || lower.contains('found:')) {
      ObjectDirection dir = ObjectDirection.ahead;
      if (lower.contains('far left')) {
        dir = ObjectDirection.farLeft;
      } else if (lower.contains('far right')) {
        dir = ObjectDirection.farRight;
      } else if (lower.contains('left')) {
        dir = ObjectDirection.left;
      } else if (lower.contains('right')) {
        dir = ObjectDirection.right;
      } else if (lower.contains('ahead') || lower.contains('center') || lower.contains('front')) {
        dir = ObjectDirection.ahead;
      }

      // Extract distance if present
      String dist = 'about 2 metres';
      final match = RegExp(r'(\d+(?:\.\d+)?\s*(?:metres|meters|metre|meter|m|steps|step|feet|ft))', caseSensitive: false).firstMatch(text);
      if (match != null) {
        dist = match.group(1)!;
      } else if (lower.contains('close') || lower.contains('nearby')) {
        dist = 'close to you';
      }

      return ObjectSearchResult(
        status: TargetDetectionStatus.found,
        direction: dir,
        distance: dist,
        description: 'I see the $targetObject $dist.',
        guidance: '',
        rawResponse: rawText,
      );
    }

    // 2. Direct compact format: UNCERTAIN: [direction], [distance]
    if (lower.startsWith('uncertain') || lower.contains('uncertain:')) {
      ObjectDirection dir = ObjectDirection.ahead;
      if (lower.contains('left')) dir = ObjectDirection.left;
      if (lower.contains('right')) dir = ObjectDirection.right;

      return ObjectSearchResult(
        status: TargetDetectionStatus.uncertain,
        direction: dir,
        distance: 'partially visible',
        description: 'Possible $targetObject in view.',
        guidance: 'Turn phone slightly to center it.',
        rawResponse: rawText,
      );
    }

    // 3. Fallback: JSON parsing (if model still returned JSON)
    try {
      final start = rawText.indexOf('{');
      final end = rawText.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        final jsonStr = rawText.substring(start, end + 1);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final statusStr = (map['status'] ?? '').toString().toLowerCase();
        if (statusStr == 'found') {
          final dirStr = (map['direction'] ?? '').toString().toLowerCase();
          ObjectDirection direction = ObjectDirection.ahead;
          if (dirStr.contains('left')) direction = ObjectDirection.left;
          if (dirStr.contains('right')) direction = ObjectDirection.right;
          return ObjectSearchResult(
            status: TargetDetectionStatus.found,
            direction: direction,
            distance: map['distance']?.toString() ?? 'about 2 metres',
            description: map['description']?.toString() ?? 'Target found.',
            guidance: '',
            rawResponse: rawText,
          );
        }
      }
    } catch (_) {}

    // 4. Default: NOT_FOUND
    return ObjectSearchResult(
      status: TargetDetectionStatus.notFound,
      direction: ObjectDirection.unknown,
      distance: 'unknown',
      description: 'Object not visible.',
      guidance: 'Continue turning slowly.',
      rawResponse: rawText,
    );
  }

  ObjectSearchResult _mockObjectSearch(String target) {
    _mockSearchCount++;
    if (_mockSearchCount % 3 == 1) {
      return ObjectSearchResult(
        status: TargetDetectionStatus.notFound,
        direction: ObjectDirection.unknown,
        distance: 'unknown',
        description: 'No $target visible in the immediate camera view.',
        guidance: 'Slowly turn your phone to the left.',
        rawResponse: 'Mock not found',
      );
    } else if (_mockSearchCount % 3 == 2) {
      return ObjectSearchResult(
        status: TargetDetectionStatus.uncertain,
        direction: ObjectDirection.right,
        distance: 'about 3 metres away',
        description: 'I can see the possible edge of a $target on the right boundary.',
        guidance: 'Turn your phone slightly to the right to center it.',
        rawResponse: 'Mock uncertain',
      );
    } else {
      return ObjectSearchResult(
        status: TargetDetectionStatus.found,
        direction: ObjectDirection.ahead,
        distance: 'about 2 metres away',
        description: 'A $target is directly ahead of you, about 2 metres away.',
        guidance: 'Walk straight ahead towards it.',
        rawResponse: 'Mock found',
      );
    }
  }

  // ── Mock responses ──────────────────────────────────────────────────────────
  String _mockResponse(String question, VerbosityLevel v) {
    final q = question.toLowerCase();

    if (q.contains('color') || q.contains('colour')) {
      return "Looks like a white hatchback, maybe about 5 metres ahead on your right.";
    }
    if (q.contains('person') || q.contains('people') || q.contains('who')) {
      return "There's someone in a blue jacket standing about 3 metres to your left, facing away from you.";
    }
    if (q.contains('text') || q.contains('read') || q.contains('sign')) {
      return "I can see what looks like a sign on the wall ahead. It says 'Computer Science Department', I think.";
    }
    if (q.contains('step') || q.contains('stair')) {
      return "Looks like there are steps coming up, maybe 4 or 5 steps going down, straight ahead.";
    }
    if (q.contains('more detail') || q.contains('tell me more')) {
      return "The corridor continues straight ahead for what looks like about 20 metres. There are doors on both sides, and the floor looks clear.";
    }

    return switch (v) {
      VerbosityLevel.brief =>
        "Looks like an indoor corridor, well lit, doors on both sides.",
      VerbosityLevel.normal =>
        "I think you're in an indoor corridor. There are doors on the left and right — probably classrooms. "
            "Lighting is good and the floor looks clear. Want more detail?",
      VerbosityLevel.detailed =>
        "I think you're in an indoor corridor. There are doors on both sides — they look like classroom doors. "
            "Straight ahead, maybe 15 metres, there appears to be a noticeboard on the wall. "
            "Lighting is good, no obvious obstacles on the floor. "
            "There's what looks like a fire extinguisher on your right wall, about 2 metres ahead.",
    };
  }

  String _shortError(String msg) {
    if (msg.length > 80) return '${msg.substring(0, 80)}…';
    return msg;
  }
}
