import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/conversation_turn.dart';
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
      generationConfig: GenerationConfig(maxOutputTokens: 1000),
    );
    return _model!;
  }

  /// Ask a question. Pass [imageBytes] (PNG) for camera questions, or null for text-only.
  /// Returns a short spoken answer, or an error string the caller can speak directly.
  Future<String> ask({
    required String question,
    Uint8List? imageBytes,
    required VerbosityLevel verbosity,
  }) async {
    // ── MOCK MODE ────────────────────────────────────────────────
    if (AppConfig.isMockMode) {
      await Future.delayed(const Duration(milliseconds: 900));
      return _mockResponse(question, verbosity);
    }

    // ── REAL API ─────────────────────────────────────────────────
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
      parts.add(TextPart('Verbosity: ${verbosity.label}.'));
      if (imageBytes != null) {
        parts.add(DataPart('image/jpeg', imageBytes));
      }
      parts.add(TextPart(question));

      print('SIGHT_MATE [GEMINI REQUEST]: question="$question", verbosity=${verbosity.label}, hasImage=${imageBytes != null}');
      final response = await chat.sendMessage(Content.multi(parts));
      final answer = response.text?.trim() ?? 'No response from AI.';
      print('SIGHT_MATE [GEMINI ANSWER]: "$answer"');

      // Store turn in history.
      _history.add(ConversationTurn(
        question: question,
        answer: answer,
        timestamp: DateTime.now(),
      ));
      if (_history.length > _maxHistory) {
        _history.removeAt(0);
      }

      return answer;
    } on GenerativeAIException catch (e) {
      print('SIGHT_MATE [GEMINI EXCEPTION]: ${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('quota') || msg.contains('429') || msg.contains('resource')) {
        return "I'm getting too many requests right now. Please try again in a moment.";
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
      final contextItems = <String>[
        'Destination: "$destination"',
        if (currentPosition != null) 'Current Spot: "$currentPosition"',
        if (macroDistanceMeters != null)
          'GPS Distance: ${macroDistanceMeters.round()}m',
        if (stepsRemaining != null) 'Map steps: ~$stepsRemaining steps',
        if (headingDegrees != null) 'Heading: ${headingDegrees.round()}°',
      ];

      final prompt = '''
You are a live sighted-navigation companion walking with a blind or low-vision pedestrian.
Navigation Context: ${contextItems.join(', ')}.

Analyze the user's camera view of the walkway directly ahead:
1. OBSTACLE SCAN: Closely inspect the floor, ground, and knee-level path for ANY obstacles — even small ones:
   - Small hazards: shoes, cables, toys, mats, puddles, small drops, raised thresholds, uneven pavement.
   - Larger obstacles: chairs, trash cans, open doors, pillars, bikes, bushes, people.
2. TACTICAL DEVIATION & STEP INSTRUCTION:
   - If an obstacle is in the path: Give the user an EXACT step-based detour instruction. For example:
     - "Walk 3 steps forward, take a 1-step deviation to your right to bypass a low box, then continue straight."
     - "Careful: small raised threshold 2 steps ahead. Step high, then walk straight for 5 steps."
   - If path is clear: Tell them how many steps to walk straight ahead towards $destination.
3. CONSTRAINTS:
   - Maximum 2 sentences.
   - Crisp, actionable, and direct.
   - Use hedge words ("looks like", "seems to be", "I think"). Never say anything is "completely safe".
''';

      final model = _getModel();
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
      return "Continue carefully towards $destination for 3 steps. Watch your footing.";
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

  /// Clear conversation memory (e.g. on new topic).
  void resetMemory() => _history.clear();

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
