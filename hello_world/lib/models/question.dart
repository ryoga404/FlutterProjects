// 問題タイプ
enum QuestionType {
  trueFalse,      // 丸バツ
  singleChoice,   // 多肢択一（1つ選択）
  multipleChoice, // 複数選択
  shortAnswer,    // 記述
}

extension QuestionTypeExt on QuestionType {
  String get label {
    switch (this) {
      case QuestionType.trueFalse: return '丸バツ';
      case QuestionType.singleChoice: return '多肢択一';
      case QuestionType.multipleChoice: return '複数選択';
      case QuestionType.shortAnswer: return '記述';
    }
  }

  String get jsonKey {
    switch (this) {
      case QuestionType.trueFalse: return 'true_false';
      case QuestionType.singleChoice: return 'single_choice';
      case QuestionType.multipleChoice: return 'multiple_choice';
      case QuestionType.shortAnswer: return 'short_answer';
    }
  }

  static QuestionType fromString(String s) {
    switch (s) {
      case 'true_false': return QuestionType.trueFalse;
      case 'single_choice': return QuestionType.singleChoice;
      case 'multiple_choice': return QuestionType.multipleChoice;
      case 'short_answer': return QuestionType.shortAnswer;
      default: return QuestionType.shortAnswer;
    }
  }
}

class Question {
  final String id;
  final String setId;
  final QuestionType type;
  final String question;
  final List<String>? choices;
  final dynamic answer;
  final String? explanation;
  final String? imagePath;
  final int points;

  final String? memo;
  final List<String> tags;

  /// ★ 間隔反復：次回復習推奨日時（null = まだ一度も解いていない）
  final DateTime? nextReviewAt;

  Question({
    required this.id,
    required this.setId,
    required this.type,
    required this.question,
    this.choices,
    required this.answer,
    this.explanation,
    this.imagePath,
    this.points = 1,
    this.memo,
    this.tags = const [],
    this.nextReviewAt,
  });

  Question copyWith({
    String? id,
    String? setId,
    QuestionType? type,
    String? question,
    List<String>? choices,
    dynamic answer,
    String? explanation,
    String? imagePath,
    int? points,
    String? memo,
    bool clearMemo = false,
    List<String>? tags,
    DateTime? nextReviewAt,
    bool clearNextReviewAt = false,
  }) {
    return Question(
      id: id ?? this.id,
      setId: setId ?? this.setId,
      type: type ?? this.type,
      question: question ?? this.question,
      choices: choices ?? this.choices,
      answer: answer ?? this.answer,
      explanation: explanation ?? this.explanation,
      imagePath: imagePath ?? this.imagePath,
      points: points ?? this.points,
      memo: clearMemo ? null : (memo ?? this.memo),
      tags: tags ?? this.tags,
      nextReviewAt: clearNextReviewAt ? null : (nextReviewAt ?? this.nextReviewAt),
    );
  }

  factory Question.fromJson(Map<String, dynamic> json) {
    final type = QuestionTypeExt.fromString(json['type'] ?? 'short_answer');
    dynamic answer = json['answer'];
    if (type == QuestionType.multipleChoice && answer is List) {
      answer = List<String>.from(answer);
    }
    return Question(
      id: json['id'],
      setId: json['setId'] ?? '',
      type: type,
      question: json['question'],
      choices: json['choices'] != null ? List<String>.from(json['choices']) : null,
      answer: answer,
      explanation: json['explanation'],
      imagePath: json['imagePath'],
      points: (json['points'] as num?)?.toInt() ?? 1,
      memo: json['memo'] as String?,
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
      nextReviewAt: json['nextReviewAt'] != null
          ? DateTime.tryParse(json['nextReviewAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'setId': setId,
      'type': type.jsonKey,
      'question': question,
      'choices': choices,
      'answer': answer,
      'explanation': explanation,
      'imagePath': imagePath,
      'points': points,
      'memo': memo,
      'tags': tags,
      'nextReviewAt': nextReviewAt?.toIso8601String(),
    };
  }

  /// 今日が復習推奨日かどうか
  bool get isDueForReview {
    if (nextReviewAt == null) return true; // 未解答は常に対象
    final today = DateTime.now();
    return !nextReviewAt!.isAfter(DateTime(today.year, today.month, today.day, 23, 59, 59));
  }

  bool judgeAnswer(dynamic userAnswer) {
    switch (type) {
      case QuestionType.trueFalse:
        return userAnswer.toString() == answer.toString();
      case QuestionType.singleChoice:
        return userAnswer.toString() == answer.toString();
      case QuestionType.multipleChoice:
        // ★ Set比較に修正（カンマ結合文字列比較は選択肢内カンマで誤判定するバグを修正）
        if (userAnswer is! List || answer is! List) return false;
        final ua = Set<String>.from(List<String>.from(userAnswer));
        final ca = Set<String>.from(List<String>.from(answer));
        return ua.length == ca.length && ua.every(ca.contains);
      case QuestionType.shortAnswer:
        return false;
    }
  }
}
