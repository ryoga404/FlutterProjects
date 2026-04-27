import 'package:intl/intl.dart';
import '../models/question.dart';
import '../models/answer_history.dart';
import '../models/ai_learning_data.dart';

class AiLearningEngine {
  /// 全解答履歴を分析して学習成果をレポート生成
  static AiLearningAnalysis analyzeProgress(
    List<Question> questions,
    List<AnswerHistory> histories,
  ) {
    if (histories.isEmpty) {
      return _emptyAnalysis(questions.first.setId);
    }

    final totalAttempts = histories.length;
    final totalQuestions = questions.length;
    final correctCount = histories.where((h) => h.correct).length;
    final overallAccuracy = correctCount / totalAttempts;

    // 個別問題の分析
    final questionAnalysisMap = <String, QuestionAnalysis>{};
    for (final q in questions) {
      final qHistories = histories.where((h) => h.questionId == q.id).toList();
      if (qHistories.isNotEmpty) {
        final qCorrect = qHistories.where((h) => h.correct).length;
        final qAccuracy = qCorrect / qHistories.length;
        final consecutiveCorrect = _countConsecutiveCorrect(qHistories);

        final firstDate = qHistories.isNotEmpty
            ? qHistories.reduce((a, b) =>
                a.answeredAt.isBefore(b.answeredAt) ? a : b).answeredAt
            : null;
        final lastDate = qHistories.isNotEmpty
            ? qHistories.reduce((a, b) =>
                a.answeredAt.isAfter(b.answeredAt) ? a : b).answeredAt
            : null;
        final daysUnderReview = firstDate != null
            ? DateTime.now().difference(firstDate).inDays
            : 0;

        questionAnalysisMap[q.id] = QuestionAnalysis(
          questionId: q.id,
          questionText: q.question,
          tags: q.tags,
          attempts: qHistories.length,
          correctCount: qCorrect,
          accuracy: qAccuracy,
          firstAttemptDate: firstDate,
          lastAttemptDate: lastDate,
          consecutiveCorrect: consecutiveCorrect,
          daysUnderReview: daysUnderReview,
        );
      }
    }

    // タグ別の弱点分析
    final tagAnalysis = _analyzeTagWeakness(questions, questionAnalysisMap);

    // 学習トレンド
    final trend = _calculateTrend(histories);

    // 学習推奨事項
    final recommendations = _generateRecommendations(
      tagAnalysis,
      overallAccuracy,
      trend,
      questionAnalysisMap.values.toList(),
    );

    return AiLearningAnalysis(
      setId: questions.first.setId,
      totalQuestions: totalQuestions,
      totalAttempts: totalAttempts,
      overallAccuracy: overallAccuracy,
      weakAreas: tagAnalysis,
      questionAnalysis: questionAnalysisMap.values.toList(),
      learningTrend: trend,
      recommendations: recommendations,
    );
  }

  /// 空の分析（履歴がない場合）
  static AiLearningAnalysis _emptyAnalysis(String setId) {
    return AiLearningAnalysis(
      setId: setId,
      totalQuestions: 0,
      totalAttempts: 0,
      overallAccuracy: 0,
      weakAreas: [],
      questionAnalysis: [],
      learningTrend: LearningTrend(
        dates: [],
        dailyAccuracy: [],
        dailyAttempts: [],
        weeklyTrend: 0,
        practiceStreak: 0,
        daysInactive: 0,
      ),
      recommendations: ['まずは問題を解いてみましょう！'],
    );
  }

  /// タグ別の弱点分析
  static List<WeakArea> _analyzeTagWeakness(
    List<Question> questions,
    Map<String, QuestionAnalysis> analysisMap,
  ) {
    final tagMap = <String, List<QuestionAnalysis>>{};

    for (final q in questions) {
      final analysis = analysisMap[q.id];
      if (analysis != null) {
        // タグが空の場合は「未分類」として扱う
        final tags = q.tags.isEmpty ? ['未分類'] : q.tags;
        for (final tag in tags) {
          tagMap.putIfAbsent(tag, () => []).add(analysis);
        }
      }
    }

    final weakAreas = <WeakArea>[];
    for (final entry in tagMap.entries) {
      final tag = entry.key;
      final analyses = entry.value;
      final questionCount = analyses.length;
      final correctCount =
          analyses.fold<int>(0, (sum, a) => sum + a.correctCount);
      final totalAttempts = analyses.fold<int>(0, (sum, a) => sum + a.attempts);
      final accuracy =
          totalAttempts > 0 ? correctCount / totalAttempts : 0.0;

      final lastAttemptDate = analyses
          .where((a) => a.lastAttemptDate != null)
          .map((a) => a.lastAttemptDate!)
          .fold<DateTime?>(null,
              (prev, date) => prev == null || date.isAfter(prev) ? date : prev);

      weakAreas.add(WeakArea(
        tag: tag,
        questionCount: questionCount,
        correctCount: correctCount,
        accuracy: accuracy,
        attempts: totalAttempts,
        lastAttemptDate: lastAttemptDate,
      ));
    }

    // 優先度でソート（低正答率 > 最後に解いた日が古い）
    weakAreas.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return weakAreas;
  }

  /// 学習トレンドの計算
  static LearningTrend _calculateTrend(List<AnswerHistory> histories) {
    if (histories.isEmpty) {
      return LearningTrend(
        dates: [],
        dailyAccuracy: [],
        dailyAttempts: [],
        weeklyTrend: 0,
        practiceStreak: 0,
        daysInactive: 0,
      );
    }

    // 日付ごとにグループ化
    final dateGrouped = <String, List<AnswerHistory>>{};
    for (final h in histories) {
      final dateStr =
          DateFormat('yyyy-MM-dd').format(h.answeredAt);
      dateGrouped.putIfAbsent(dateStr, () => []).add(h);
    }

    final sortedDates = dateGrouped.keys.toList()..sort();
    final dates = sortedDates
        .map((s) => DateFormat('yyyy-MM-dd').parse(s))
        .toList();
    final dailyAccuracy = <double>[];
    final dailyAttempts = <int>[];

    for (final date in dates) {
      final datetimeStr = DateFormat('yyyy-MM-dd').format(date);
      final dayHistories = dateGrouped[datetimeStr] ?? [];
      final correct = dayHistories.where((h) => h.correct).length;
      dailyAccuracy.add(dayHistories.isEmpty
          ? 0
          : correct / dayHistories.length);
      dailyAttempts.add(dayHistories.length);
    }

    // 週間トレンド（過去7日）
    final weeklyTrend = _calculateWeeklyTrend(dailyAccuracy);

    // 練習ストリーク（連続練習日数）
    final practiceStreak = _calculatePracticeStreak(dates);

    // 休止日数
    final daysInactive = _calculateDaysInactive(
        dates.isEmpty ? DateTime.now() : dates.last);

    return LearningTrend(
      dates: dates,
      dailyAccuracy: dailyAccuracy,
      dailyAttempts: dailyAttempts,
      weeklyTrend: weeklyTrend,
      practiceStreak: practiceStreak,
      daysInactive: daysInactive,
    );
  }

  /// 週間トレンドの計算（-1.0 〜 1.0）
  static double _calculateWeeklyTrend(List<double> dailyAccuracy) {
    if (dailyAccuracy.length < 2) return 0;

    final recentLength = dailyAccuracy.length >= 14
        ? 7
        : (dailyAccuracy.length ~/ 2).clamp(1, 7);
    final earlier = dailyAccuracy.length > recentLength
        ? dailyAccuracy
            .sublist(dailyAccuracy.length - recentLength * 2,
                dailyAccuracy.length - recentLength)
            .reduce((a, b) => a + b) /
            recentLength
        : (dailyAccuracy.reduce((a, b) => a + b) / dailyAccuracy.length);
    final recent = dailyAccuracy
            .sublist(dailyAccuracy.length - recentLength)
            .reduce((a, b) => a + b) /
        recentLength;

    return (recent - earlier).clamp(-1.0, 1.0);
  }

  /// 連続練習日数
  static int _calculatePracticeStreak(List<DateTime> dates) {
    if (dates.isEmpty) return 0;
    int streak = 1;
    for (int i = dates.length - 1; i > 0; i--) {
      final diff = dates[i].difference(dates[i - 1]).inDays;
      if (diff == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// 最後の練習からの経過日数
  static int _calculateDaysInactive(DateTime lastPracticeDate) {
    return DateTime.now()
        .difference(lastPracticeDate)
        .inDays
        .clamp(0, 365);
  }

  /// 連続正答数（最後の解答に向かって何問連続で正答したか）
  static int _countConsecutiveCorrect(List<AnswerHistory> histories) {
    if (histories.isEmpty) return 0;
    // 時系列でソート
    final sorted = [...histories]
      ..sort((a, b) => a.answeredAt.compareTo(b.answeredAt));
    int count = 0;
    for (int i = sorted.length - 1; i >= 0; i--) {
      if (sorted[i].correct) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// 学習推奨の生成
  static List<String> _generateRecommendations(
    List<WeakArea> weakAreas,
    double overallAccuracy,
    LearningTrend trend,
    List<QuestionAnalysis> allQuestions,
  ) {
    final recommendations = <String>[];

    // 全体成績が低い場合
    if (overallAccuracy < 0.5) {
      recommendations.add('📚 基礎から復習しましょう。正答率50%未満です。');
    }

    // 弱点分野がある場合
    if (weakAreas.isNotEmpty) {
      final topWeakArea = weakAreas.first;
      recommendations.add(
          '🎯 「${topWeakArea.tag}」を集中復習しましょう（正答率: ${(topWeakArea.accuracy * 100).toStringAsFixed(0)}%）');
    }

    // トレンドが悪い場合
    if (trend.weeklyTrend < -0.1) {
      recommendations.add('💪 最近成績が下がっています。基礎を見直してみて。');
    }

    // 練習量が足りない場合
    if (trend.practiceStreak == 0 && trend.daysInactive > 3) {
      recommendations.add('⏰ ${trend.daysInactive}日間練習していません。少しずつ再開しましょう。');
    }

    // 習得済み問題がある場合
    final masteredCount = allQuestions
        .where((q) => q.level == LevelStatus.mastered)
        .length;
    if (masteredCount > 0 && masteredCount == allQuestions.length) {
      recommendations.add('🎉 すべての問題を習得しました！合格祝い！');
    } else if (masteredCount > 0) {
      recommendations.add(
          '✅ 習得済み: $masteredCount問。残り${allQuestions.length - masteredCount}問を頑張ろう！');
    }

    // 推奨がない場合
    if (recommendations.isEmpty) {
      recommendations.add('📖 継続は力なり。毎日少しずつ練習を続けましょう！');
    }

    return recommendations;
  }
}
