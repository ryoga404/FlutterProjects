class AnswerHistory {
  final String id;
  final String setId;
  final String questionId;
  final String questionText;
  final bool correct;
  final dynamic userAnswer;
  final DateTime answeredAt;

  AnswerHistory({
    required this.id,
    required this.setId,
    required this.questionId,
    required this.questionText,
    required this.correct,
    required this.userAnswer,
    required this.answeredAt,
  });

  factory AnswerHistory.fromJson(Map<String, dynamic> json) {
    return AnswerHistory(
      id: json['id'] ?? '',
      setId: json['setId'] ?? '',
      questionId: json['questionId'],
      questionText: json['questionText'],
      correct: json['correct'],
      userAnswer: json['userAnswer'],
      answeredAt: DateTime.parse(json['answeredAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'setId': setId,
      'questionId': questionId,
      'questionText': questionText,
      'correct': correct,
      'userAnswer': userAnswer,
      'answeredAt': answeredAt.toIso8601String(),
    };
  }
}
