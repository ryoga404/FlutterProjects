import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exercise_progress.dart';
import '../models/question.dart';
import '../models/question_set.dart';
import '../providers/app_settings_provider.dart';
import '../services/question_service.dart';
import 'exercise_screen.dart';
import 'mock_exam_screen.dart';

class ExerciseMenuScreen extends StatefulWidget {
  final QuestionSet set;
  /// true のとき、画面を開いた直後に「今日の復習」問題で演習を開始する
  final bool startTodaysReview;

  const ExerciseMenuScreen({
    super.key,
    required this.set,
    this.startTodaysReview = false,
  });

  @override
  State<ExerciseMenuScreen> createState() => _ExerciseMenuScreenState();
}

class _ExerciseMenuScreenState extends State<ExerciseMenuScreen> {
  final _service = QuestionService();

  List<Question> _questions = [];
  List<Question> _weakQuestions = [];
  List<String>   _allTags = [];
  bool _isLoading = true;

  double _weakThreshold = 0.6;

  // フィルター
  Set<QuestionType> _typeFilter = {};
  Set<String>       _tagFilter  = {};

  // 中断進捗
  ExerciseProgress? _savedProgress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final questions = await _service.loadQuestionsForSet(widget.set.id);
    final weak      = await _service.loadWeakQuestions(
        setId: widget.set.id, threshold: _weakThreshold);
    final tags     = await _service.loadTagsForSet(widget.set.id);
    final progress = await _service.loadExerciseProgress();

    setState(() {
      _questions     = questions;
      _weakQuestions = weak;
      _allTags       = tags;
      // 別セットの進捗は無視
      _savedProgress = (progress?.setId == widget.set.id) ? progress : null;
      _isLoading     = false;
    });

    // 今日の復習ショートカットで開かれた場合、即座に開始
    if (widget.startTodaysReview && mounted) {
      final reviewQs = questions.where((q) => q.isDueForReview).toList();
      if (reviewQs.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _start(reviewQs));
      }
    }
  }

  List<Question> get _filtered {
    var list = _questions;
    if (_typeFilter.isNotEmpty) {
      list = list.where((q) => _typeFilter.contains(q.type)).toList();
    }
    if (_tagFilter.isNotEmpty) {
      list = list.where((q) => q.tags.any(_tagFilter.contains)).toList();
    }
    return list;
  }

  List<Question> get _filteredWeak {
    var list = _weakQuestions;
    if (_typeFilter.isNotEmpty) {
      list = list.where((q) => _typeFilter.contains(q.type)).toList();
    }
    if (_tagFilter.isNotEmpty) {
      list = list.where((q) => q.tags.any(_tagFilter.contains)).toList();
    }
    return list;
  }

  Map<QuestionType, int> get _typeCounts {
    final counts = <QuestionType, int>{};
    for (final q in _questions) counts[q.type] = (counts[q.type] ?? 0) + 1;
    return counts;
  }

  Future<void> _start(List<Question> questions) async {
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('該当する問題がありません')));
      return;
    }
    if (!mounted) return;

    final settings = context.read<AppSettingsProvider>();

    // 演習開始前に進捗を保存（中断対応）
    await _service.saveExerciseProgress(ExerciseProgress(
      setId: widget.set.id,
      setName: widget.set.name,
      questionIds: questions.map((q) => q.id).toList(),
      currentIndex: 0,
      timeLimitEnabled: settings.timeLimitEnabled,
      timeLimitSeconds: settings.timeLimitSeconds,
      shuffleChoices: settings.shuffleChoices,
      savedAt: DateTime.now(),
    ));

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseScreen(
          questions: questions,
          setName: widget.set.name,
          timeLimitEnabled: settings.timeLimitEnabled,
          timeLimitSeconds: settings.timeLimitSeconds,
          shuffleChoices: settings.shuffleChoices,
        ),
      ),
    );

    // 演習完了後は進捗をクリア
    await _service.clearExerciseProgress();
    _load();
  }

  // ──────────────────────────────────────────────
  // 中断再開ダイアログ
  // ──────────────────────────────────────────────
  Future<void> _resumeProgress() async {
    final prog = _savedProgress!;
    final ids  = prog.questionIds;
    final allQ = await _service.loadQuestionsForSet(widget.set.id);
    final qMap = {for (final q in allQ) q.id: q};
    final orderedQs = ids.map((id) => qMap[id]).whereType<Question>().toList();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseScreen(
          questions: orderedQs,
          setName: prog.setName,
          timeLimitEnabled: prog.timeLimitEnabled,
          timeLimitSeconds: prog.timeLimitSeconds,
          shuffleChoices: prog.shuffleChoices,
          initialIndex: prog.currentIndex,
        ),
      ),
    ).then((_) async {
      await _service.clearExerciseProgress();
      _load();
    });
  }

  void _showWeakThresholdDialog() {
    double temp = _weakThreshold;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('苦手判定の閾値'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('正答率 ${(temp * 100).toInt()}% 未満を苦手とみなします',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Slider(
              value: temp, min: 0.1, max: 0.9, divisions: 8,
              label: '${(temp * 100).toInt()}%',
              onChanged: (v) => setD(() => temp = v),
              activeColor: Colors.red,
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
              Text('10%', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text('90%', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () {
                setState(() => _weakThreshold = temp);
                Navigator.pop(ctx);
                _load();
              },
              child: const Text('適用'),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.set.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final settings    = context.watch<AppSettingsProvider>();
    final filtered    = _filtered;
    final filteredWeak = _filteredWeak;
    final typeCounts  = _typeCounts;
    final total       = filtered.length;
    final maxCount    = total.clamp(1, 999);
    final presets     = [10, 20, 30].where((n) => n < total).toList();
    final todayReview = _questions.where((q) => q.isDueForReview).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        title: Text('演習 — ${widget.set.name}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── 中断再開バナー ──
            if (_savedProgress != null) _resumeBanner(),

            // ── 今日の復習バナー ──
            if (todayReview > 0) _todayReviewBanner(todayReview),

            // ── タイプ絞り込み ──
            _filterCard(typeCounts, filtered),
            const SizedBox(height: 12),

            // ── 演習オプション（永続化） ──
            _optionsCard(settings),
            const SizedBox(height: 12),

            // ── 苦手フォーカスモード ──
            if (filteredWeak.isNotEmpty) ...[
              _weakFocusCard(filteredWeak),
              const SizedBox(height: 10),
            ],

            // ── 通常演習 ──
            _menuItem(
              icon: Icons.format_list_numbered,
              title: 'すべて順番に',
              subtitle: '$total問',
              onTap: () => _start(List.from(filtered)),
            ),
            const SizedBox(height: 10),
            _menuItem(
              icon: Icons.shuffle,
              title: 'ランダム',
              subtitle: '$total問をシャッフル',
              onTap: () => _start(List.from(filtered)..shuffle()),
            ),
            const SizedBox(height: 10),

            // ── 問題数指定 ──
            _countInputSection(filtered, maxCount, presets),
            const SizedBox(height: 10),

            // ── 模擬試験 ──
            _menuItem(
              icon: Icons.assignment,
              title: '模擬試験',
              subtitle: '合否判定・制限時間あり',
              color: Colors.indigo.shade50,
              onTap: () => _showMockExamDialog(filtered),
            ),
          ],
        ),
      ),
    );
  }

  // ── 中断再開バナー ──
  Widget _resumeBanner() {
    final prog = _savedProgress!;
    final pct  = ((prog.currentIndex / prog.questionIds.length.clamp(1, 999)) * 100).toInt();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade400, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.restore, color: Colors.amber.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text('前回の演習を途中で中断しました',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
          ),
          TextButton(
            onPressed: () async {
              await _service.clearExerciseProgress();
              setState(() => _savedProgress = null);
            },
            child: const Text('破棄', style: TextStyle(color: Colors.grey)),
          ),
        ]),
        Text('${prog.currentIndex} / ${prog.questionIds.length}問完了（$pct%）',
            style: TextStyle(fontSize: 12, color: Colors.amber.shade700)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _resumeProgress,
            icon: const Icon(Icons.play_arrow),
            label: const Text('続きから再開'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700, foregroundColor: Colors.white),
          ),
        ),
      ]),
    );
  }

  // ── 今日の復習バナー ──
  Widget _todayReviewBanner(int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton.icon(
        onPressed: () {
          final reviewQs = _questions.where((q) => q.isDueForReview).toList();
          _start(reviewQs);
        },
        icon: const Icon(Icons.schedule),
        label: Text('今日の復習を始める（$count問）'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  // ── フィルターカード（タイプ + タグ）──
  Widget _filterCard(Map<QuestionType, int> typeCounts, List<Question> filtered) {
    final hasTagFilter = _allTags.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('絞り込み', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // タイプ
          Wrap(
            spacing: 8, runSpacing: 4,
            children: QuestionType.values.map((t) {
              final count = typeCounts[t] ?? 0;
              if (count == 0) return const SizedBox.shrink();
              final selected = _typeFilter.contains(t);
              return FilterChip(
                label: Text('${t.label} ($count)'),
                selected: selected,
                onSelected: (_) => setState(() {
                  selected ? _typeFilter.remove(t) : _typeFilter.add(t);
                }),
              );
            }).toList(),
          ),
          // タグ
          if (hasTagFilter) ...[
            const SizedBox(height: 8),
            const Text('タグ', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: _allTags.map((tag) {
                final selected = _tagFilter.contains(tag);
                return FilterChip(
                  label: Text(tag, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  selectedColor: Colors.indigo.shade100,
                  checkmarkColor: Colors.indigo,
                  onSelected: (_) => setState(() {
                    selected ? _tagFilter.remove(tag) : _tagFilter.add(tag);
                  }),
                );
              }).toList(),
            ),
          ],
          if (_typeFilter.isNotEmpty || _tagFilter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Text('絞り込み中: ${filtered.length}問',
                    style: const TextStyle(color: Colors.indigo, fontSize: 12)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() { _typeFilter.clear(); _tagFilter.clear(); }),
                  child: const Text('クリア', style: TextStyle(fontSize: 12)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  // ── 演習オプションカード（AppSettingsProvider 連携・永続化）──
  Widget _optionsCard(AppSettingsProvider settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: [
          // タイムリミット
          Row(children: [
            const Icon(Icons.timer_outlined, size: 20, color: Colors.orange),
            const SizedBox(width: 10),
            const Expanded(child: Text('タイムリミット')),
            if (settings.timeLimitEnabled) ...[
              SizedBox(
                width: 64,
                height: 36,
                child: TextField(
                  controller: TextEditingController(
                      text: settings.timeLimitSeconds.toString()),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: Colors.orange.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: Colors.orange.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: Colors.orange, width: 2)),
                    suffixText: '秒',
                    suffixStyle: const TextStyle(fontSize: 11),
                  ),
                  onChanged: (v) {
                    final secs = int.tryParse(v);
                    if (secs != null && secs > 0) {
                      settings.setTimeLimitSeconds(secs);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
            Switch(
              value: settings.timeLimitEnabled,
              activeColor: Colors.orange,
              onChanged: settings.setTimeLimitEnabled,
            ),
          ]),
          const Divider(height: 1),
          // 選択肢シャッフル
          Row(children: [
            const Icon(Icons.shuffle_outlined, size: 20, color: Colors.indigo),
            const SizedBox(width: 10),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('選択肢をランダム表示'),
                Text('毎回選択肢の順番を変えます',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            )),
            Switch(
              value: settings.shuffleChoices,
              activeColor: Colors.indigo,
              onChanged: settings.setShuffleChoices,
            ),
          ]),
        ]),
      ),
    );
  }

  // ── 苦手フォーカスカード ──
  Widget _weakFocusCard(List<Question> weakQs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
          ),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 8),
            Text('苦手問題フォーカス',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: Colors.red.shade800, fontSize: 15)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${weakQs.length}問',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('正答率${(_weakThreshold * 100).toInt()}%未満の問題',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(children: [
            Expanded(child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _start(List.from(weakQs)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.format_list_numbered, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 6),
                  Text('順番に', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                ]),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _start(List.from(weakQs)..shuffle()),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.shuffle, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text('ランダム', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ]),
              ),
            )),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _showWeakThresholdDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300)),
                child: Icon(Icons.tune, size: 18, color: Colors.red.shade700),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── 問題数指定セクション ──
  Widget _countInputSection(List<Question> filtered, int maxCount, List<int> presets) {
    return StatefulBuilder(
      builder: (ctx, setInner) {
        int sliderVal = maxCount;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('問題数を指定してランダム',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text('$sliderVal / $maxCount問',
                style: TextStyle(
                    color: Theme.of(ctx).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ]),
          Slider(
            value: sliderVal.toDouble(),
            min: 1, max: maxCount.toDouble(),
            divisions: maxCount > 1 ? maxCount - 1 : 1,
            label: '$sliderVal',
            onChanged: (v) => setInner(() => sliderVal = v.round()),
          ),
          Wrap(spacing: 8, children: [
            ...presets.map((n) => OutlinedButton(
              onPressed: () => setInner(() => sliderVal = n),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  side: BorderSide(
                    color: sliderVal == n
                        ? Theme.of(ctx).colorScheme.primary
                        : Colors.grey.shade300,
                    width: sliderVal == n ? 2 : 1,
                  )),
              child: Text('$n問'),
            )),
            OutlinedButton(
              onPressed: () => setInner(() => sliderVal = maxCount),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  side: BorderSide(
                    color: sliderVal == maxCount
                        ? Theme.of(ctx).colorScheme.primary
                        : Colors.grey.shade300,
                    width: sliderVal == maxCount ? 2 : 1,
                  )),
              child: const Text('全問'),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final count   = sliderVal.clamp(1, maxCount);
                final shuffled = List<Question>.from(filtered)..shuffle();
                _start(shuffled.take(count).toList());
              },
              icon: const Icon(Icons.shuffle),
              label: Text('ランダムで$sliderVal問開始'),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ]);
      },
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Material(
      color: color ??
          Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.3),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            )),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }

  // ── 模擬試験ダイアログ ──
  void _showMockExamDialog(List<Question> questions) {
    final countCtrl     = TextEditingController(text: questions.length.toString());
    final passRateCtrl  = TextEditingController(text: '70');
    final timeLimitCtrl = TextEditingController(text: '60');
    bool timeLimitEnabled = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.assignment, color: Colors.indigo),
            SizedBox(width: 8),
            Text('模擬試験設定'),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: countCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: '問題数',
                    suffixText: '問（最大: ${questions.length}）',
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passRateCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '合格基準（得点率%）',
                    suffixText: '%',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('制限時間'),
                Switch(
                    value: timeLimitEnabled,
                    onChanged: (v) => setD(() => timeLimitEnabled = v)),
              ]),
              if (timeLimitEnabled)
                TextField(
                  controller: timeLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '制限時間',
                      suffixText: '分',
                      border: OutlineInputBorder()),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル')),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('開始'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () {
                final count  = (int.tryParse(countCtrl.text) ?? questions.length)
                    .clamp(1, questions.length);
                final rate   = (int.tryParse(passRateCtrl.text) ?? 70).clamp(1, 100);
                final limit  = int.tryParse(timeLimitCtrl.text) ?? 60;
                final selected = (List<Question>.from(questions)..shuffle())
                    .take(count)
                    .toList();
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MockExamScreen(
                      questions: selected,
                      setName: widget.set.name,
                      passRatePercent: rate,
                      timeLimitEnabled: timeLimitEnabled,
                      timeLimitMinutes: limit,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
