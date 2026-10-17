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
        parts.add(DataPart('image/png', imageBytes));
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
