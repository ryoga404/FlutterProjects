import 'dart:convert';

/// 演習の中断状態を保存するモデル
class ExerciseProgress {
  final String setId;
  final String setName;
  final List<String> questionIds; // 出題順の問題 ID リスト
  final int currentIndex;
  final bool timeLimitEnabled;
  final int timeLimitSeconds;
  final bool shuffleChoices;
  final DateTime savedAt;

  ExerciseProgress({
    required this.setId,
    required this.setName,
    required this.questionIds,
    required this.currentIndex,
    required this.timeLimitEnabled,
    required this.timeLimitSeconds,
    required this.shuffleChoices,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'setId': setId,
    'setName': setName,
    'questionIds': questionIds,
    'currentIndex': currentIndex,
    'timeLimitEnabled': timeLimitEnabled,
    'timeLimitSeconds': timeLimitSeconds,
    'shuffleChoices': shuffleChoices,
    'savedAt': savedAt.toIso8601String(),
  };

  factory ExerciseProgress.fromJson(Map<String, dynamic> json) =>
      ExerciseProgress(
        setId: json['setId'] as String,
        setName: json['setName'] as String,
        questionIds: List<String>.from(json['questionIds'] as List),
        currentIndex: (json['currentIndex'] as num).toInt(),
        timeLimitEnabled: json['timeLimitEnabled'] as bool? ?? false,
        timeLimitSeconds: (json['timeLimitSeconds'] as num?)?.toInt() ?? 45,
        shuffleChoices: json['shuffleChoices'] as bool? ?? false,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
