/// One turn in the conversation with the AI.
class ConversationTurn {
  final String question;
  final String answer;
  final DateTime timestamp;

  const ConversationTurn({
    required this.question,
    required this.answer,
    required this.timestamp,
  });
}
