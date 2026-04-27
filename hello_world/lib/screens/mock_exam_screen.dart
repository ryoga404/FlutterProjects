import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/answer_history.dart';
import '../models/question.dart';
import '../services/history_service.dart';
import '../services/pdf_service.dart';
import '../services/question_service.dart';
import '../platform/image_widget.dart';

class MockExamScreen extends StatefulWidget {
  final List<Question> questions;
  final String setName;
  final int passRatePercent;
  final bool timeLimitEnabled;
  final int timeLimitMinutes;

  const MockExamScreen({
    super.key,
    required this.questions,
    required this.setName,
    required this.passRatePercent,
    this.timeLimitEnabled = false,
    this.timeLimitMinutes = 60,
  });

  @override
  State<MockExamScreen> createState() => _MockExamScreenState();
}

class _MockExamScreenState extends State<MockExamScreen> {
  final _questionService = QuestionService();
  final _historyService  = HistoryService();

  int  _currentIndex = 0;
  bool _examFinished = false;

  late List<bool?>               _answers;
  late List<bool>                _reviewFlags;
  late List<int?>                _selectedIndices;
  late List<Set<int>>            _multiIndices;
  late List<TextEditingController> _shortTextControllers;

  Timer? _timer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    final n = widget.questions.length;
    _answers              = List.filled(n, null);
    _reviewFlags          = List.filled(n, false);
    _selectedIndices      = List.filled(n, null);
    _multiIndices         = List.generate(n, (_) => {});
    _shortTextControllers = List.generate(n, (_) => TextEditingController());
    if (widget.timeLimitEnabled) {
      _remainingSeconds = widget.timeLimitMinutes * 60;
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final ctrl in _shortTextControllers) ctrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remainingSeconds <= 1) {
        t.cancel();
        setState(() => _remainingSeconds = 0);
        _finishExam(timeUp: true);
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  Question get _current  => widget.questions[_currentIndex];
  bool     get _isLast   => _currentIndex >= widget.questions.length - 1;
  int      get _answeredCount => _answers.where((a) => a != null).length;
  int      get _reviewCount   => _reviewFlags.where((f) => f).length;

  String get _timerLabel {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor {
    if (_remainingSeconds > 300) return Colors.green;
    if (_remainingSeconds > 60)  return Colors.orange;
    return Colors.red;
  }

  double get _timerProgress =>
      widget.timeLimitMinutes > 0
          ? _remainingSeconds / (widget.timeLimitMinutes * 60)
          : 1.0;

  // ──────────────────────────────────────────────
  // 判定ロジック
  // ──────────────────────────────────────────────
  bool _judgeChoice(int idx) {
    final q = widget.questions[idx];
    switch (q.type) {
      case QuestionType.trueFalse:
        if (_selectedIndices[idx] == null) return false;
        return (_selectedIndices[idx] == 0 ? 'true' : 'false') == q.answer.toString();
      case QuestionType.singleChoice:
        final si = _selectedIndices[idx];
        if (si == null) return false;
        final choices = q.choices ?? [];
        if (si >= choices.length) return false;
        return choices[si] == q.answer.toString();
      case QuestionType.multipleChoice:
        final sel = _multiIndices[idx];
        if (sel.isEmpty) return false;
        final choices    = q.choices ?? [];
        final selectedSet = sel.map((i) => choices[i]).toSet();
        final correctSet  = Set<String>.from(List<String>.from(q.answer));
        return selectedSet.length == correctSet.length &&
            selectedSet.every(correctSet.contains);
      case QuestionType.shortAnswer:
        return _answers[idx] ?? false;
    }
  }

  void _commitAnswer(int idx) {
    final q = widget.questions[idx];
    if (q.type == QuestionType.shortAnswer) return;
    setState(() => _answers[idx] = _judgeChoice(idx));
  }

  // ──────────────────────────────────────────────
  // ★ バグ修正：実際のユーザー回答を組み立てる
  //   旧実装は userAnswer: null で保存していたため
  //   成績画面の「あなたの回答」が常に空だった
  // ──────────────────────────────────────────────
  dynamic _buildUserAnswer(int idx) {
    final q = widget.questions[idx];
    switch (q.type) {
      case QuestionType.trueFalse:
        final si = _selectedIndices[idx];
        if (si == null) return null;
        return si == 0 ? 'true' : 'false';
      case QuestionType.singleChoice:
        final si = _selectedIndices[idx];
        if (si == null) return null;
        final choices = q.choices ?? [];
        if (si >= choices.length) return null;
        return choices[si];
      case QuestionType.multipleChoice:
        final sel = _multiIndices[idx];
        if (sel.isEmpty) return null;
        final choices = q.choices ?? [];
        return sel.map((i) => choices[i]).toList();
      case QuestionType.shortAnswer:
        final text = _shortTextControllers[idx].text.trim();
        return text.isEmpty ? null : text;
    }
  }

  void _goTo(int idx) => setState(() => _currentIndex = idx);
  void _goToNext() { if (!_isLast) setState(() => _currentIndex++); }
  void _goToPrev() { if (_currentIndex > 0) setState(() => _currentIndex--); }

  int get _totalPoints  => widget.questions.fold(0, (s, q) => s + q.points);
  int get _earnedPoints {
    int pts = 0;
    for (int i = 0; i < widget.questions.length; i++) {
      if (_answers[i] == true) pts += widget.questions[i].points;
    }
    return pts;
  }

  bool get _isPassed {
    if (_totalPoints == 0) return false;
    return (_earnedPoints / _totalPoints * 100) >= widget.passRatePercent;
  }

  // ──────────────────────────────────────────────
  // 試験終了処理
  // ──────────────────────────────────────────────
  Future<void> _finishExam({bool timeUp = false}) async {
    _timer?.cancel();
    final now = DateTime.now();
    for (int i = 0; i < widget.questions.length; i++) {
      final q       = widget.questions[i];
      final correct = _answers[i] ?? false;
      await _historyService.addHistory(AnswerHistory(
        id:           'h_${now.millisecondsSinceEpoch}_$i',
        setId:        q.setId,
        questionId:   q.id,
        questionText: q.question,
        correct:      correct,
        userAnswer:   _buildUserAnswer(i),   // ★ 修正箇所
        answeredAt:   now,
      ));
      await _questionService.updateQuestionResult(
          id: q.id, correct: correct, answeredAt: now);
      await _questionService.updateReviewSchedule(
          questionId: q.id, correct: correct);
    }
    setState(() => _examFinished = true);
    if (!mounted) return;
    _showResultDialog(timeUp: timeUp);
  }

  Future<void> _exportReport() async {
    try {
      final filePath = await PdfService().generateMockExamReport(
        setName:         widget.setName,
        questions:       widget.questions,
        answers:         _answers,
        passRatePercent: widget.passRatePercent,
        passed:          _isPassed,
      );
      if (!mounted) return;
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDFをダウンロードしました'),
                backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF保存: $filePath'),
                duration: const Duration(seconds: 3)));
      }
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF出力失敗: $e')));
    }
  }

  void _showResultDialog({bool timeUp = false}) {
    final passed = _isPassed;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(passed ? Icons.emoji_events : Icons.cancel,
              color: passed ? Colors.amber : Colors.red, size: 32),
          const SizedBox(width: 8),
          Text(passed ? '合格' : '不合格',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: passed ? Colors.green : Colors.red)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (timeUp)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200)),
              child: const Row(children: [
                Icon(Icons.timer_off, color: Colors.red, size: 16),
                SizedBox(width: 6),
                Text('時間切れで終了しました',
                    style: TextStyle(color: Colors.red)),
              ]),
            ),
          _resultRow('合格基準', '${widget.passRatePercent}%以上'),
          _resultRow('回答済み', '$_answeredCount / ${widget.questions.length}問'),
          const Divider(height: 20),
          Text(
            passed ? '合格ライン達成！' : '合格ラインに届きませんでした',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: passed ? Colors.green : Colors.red),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('閉じる')),
          ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('レポート出力'),
              onPressed: () {
                Navigator.pop(context);
                _exportReport();
              }),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.grey)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ]),
  );

  void _showReviewList() {
    final reviewIndices = List.generate(widget.questions.length, (i) => i)
        .where((i) => _reviewFlags[i]).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.bookmark, color: Colors.orange),
          const SizedBox(width: 8),
          Text('見直し (${reviewIndices.length}問)'),
        ]),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: reviewIndices.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('見直し登録された問題はありません',
                      style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: reviewIndices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final idx      = reviewIndices[i];
                    final q        = widget.questions[idx];
                    final answered = _answers[idx] != null;
                    final text     = q.question.length > 20
                        ? '${q.question.substring(0, 20)}...'
                        : q.question;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              answered ? Colors.indigo : Colors.grey.shade300,
                          child: Text('${idx + 1}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: answered
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                  fontWeight: FontWeight.bold))),
                      title: Text(text, style: const TextStyle(fontSize: 13)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: answered
                                ? Colors.indigo.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(answered ? '回答済み' : '未回答',
                            style: TextStyle(
                                fontSize: 10,
                                color: answered
                                    ? Colors.indigo
                                    : Colors.grey)),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _goTo(idx);
                      },
                    );
                  }),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる')),
        ],
      ),
    );
  }

  void _showFinishPreview() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('試験終了前の確認'),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _previewBadge(
                        '回答済み', '$_answeredCount', Colors.indigo),
                    _previewBadge(
                        '未回答',
                        '${widget.questions.length - _answeredCount}',
                        Colors.grey),
                    _previewBadge('見直し', '$_reviewCount', Colors.orange),
                  ]),
            ),
            SizedBox(
              height: 300,
              child: ListView.separated(
                itemCount: widget.questions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final q        = widget.questions[i];
                  final answered = _answers[i] != null;
                  final review   = _reviewFlags[i];
                  final text     = q.question.length > 20
                      ? '${q.question.substring(0, 20)}...'
                      : q.question;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                        radius: 13,
                        backgroundColor:
                            answered ? Colors.indigo : Colors.grey.shade300,
                        child: Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 10,
                                color: answered
                                    ? Colors.white
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.bold))),
                    title: Text(text, style: const TextStyle(fontSize: 13)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (review)
                        const Icon(Icons.bookmark,
                            color: Colors.orange, size: 16),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: answered
                                ? Colors.indigo.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(answered ? '回答済み' : '未回答',
                            style: TextStyle(
                                fontSize: 10,
                                color: answered
                                    ? Colors.indigo
                                    : Colors.grey)),
                      ),
                    ]),
                    onTap: () {
                      Navigator.pop(context);
                      _goTo(i);
                    },
                  );
                },
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('問題に戻る')),
          ElevatedButton.icon(
            icon: const Icon(Icons.stop_circle),
            label: const Text('試験終了'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _confirmFinish();
            },
          ),
        ],
      ),
    );
  }

  Widget _previewBadge(String label, String count, Color color) {
    return Column(children: [
      Text(count,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  void _confirmFinish() {
    final unanswered = _answers.where((a) => a == null).length;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('試験を終了しますか？'),
        content: unanswered > 0
            ? Text('$unanswered問が未回答です。終了しますか？',
                style: const TextStyle(color: Colors.orange))
            : const Text('すべての問題に回答しました。終了しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('戻る')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _finishExam();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('終了する'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // build
  // ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final total = widget.questions.length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: Text('模擬試験 — ${widget.setName}'),
        actions: [
          if (widget.timeLimitEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: _timerColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _timerColor)),
                child: Row(children: [
                  Icon(Icons.timer, size: 15, color: _timerColor),
                  const SizedBox(width: 4),
                  Text(_timerLabel,
                      style: TextStyle(
                          color: _timerColor, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          IconButton(
              icon: const Icon(Icons.format_list_bulleted),
              tooltip: '問題一覧',
              onPressed: _showFinishPreview),
        ],
      ),
      body: Column(children: [
        if (widget.timeLimitEnabled)
          LinearProgressIndicator(
              value: _timerProgress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(_timerColor),
              minHeight: 5),
        Container(
          color: Colors.indigo.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Text('$_answeredCount/$total 回答',
                style: const TextStyle(fontSize: 12, color: Colors.indigo)),
            const SizedBox(width: 8),
            if (_reviewCount > 0)
              GestureDetector(
                onTap: _showReviewList,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.bookmark, size: 13, color: Colors.orange),
                    const SizedBox(width: 3),
                    Text('$_reviewCount',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            const Spacer(),
            Wrap(
              spacing: 4,
              children: List.generate(total, (i) {
                Color color;
                if (i == _currentIndex)       color = Colors.indigo;
                else if (_reviewFlags[i])      color = Colors.orange;
                else if (_answers[i] != null)  color = Colors.indigo.shade200;
                else                           color = Colors.grey.shade300;
                return GestureDetector(
                  onTap: () => _goTo(i),
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: i == _currentIndex
                            ? Border.all(
                                color: Colors.indigo.shade800, width: 2)
                            : null),
                  ),
                );
              }),
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('No.${_current.id}',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.shade200)),
                  child: Text('${_current.points}点',
                      style: const TextStyle(
                          color: Colors.indigo,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() =>
                      _reviewFlags[_currentIndex] =
                          !_reviewFlags[_currentIndex]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _reviewFlags[_currentIndex]
                          ? Colors.yellow.shade300
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _reviewFlags[_currentIndex]
                              ? Colors.orange
                              : Colors.grey.shade300),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.bookmark,
                          size: 16,
                          color: _reviewFlags[_currentIndex]
                              ? Colors.orange.shade800
                              : Colors.grey),
                      const SizedBox(width: 4),
                      Text('あとで見直し',
                          style: TextStyle(
                              fontSize: 12,
                              color: _reviewFlags[_currentIndex]
                                  ? Colors.orange.shade800
                                  : Colors.grey,
                              fontWeight: _reviewFlags[_currentIndex]
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _questionCard(),
              const SizedBox(height: 16),
              _answerUI(),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _currentIndex > 0 ? _goToPrev : null,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('前の問題'))),
                const SizedBox(width: 12),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: !_isLast ? _goToNext : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('次の問題'),
                        iconAlignment: IconAlignment.end)),
              ]),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _examFinished ? null : _showFinishPreview,
                icon: const Icon(Icons.stop_circle),
                label: const Text('試験終了',
                    style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _questionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.indigo.shade100)),
      child: Column(children: [
        if (_current.imagePath != null) ...[
          ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AppImageWidget(
                  path: _current.imagePath!,
                  height: 150,
                  fit: BoxFit.contain)),
          const SizedBox(height: 12),
        ],
        Text(_current.question,
            style: const TextStyle(fontSize: 17, height: 1.5),
            textAlign: TextAlign.center),
        if (_current.type == QuestionType.multipleChoice) ...[
          const SizedBox(height: 8),
          Text(
            '（正解は${(List<dynamic>.from(_current.answer)).length}つ）',
            style: TextStyle(
                color: Colors.teal.shade700,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
        ],
      ]),
    );
  }

  Widget _answerUI() {
    switch (_current.type) {
      case QuestionType.trueFalse:      return _tfUI();
      case QuestionType.singleChoice:   return _singleUI();
      case QuestionType.multipleChoice: return _multiUI();
      case QuestionType.shortAnswer:    return _shortUI();
    }
  }

  Widget _tfUI() {
    final sel = _selectedIndices[_currentIndex];
    return Row(children: [
      Expanded(child: _tfBtn('○', 0, sel)),
      const SizedBox(width: 16),
      Expanded(child: _tfBtn('✕', 1, sel)),
    ]);
  }

  Widget _tfBtn(String label, int val, int? sel) {
    final isO     = val == 0;
    final selected = sel == val;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndices[_currentIndex] = val);
        _commitAnswer(_currentIndex);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: selected
              ? (isO ? Colors.green.shade100 : Colors.red.shade100)
              : (isO ? Colors.green.shade50  : Colors.red.shade50),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isO ? Colors.green : Colors.red,
              width: selected ? 3 : 1.5),
        ),
        child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 40,
                    color: isO ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold))),
      ),
    );
  }

  Widget _singleUI() {
    final choices = _current.choices ?? [];
    final sel     = _selectedIndices[_currentIndex];
    return Column(children: List.generate(choices.length, (i) {
      final selected = sel == i;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedIndices[_currentIndex] = i);
            _commitAnswer(_currentIndex);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? Colors.indigo.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? Colors.indigo : Colors.grey.shade300,
                  width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? Colors.indigo : Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(choices[i],
                      style: const TextStyle(fontSize: 15))),
            ]),
          ),
        ),
      );
    }));
  }

  Widget _multiUI() {
    final choices = _current.choices ?? [];
    final sel     = _multiIndices[_currentIndex];
    return Column(children: List.generate(choices.length, (i) {
      final selected = sel.contains(i);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () {
            setState(() {
              if (selected) sel.remove(i);
              else sel.add(i);
            });
            _commitAnswer(_currentIndex);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? Colors.teal.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? Colors.teal : Colors.grey.shade300,
                  width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Icon(
                  selected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color: selected ? Colors.teal : Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(choices[i],
                      style: const TextStyle(fontSize: 15))),
            ]),
          ),
        ),
      );
    }));
  }

  Widget _shortUI() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _shortTextControllers[_currentIndex],
        maxLines: 4,
        decoration: const InputDecoration(
            hintText: '回答を入力してください（自己採点）',
            border: OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      const Text('記述問題は自己採点してください',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: OutlinedButton.icon(
          onPressed: () =>
              setState(() => _answers[_currentIndex] = false),
          icon: const Icon(Icons.close, color: Colors.red),
          label: const Text('不正解',
              style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: _answers[_currentIndex] == false
                      ? Colors.red
                      : Colors.grey.shade300,
                  width: _answers[_currentIndex] == false ? 2 : 1),
              padding:
                  const EdgeInsets.symmetric(vertical: 14)),
        )),
        const SizedBox(width: 12),
        Expanded(
            child: OutlinedButton.icon(
          onPressed: () =>
              setState(() => _answers[_currentIndex] = true),
          icon: const Icon(Icons.check, color: Colors.green),
          label: const Text('正解',
              style: TextStyle(color: Colors.green)),
          style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: _answers[_currentIndex] == true
                      ? Colors.green
                      : Colors.grey.shade300,
                  width: _answers[_currentIndex] == true ? 2 : 1),
              padding:
                  const EdgeInsets.symmetric(vertical: 14)),
        )),
      ]),
    ]);
  }
}
