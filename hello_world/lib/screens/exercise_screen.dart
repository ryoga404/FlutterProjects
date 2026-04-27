import 'dart:async';
import 'package:flutter/material.dart';
import '../models/answer_history.dart';
import '../models/question.dart';
import '../services/history_service.dart';
import '../services/question_service.dart';
import '../widgets/answer_widgets.dart';
import '../platform/image_widget.dart';
import 'register_screen.dart';

class ExerciseScreen extends StatefulWidget {
  final List<Question> questions;
  final String setName;
  final bool timeLimitEnabled;
  final int timeLimitSeconds;
  final bool shuffleChoices;
  final int initialIndex;

  const ExerciseScreen({
    super.key,
    required this.questions,
    required this.setName,
    this.timeLimitEnabled = false,
    this.timeLimitSeconds = 45,
    this.shuffleChoices = false,
    this.initialIndex = 0,
  });

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen>
    with TickerProviderStateMixin {
  final _questionService = QuestionService();
  final _historyService = HistoryService();

  late int _currentIndex;
  bool _answered = false;
  bool _showAnswer = false;

  // タイマー
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _timeUp = false;

  // シャッフル済み選択肢
  List<String> _shuffledChoices = [];

  // 選択状態（インデックスは _shuffledChoices 上）
  int? _selectedChoiceIndex;
  final Set<int> _selectedChoiceIndices = {};
  final _textAnswerCtrl = TextEditingController();

  // 正誤結果
  bool? _lastCorrect;

  // 回答済みユーザー選択テキスト（結果表示用）
  String? _userSingleAnswer;
  Set<String> _userMultiAnswers = {};

  // 正誤フラッシュオーバーレイ
  late AnimationController _resultFadeController;
  late Animation<double> _resultFadeAnimation;
  late Animation<double> _resultScaleAnimation;
  Timer? _overlayTimer;

  // メモ編集
  late TextEditingController _memoCtrl;
  bool _memoSaving = false;

  @override
  void initState() {
    super.initState();
    _resultFadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _resultFadeAnimation = CurvedAnimation(
      parent: _resultFadeController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _resultScaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _resultFadeController, curve: Curves.easeOutBack),
    );
    _currentIndex = widget.initialIndex.clamp(0, widget.questions.length - 1);
    _memoCtrl = TextEditingController(text: _current.memo ?? '');
    _initShuffledChoices();
    if (widget.timeLimitEnabled) _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _overlayTimer?.cancel();
    _resultFadeController.dispose();
    _textAnswerCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Question get _current => widget.questions[_currentIndex];
  bool get _isLast => _currentIndex >= widget.questions.length - 1;

  void _initShuffledChoices() {
    final choices = List<String>.from(_current.choices ?? []);
    if (widget.shuffleChoices && choices.isNotEmpty) choices.shuffle();
    _shuffledChoices = choices;
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() { _remainingSeconds = widget.timeLimitSeconds; _timeUp = false; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remainingSeconds <= 1) {
        t.cancel();
        setState(() { _remainingSeconds = 0; _timeUp = true; });
        _recordAnswer(false, forced: true);
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  double get _timerProgress =>
      widget.timeLimitSeconds > 0 ? _remainingSeconds / widget.timeLimitSeconds : 0;
  Color get _timerColor {
    if (_timerProgress > 0.5) return Colors.green;
    if (_timerProgress > 0.25) return Colors.orange;
    return Colors.red;
  }

  Future<void> _recordAnswer(bool correct, {bool forced = false}) async {
    _timer?.cancel();
    dynamic userAnswer;
    switch (_current.type) {
      case QuestionType.trueFalse:
        userAnswer = correct ? _current.answer : (_current.answer == 'true' ? 'false' : 'true');
        break;
      case QuestionType.singleChoice:
        userAnswer = _selectedChoiceIndex != null && _selectedChoiceIndex! < _shuffledChoices.length
            ? _shuffledChoices[_selectedChoiceIndex!] : '';
        _userSingleAnswer = userAnswer as String;
        break;
      case QuestionType.multipleChoice:
        final selected = _selectedChoiceIndices
            .where((i) => i < _shuffledChoices.length)
            .map((i) => _shuffledChoices[i])
            .toList();
        userAnswer = selected;
        _userMultiAnswers = selected.toSet();
        break;
      case QuestionType.shortAnswer:
        userAnswer = _textAnswerCtrl.text.trim();
        break;
    }

    await _historyService.addHistory(AnswerHistory(
      id: 'h_${DateTime.now().millisecondsSinceEpoch}',
      setId: _current.setId,
      questionId: _current.id,
      questionText: _current.question,
      correct: correct,
      userAnswer: userAnswer,
      answeredAt: DateTime.now(),
    ));

    // ★ 間隔反復スケジュールを更新（エビングハウス忘却曲線）
    await _questionService.updateReviewSchedule(
      questionId: _current.id,
      correct: correct,
    );

    _overlayTimer?.cancel();
    _resultFadeController.reset();
    _resultFadeController.forward();
    _overlayTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _resultFadeController.reverse();
    });

    setState(() { _answered = true; _lastCorrect = correct; });
  }

  void _submitAnswer() {
    bool correct;
    switch (_current.type) {
      case QuestionType.trueFalse:
        return;
      case QuestionType.singleChoice:
        if (_selectedChoiceIndex == null) { _snack('選択肢を選んでください'); return; }
        correct = _shuffledChoices[_selectedChoiceIndex!] == _current.answer.toString();
        break;
      case QuestionType.multipleChoice:
        if (_selectedChoiceIndices.isEmpty) { _snack('選択肢を選んでください'); return; }
        final selectedSet = _selectedChoiceIndices.map((i) => _shuffledChoices[i]).toSet();
        final correctSet  = Set<String>.from(List<String>.from(_current.answer));
        correct = selectedSet.length == correctSet.length &&
            selectedSet.every((s) => correctSet.contains(s));
        break;
      case QuestionType.shortAnswer:
        setState(() => _showAnswer = true);
        _timer?.cancel();
        return;
    }
    _recordAnswer(correct);
  }

  void _nextQuestion() {
    _overlayTimer?.cancel();
    _resultFadeController.reset();
    if (_isLast) {
      _showFinishDialog();
    } else {
      setState(() {
        _currentIndex++;
        _answered = false;
        _showAnswer = false;
        _lastCorrect = null;
        _selectedChoiceIndex = null;
        _selectedChoiceIndices.clear();
        _userSingleAnswer = null;
        _userMultiAnswers = {};
        _textAnswerCtrl.clear();
        _timeUp = false;
        _memoCtrl.text = _current.memo ?? '';
      });
      _initShuffledChoices();
      if (widget.timeLimitEnabled) _startTimer();
    }
  }

  void _showFinishDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('演習完了 🎉'),
        content: const Text('すべての問題が終わりました！'),
        actions: [
          ElevatedButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _saveMemo() async {
    setState(() => _memoSaving = true);
    final updated = _current.copyWith(
        memo: _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim());
    await _questionService.updateQuestion(updated);
    widget.questions[_currentIndex] = updated;
    setState(() => _memoSaving = false);
    if (mounted) _snack('メモを保存しました');
  }

  // ★ 「この問題を後で修正」ショートカット
  // 演習を中断せずに RegisterScreen へ遷移し、戻ってきたら演習を再開
  Future<void> _openRegisterForCurrentQuestion() async {
    _timer?.cancel();
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterScreen(
          setId: _current.setId,
          setName: widget.setName,
          editingQuestion: _current,
        ),
      ),
    );
    // 保存されたら問題リストを更新してタイマーを再スタート
    if (result == true) {
      final updated = await _questionService.loadQuestionsForSet(_current.setId);
      final idx = updated.indexWhere((q) => q.id == _current.id);
      if (idx != -1) widget.questions[_currentIndex] = updated[idx];
      setState(() {});
      _snack('問題を更新しました');
    }
    if (widget.timeLimitEnabled && !_answered) _startTimer();
  }

  // ─────────────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final total = widget.questions.length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        title: Text('${widget.setName}  ${_currentIndex + 1}/$total'),
        actions: [
          // ★ 「この問題を後で修正」ショートカットボタン
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'この問題を修正',
            onPressed: _openRegisterForCurrentQuestion,
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentIndex + (_answered ? 1 : 0)) / total,
            minHeight: 4,
          ),
          if (widget.timeLimitEnabled) _timerBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: _typeBadge(_current.type)),
                  const SizedBox(height: 12),
                  if (_timeUp) _timeUpBanner(),

                  // 問題カード＋正誤オーバーレイ
                  ClipRect(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _questionCard(),
                        if (_answered) _resultOverlay(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // メモ欄（常に表示）
                  _memoSection(),
                  const SizedBox(height: 12),

                  if (!_answered && !_showAnswer) _answerUI(),
                  if (_answered || _showAnswer) _resultSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // メモセクション
  // ─────────────────────────────────────────────────────
  Widget _memoSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.sticky_note_2_outlined, size: 15, color: Colors.amber.shade800),
          const SizedBox(width: 6),
          Text('メモ', style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900)),
          const Spacer(),
          if (_memoSaving)
            const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            GestureDetector(
              onTap: _saveMemo,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('保存', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _memoCtrl,
          maxLines: 3,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: '気づいたことや復習ポイントを書いておこう',
            hintStyle: TextStyle(fontSize: 12, color: Colors.amber.shade400),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber.shade300)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber.shade300)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.amber.shade600, width: 2)),
          ),
        ),
      ]),
    );
  }

  Widget _resultOverlay() {
    final correct = _lastCorrect == true;
    final color = correct ? Colors.green : Colors.red;
    final label = correct ? '正解！' : '不正解...';
    final icon = correct ? Icons.check_circle_rounded : Icons.cancel_rounded;
    return FadeTransition(
      opacity: _resultFadeAnimation,
      child: ScaleTransition(
        scale: _resultScaleAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.92),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 36),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold,
                color: Colors.white, letterSpacing: 1.2)),
          ]),
        ),
      ),
    );
  }

  Widget _timerBar() {
    return Column(children: [
      LinearProgressIndicator(
        value: _timerProgress,
        backgroundColor: Colors.grey.shade200,
        valueColor: AlwaysStoppedAnimation<Color>(_timerColor),
        minHeight: 6,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Icon(Icons.timer, size: 13, color: _timerColor),
          const SizedBox(width: 4),
          Text('$_remainingSeconds秒',
              style: TextStyle(fontSize: 12, color: _timerColor, fontWeight: FontWeight.bold)),
        ]),
      ),
    ]);
  }

  Widget _timeUpBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red)),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.timer_off, color: Colors.red, size: 18),
        SizedBox(width: 6),
        Text('時間切れ！',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _typeBadge(QuestionType type) {
    final colors = {
      QuestionType.trueFalse: Colors.purple,
      QuestionType.singleChoice: Colors.blue,
      QuestionType.multipleChoice: Colors.teal,
      QuestionType.shortAnswer: Colors.orange,
    };
    final color = colors[type]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Text(type.label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _questionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(children: [
        if (_current.imagePath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AppImageWidget(path: _current.imagePath!, height: 150, fit: BoxFit.contain),
          ),
          const SizedBox(height: 12),
        ],
        SelectableText(
          _current.question,
          style: const TextStyle(fontSize: 17, height: 1.5),
          textAlign: TextAlign.center,
        ),
        if (_current.type == QuestionType.multipleChoice) ...[
          const SizedBox(height: 8),
          Text('（正解は${(List<dynamic>.from(_current.answer)).length}つ）',
              style: TextStyle(
                  color: Colors.teal.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ],
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Icon(Icons.text_fields, size: 11, color: Colors.grey.shade400),
          const SizedBox(width: 3),
          Text('長押しでテキスト選択・コピー',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        ]),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────
  // 回答 UI
  // ─────────────────────────────────────────────────────
  Widget _answerUI() {
    switch (_current.type) {
      case QuestionType.trueFalse:      return _tfAnswerUI();
      case QuestionType.singleChoice:   return _singleChoiceUI();
      case QuestionType.multipleChoice: return _multipleChoiceUI();
      case QuestionType.shortAnswer:    return _shortAnswerUI();
    }
  }

  Widget _tfAnswerUI() {
    return Row(children: [
      Expanded(child: _tfButton('○', true)),
      const SizedBox(width: 16),
      Expanded(child: _tfButton('✕', false)),
    ]);
  }

  Widget _tfButton(String label, bool value) {
    final isO = label == '○';
    return GestureDetector(
      onTap: () => _recordAnswer(_current.answer == value.toString()),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: isO ? Colors.green.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isO ? Colors.green : Colors.red, width: 2),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 40,
                  color: isO ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _singleChoiceUI() {
    return Column(children: [
      ...List.generate(_shuffledChoices.length, (i) {
        final selected = _selectedChoiceIndex == i;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => setState(() => _selectedChoiceIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                    width: selected ? 2 : 1),
              ),
              child: Row(children: [
                Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    _shuffledChoices[i],
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _submitAnswer,
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: const Size(double.infinity, 48)),
        child: const Text('回答する', style: TextStyle(fontSize: 16)),
      ),
    ]);
  }

  Widget _multipleChoiceUI() {
    return Column(children: [
      ...List.generate(_shuffledChoices.length, (i) {
        final selected = _selectedChoiceIndices.contains(i);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => setState(() {
              if (selected) _selectedChoiceIndices.remove(i);
              else _selectedChoiceIndices.add(i);
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected ? Colors.teal.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected ? Colors.teal : Colors.grey.shade300,
                    width: selected ? 2 : 1),
              ),
              child: Row(children: [
                Icon(
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
                    color: selected ? Colors.teal : Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    _shuffledChoices[i],
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _submitAnswer,
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: const Size(double.infinity, 48)),
        child: const Text('回答する', style: TextStyle(fontSize: 16)),
      ),
    ]);
  }

  Widget _shortAnswerUI() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _textAnswerCtrl,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: '回答を入力してください',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _submitAnswer,
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14)),
        child: const Text('解答を確認する', style: TextStyle(fontSize: 16)),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────
  // 結果セクション
  // ─────────────────────────────────────────────────────
  Widget _resultSection() {
    final isShortAnswer = _current.type == QuestionType.shortAnswer;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _answerResultCard(),

      if (isShortAnswer && !_answered) ...[
        const SizedBox(height: 12),
        const Text('自己採点してください',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: () => _recordAnswer(false),
            icon: const Icon(Icons.close),
            label: const Text('不正解'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton.icon(
            onPressed: () => _recordAnswer(true),
            icon: const Icon(Icons.check),
            label: const Text('正解'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ]),
      ],

      if (_answered &&
          _current.explanation != null &&
          _current.explanation!.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.lightbulb_outline, color: Colors.blue, size: 16),
              SizedBox(width: 6),
              Text('解説',
                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            SelectableText(_current.explanation!,
                style: const TextStyle(fontSize: 14, height: 1.5)),
          ]),
        ),
      ],

      if (_answered) ...[
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _nextQuestion,
          icon: Icon(_isLast ? Icons.flag : Icons.arrow_forward),
          label: Text(_isLast ? '演習終了' : '次の問題へ',
              style: const TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ],
    ]);
  }

  // ─────────────────────────────────────────────────────
  // 正誤詳細カード
  // ─────────────────────────────────────────────────────
  Widget _answerResultCard() {
    final correct = _lastCorrect == true;
    final headerColor  = correct ? Colors.green : Colors.red;
    final headerBg     = correct ? Colors.green.shade50 : Colors.red.shade50;
    final headerBorder = correct ? Colors.green.shade300 : Colors.red.shade300;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: headerBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            Icon(correct ? Icons.check_circle : Icons.cancel,
                color: headerColor, size: 20),
            const SizedBox(width: 6),
            Text(correct ? '正解' : '不正解',
                style: TextStyle(
                    color: headerColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: _answerDetailContent(correct),
        ),
      ]),
    );
  }

  Widget _answerDetailContent(bool correct) {
    switch (_current.type) {
      case QuestionType.trueFalse:
        final correctText = _current.answer == 'true' ? '○（正しい）' : '✕（誤り）';
        return _choiceRow(text: correctText, isCorrectChoice: true,
            isUserChoice: true, overallCorrect: correct);

      case QuestionType.singleChoice:
        final correctText = _current.answer.toString();
        final userText    = _userSingleAnswer ?? '';
        final allChoices  = _current.choices ?? [];
        if (correct) {
          return _choiceRow(text: correctText, isCorrectChoice: true,
              isUserChoice: true, overallCorrect: true);
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: allChoices.map((c) {
              final isCorrect = c == correctText;
              final isUser    = c == userText;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _choiceRow(text: c, isCorrectChoice: isCorrect,
                    isUserChoice: isUser, overallCorrect: false),
              );
            }).toList(),
          );
        }

      case QuestionType.multipleChoice:
        final correctSet = Set<String>.from(List<String>.from(_current.answer));
        final allChoices = _current.choices ?? [];
        final selectedAndCorrect    = allChoices.where((c) =>  correctSet.contains(c) &&  _userMultiAnswers.contains(c)).toList();
        final selectedAndWrong      = allChoices.where((c) => !correctSet.contains(c) &&  _userMultiAnswers.contains(c)).toList();
        final notSelectedButCorrect = allChoices.where((c) =>  correctSet.contains(c) && !_userMultiAnswers.contains(c)).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...selectedAndCorrect.map((c) => Padding(padding: const EdgeInsets.only(bottom: 6),
                child: _choiceRow(text: c, isCorrectChoice: true, isUserChoice: true, overallCorrect: correct))),
            ...selectedAndWrong.map((c) => Padding(padding: const EdgeInsets.only(bottom: 6),
                child: _choiceRow(text: c, isCorrectChoice: false, isUserChoice: true, overallCorrect: false))),
            ...notSelectedButCorrect.map((c) => Padding(padding: const EdgeInsets.only(bottom: 6),
                child: _choiceRow(text: c, isCorrectChoice: true, isUserChoice: false, overallCorrect: false))),
          ],
        );

      case QuestionType.shortAnswer:
        return SelectableText(_current.answer.toString(),
            style: const TextStyle(fontSize: 15, height: 1.5));
    }
  }

  Widget _choiceRow({
    required String text,
    required bool isCorrectChoice,
    required bool isUserChoice,
    required bool overallCorrect,
  }) {
    IconData icon;
    Color iconColor;
    String? badge;
    Color badgeBg;
    Color badgeText;

    if (isCorrectChoice && isUserChoice) {
      icon = Icons.check_circle; iconColor = Colors.green;
      badge = 'あなたの選択'; badgeBg = Colors.green.shade100; badgeText = Colors.green.shade800;
    } else if (!isCorrectChoice && isUserChoice) {
      icon = Icons.cancel; iconColor = Colors.red;
      badge = 'あなたの選択'; badgeBg = Colors.red.shade100; badgeText = Colors.red.shade800;
    } else if (isCorrectChoice && !isUserChoice) {
      icon = Icons.check_circle_outline; iconColor = Colors.green;
      badge = '未選択'; badgeBg = Colors.grey.shade200; badgeText = Colors.grey.shade700;
    } else {
      icon = Icons.radio_button_unchecked; iconColor = Colors.grey;
      badge = null; badgeBg = Colors.transparent; badgeText = Colors.transparent;
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, color: iconColor, size: 18)),
      const SizedBox(width: 8),
      Expanded(
        child: SelectableText(text,
            style: TextStyle(
              fontSize: 14, height: 1.4,
              color: isCorrectChoice ? Colors.black87 : Colors.grey.shade700,
              fontWeight: isCorrectChoice ? FontWeight.w600 : FontWeight.normal,
            )),
      ),
      if (badge != null) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(10)),
          child: Text(badge,
              style: TextStyle(fontSize: 11, color: badgeText, fontWeight: FontWeight.bold)),
        ),
      ],
    ]);
  }
}
