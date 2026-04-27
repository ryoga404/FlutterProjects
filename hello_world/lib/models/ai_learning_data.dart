import '../models/question.dart';
import '../models/answer_history.dart';

/// AI学習分析結果のデータモデル
class AiLearningAnalysis {
  final String setId;
  final int totalQuestions;
  final int totalAttempts;
  final double overallAccuracy;      // 全問題の正答率
  final List<WeakArea> weakAreas;    // 弱点分野リスト
  final List<QuestionAnalysis> questionAnalysis;
  final LearningTrend learningTrend; // 学習の進捗トレンド
  final List<String> recommendations; // 学習推奨事項

  AiLearningAnalysis({
    required this.setId,
    required this.totalQuestions,
    required this.totalAttempts,
    required this.overallAccuracy,
    required this.weakAreas,
    required this.questionAnalysis,
    required this.learningTrend,
    required this.recommendations,
  });
}

/// 弱点分野
class WeakArea {
  final String tag;                // タグ名
  final int questionCount;         // 該当問題数
  final int correctCount;          // 正答数
  final double accuracy;           // 正答率
  final int attempts;              // 試行回数
  final DateTime? lastAttemptDate; // 最後に解いた日時

  WeakArea({
    required this.tag,
    required this.questionCount,
    required this.correctCount,
    required this.accuracy,
    required this.attempts,
    this.lastAttemptDate,
  });

  /// 優先度スコア（学習推奨度）
  /// 正答率が低く、最近解いていないほど高い
  double get priorityScore {
    final accuracyWeight = (1 - accuracy) * 100; // 正答率が低いほど高い
    var recencyWeight = 0.0;
    if (lastAttemptDate != null) {
      final daysSinceLastAttempt =
          DateTime.now().difference(lastAttemptDate!).inDays;
      recencyWeight = (daysSinceLastAttempt / 7).clamp(0, 10).toDouble(); // 最大10
    } else {
      recencyWeight = 10.0; // 未解答なら最高優先度
    }
    return (accuracyWeight * 0.7) + (recencyWeight * 0.3);
  }
}

/// 個別問題の分析
class QuestionAnalysis {
  final String questionId;
  final String questionText;
  final List<String> tags;
  final int attempts;
  final int correctCount;
  final double accuracy;
  final DateTime? firstAttemptDate;
  final DateTime? lastAttemptDate;
  final int consecutiveCorrect; // 連続正答数
  final int daysUnderReview;    // 復習期間（日数）

  QuestionAnalysis({
    required this.questionId,
    required this.questionText,
    required this.tags,
    required this.attempts,
    required this.correctCount,
    required this.accuracy,
    this.firstAttemptDate,
    this.lastAttemptDate,
    this.consecutiveCorrect = 0,
    this.daysUnderReview = 0,
  });

  /// 問題の習得度レベル
  LevelStatus get level {
    if (accuracy == 0) return LevelStatus.notStarted;
    if (attempts < 2) return LevelStatus.learning;
    if (accuracy >= 0.8 && consecutiveCorrect >= 2) return LevelStatus.mastered;
    if (accuracy >= 0.6) return LevelStatus.practicing;
    return LevelStatus.struggling;
  }

  String get levelLabel {
    switch (level) {
      case LevelStatus.notStarted:
        return '未開始';
      case LevelStatus.learning:
        return '学習中';
      case LevelStatus.practicing:
        return '練習中';
      case LevelStatus.struggling:
        return '苦手';
      case LevelStatus.mastered:
        return '習得済み';
    }
  }
}

/// 問題の習得度レベル
enum LevelStatus {
  notStarted,  // 未解答
  learning,    // 学習開始（1-2回）
  practicing,  // 練習中（60-80%正答）
  struggling,  // 苦手（60%未満）
  mastered,    // 習得済み（80%以上）
}

/// 学習進捗トレンド
class LearningTrend {
  final List<DateTime> dates;           // 解答日付リスト
  final List<double> dailyAccuracy;     // 日別正答率
  final List<int> dailyAttempts;        // 日別試行回数
  final double weeklyTrend;             // 週間トレンド（+で改善、-で悪化）
  final int practiceStreak;             // 連続練習日数
  final int daysInactive;               // 練習していない日数

  LearningTrend({
    required this.dates,
    required this.dailyAccuracy,
    required this.dailyAttempts,
    required this.weeklyTrend,
    required this.practiceStreak,
    required this.daysInactive,
  });

  /// トレンドの説明
  String get trendLabel {
    if (weeklyTrend > 0.1) return '📈 好調です（改善中）';
    if (weeklyTrend > -0.05) return '➡️ 安定しています';
    return '📉 少し落ちています';
  }
}

/// 学習推奨
class LearningRecommendation {
  final RecommendationType type;
  final String title;
  final String description;
  final String actionLabel;
  final int priority; // 1-5（高いほど重要）

  LearningRecommendation({
    required this.type,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.priority,
  });
}

enum RecommendationType {
  reviewWeakAreas,      // 弱点復習
  moreExercise,         // 練習追加
  focusOnTags,          // タグ別練習
  takeBreak,            // 休憩推奨
  congratulations,      // 合格祝い
}
