import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/question_set.dart';
import '../../models/ai_learning_data.dart';
import '../../services/question_service.dart';
import '../../services/history_service.dart';
import '../../services/ai_learning_service.dart';

class ModelTrainingScreen extends StatefulWidget {
  final QuestionSet questionSet;

  const ModelTrainingScreen({super.key, required this.questionSet});

  @override
  State<ModelTrainingScreen> createState() => _ModelTrainingScreenState();
}

class _ModelTrainingScreenState extends State<ModelTrainingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late QuestionService _questionService;
  late HistoryService _historyService;

  AiLearningAnalysis? _analysis;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _questionService = context.read<QuestionService>();
    _historyService = context.read<HistoryService>();
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final questions =
          await _questionService.loadQuestionsForSet(widget.questionSet.id);
      final histories =
          await _historyService.loadHistoryForSet(widget.questionSet.id);

      final analysis =
          AiLearningEngine.analyzeProgress(questions, histories);

      setState(() {
        _analysis = analysis;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'データ読み込みエラー: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        title: const Row(children: [
          Icon(Icons.smart_toy, size: 24),
          SizedBox(width: 8),
          Text('AI学習分析'),
        ]),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.trending_up), text: '成績'),
            Tab(icon: Icon(Icons.warning_amber), text: '弱点'),
            Tab(icon: Icon(Icons.lightbulb), text: '推奨'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _analysis == null || _analysis!.totalAttempts == 0
                  ? _buildEmptyState()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildScoreTab(),
                        _buildWeakAreaTab(),
                        _buildRecommendationTab(),
                      ],
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadAnalysis,
        icon: const Icon(Icons.refresh),
        label: const Text('更新'),
        backgroundColor: Colors.indigo,
      ),
    );
  }

  // ── 成績タブ ──
  Widget _buildScoreTab() {
    final analysis = _analysis!;
    final overallPercent =
        (analysis.overallAccuracy * 100).toStringAsFixed(1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 総合成績カード
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade600, Colors.indigo.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    '総合成績',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$overallPercent%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildAccuracyLevel(analysis.overallAccuracy),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 統計情報
          Text(
            '統計情報',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            icon: Icons.quiz,
            label: '総問題数',
            value: '${analysis.totalQuestions}問',
            color: Colors.blue,
          ),
          const SizedBox(height: 8),
          _buildStatCard(
            icon: Icons.done_all,
            label: '総試行回数',
            value: '${analysis.totalAttempts}回',
            color: Colors.green,
          ),
          const SizedBox(height: 8),
          _buildStatCard(
            icon: Icons.check_circle,
            label: '正答数',
            value:
                '${(analysis.overallAccuracy * analysis.totalAttempts).toStringAsFixed(0)}問',
            color: Colors.teal,
          ),
          const SizedBox(height: 24),

          // トレンド情報
          Text(
            '学習トレンド',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('トレンド'),
                      Text(
                        analysis.learningTrend.trendLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: analysis.learningTrend.weeklyTrend > 0
                              ? Colors.green
                              : analysis.learningTrend.weeklyTrend < 0
                                  ? Colors.red
                                  : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('連続練習日数'),
                      Text(
                        '${analysis.learningTrend.practiceStreak}日',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('最後の練習'),
                      Text(
                        analysis.learningTrend.daysInactive == 0
                            ? '今日'
                            : '${analysis.learningTrend.daysInactive}日前',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 弱点タブ ──
  Widget _buildWeakAreaTab() {
    final analysis = _analysis!;
    final weakAreas = analysis.weakAreas;

    if (weakAreas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 80, color: Colors.green.shade300),
            const SizedBox(height: 16),
            const Text(
              'すべての分野が習得できています！',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: weakAreas.length,
      itemBuilder: (context, index) {
        final area = weakAreas[index];
        final accuracyPercent =
            (area.accuracy * 100).toStringAsFixed(0);
        final priorityColor = _getPriorityColor(area.priorityScore);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}. ${area.tag}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${area.questionCount}問 / 正答${area.correctCount}問',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: priorityColor.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        '$accuracyPercent%',
                        style: TextStyle(
                          color: priorityColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: area.accuracy,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation(priorityColor),
                  ),
                ),
                const SizedBox(height: 8),
                if (area.lastAttemptDate != null)
                  Text(
                    '最後に解いた: ${_formatDate(area.lastAttemptDate!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 推奨タブ ──
  Widget _buildRecommendationTab() {
    final analysis = _analysis!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ...analysis.recommendations.asMap().entries.map(
            (entry) {
              final index = entry.key;
              final text = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: _getRecommendationColor(index),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('演習に戻る'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 12,
              ),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ── エラー状態 ──
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            _error ?? 'エラーが発生しました',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadAnalysis,
            child: const Text('再試行'),
          ),
        ],
      ),
    );
  }

  // ── 空状態 ──
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.school_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          const Text(
            'まず問題を解いてください',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'AI分析は解答履歴がないと利用できません',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('演習に戻る'),
          ),
        ],
      ),
    );
  }

  // ── ヘルパー ──
  Widget _buildAccuracyLevel(double accuracy) {
    String level;
    Color color;

    if (accuracy >= 0.8) {
      level = '優秀';
      color = Colors.green;
    } else if (accuracy >= 0.6) {
      level = '良好';
      color = Colors.orange;
    } else if (accuracy >= 0.4) {
      level = '要練習';
      color = Colors.orange;
    } else {
      level = '基礎から復習';
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        level,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(double score) {
    if (score > 7) return Colors.red;
    if (score > 5) return Colors.orange;
    if (score > 3) return Colors.yellow;
    return Colors.green;
  }

  Color _getRecommendationColor(int index) {
    final colors = [
      Colors.blue.shade50,
      Colors.green.shade50,
      Colors.orange.shade50,
      Colors.purple.shade50,
      Colors.red.shade50,
    ];
    return colors[index % colors.length];
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff == 0) return '今日';
    if (diff == 1) return '昨日';
    if (diff < 7) return '$diff日前';
    if (diff < 30) return '${(diff / 7).floor()}週前';
    return '${(diff / 30).floor()}ヶ月前';
  }
}
