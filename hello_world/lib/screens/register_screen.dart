import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/question.dart';
import '../services/question_service.dart';
import '../platform/image_widget.dart';

class RegisterScreen extends StatefulWidget {
  final String setId;
  final String setName;
  final Question? editingQuestion;

  const RegisterScreen({
    super.key,
    required this.setId,
    required this.setName,
    this.editingQuestion,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _service = QuestionService();
  final _picker = ImagePicker();

  QuestionType _selectedType = QuestionType.singleChoice;
  final _questionCtrl = TextEditingController();
  final _explanationCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  String? _selectedImagePath;
  bool _isLoading = false;
  List<String> _tags = [];

  // バリデーションエラー
  String? _questionError;
  String? _choicesError;
  String? _shortAnswerError;

  final List<TextEditingController> _choiceCtrl =
      List.generate(4, (_) => TextEditingController());
  int _singleAnswerIndex = 0;
  final Set<int> _multiAnswerIndices = {};
  final _shortAnswerCtrl = TextEditingController();
  String _tfAnswer = 'true';

  bool get _isEditMode => widget.editingQuestion != null;

  @override
  void initState() {
    super.initState();
    final eq = widget.editingQuestion;
    if (eq != null) {
      _selectedType = eq.type;
      _questionCtrl.text = eq.question;
      _explanationCtrl.text = eq.explanation ?? '';
      _pointsCtrl.text = eq.points.toString();
      _selectedImagePath = eq.imagePath;
      _memoCtrl.text = eq.memo ?? '';
      _tags = List.from(eq.tags);

      switch (eq.type) {
        case QuestionType.trueFalse:
          _tfAnswer = eq.answer.toString();
          break;
        case QuestionType.singleChoice:
          final choices = eq.choices ?? [];
          for (int i = 0; i < choices.length; i++) {
            if (i < _choiceCtrl.length) _choiceCtrl[i].text = choices[i];
            else _choiceCtrl.add(TextEditingController(text: choices[i]));
          }
          final ansIdx = choices.indexOf(eq.answer.toString());
          _singleAnswerIndex = ansIdx >= 0 ? ansIdx : 0;
          break;
        case QuestionType.multipleChoice:
          final choices = eq.choices ?? [];
          final correctList = List<String>.from(eq.answer);
          for (int i = 0; i < choices.length; i++) {
            if (i < _choiceCtrl.length) _choiceCtrl[i].text = choices[i];
            else _choiceCtrl.add(TextEditingController(text: choices[i]));
            if (correctList.contains(choices[i])) _multiAnswerIndices.add(i);
          }
          break;
        case QuestionType.shortAnswer:
          _shortAnswerCtrl.text = eq.answer.toString();
          break;
      }
    }
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _explanationCtrl.dispose();
    _pointsCtrl.dispose();
    _memoCtrl.dispose();
    _tagCtrl.dispose();
    _shortAnswerCtrl.dispose();
    for (final c in _choiceCtrl) c.dispose();
    super.dispose();
  }

  void _resetForm() {
    _questionCtrl.clear();
    _explanationCtrl.clear();
    _pointsCtrl.clear();
    _memoCtrl.clear();
    _tagCtrl.clear();
    _shortAnswerCtrl.clear();
    for (final c in _choiceCtrl) c.clear();
    setState(() {
      _selectedImagePath = null;
      _singleAnswerIndex = 0;
      _multiAnswerIndices.clear();
      _tfAnswer = 'true';
      _tags = [];
      _questionError = null;
      _choicesError = null;
      _shortAnswerError = null;
    });
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _selectedImagePath = picked.path);
  }

  // ★ クリップボードから問題文を貼り付けてパース
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('クリップボードにテキストがありません')));
      }
      return;
    }
    _showClipboardParseDialog(text.trim());
  }

  // ★ クリップボードテキストのパースダイアログ
  void _showClipboardParseDialog(String rawText) {
    final previewCtrl = TextEditingController(text: rawText);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.content_paste, color: Colors.indigo),
          SizedBox(width: 8),
          Text('クリップボードから入力'),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '貼り付けたテキストを確認・編集してから「問題文に適用」してください。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: previewCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                  hintText: '問題文として使用するテキスト',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.lightbulb_outline, size: 14, color: Colors.blue),
                      SizedBox(width: 6),
                      Text('自動パースのヒント',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                    ]),
                    SizedBox(height: 4),
                    Text(
                      '1行目 → 問題文\n'
                      '2行目以降の「A.」「①」「・」で始まる行 → 選択肢\n'
                      '「正解:」「答え:」「Answer:」で始まる行 → 正解',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('自動パース'),
            onPressed: () {
              Navigator.pop(ctx);
              _autoParse(previewCtrl.text.trim());
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.edit_note, size: 16),
            label: const Text('問題文に適用'),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _questionCtrl.text = previewCtrl.text.trim());
            },
          ),
        ],
      ),
    );
  }

  // ★ テキストから問題文・選択肢・正解を自動パース
  void _autoParse(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return;

    String questionText = '';
    final choices = <String>[];
    String answerRaw = '';

    // 正解行のパターン
    final answerPrefixes = ['正解:', '答え:', '正答:', 'Answer:', 'answer:',
                            '正解：', '答え：', '正答：'];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 正解行チェック
      bool isAnswer = false;
      for (final prefix in answerPrefixes) {
        if (line.startsWith(prefix)) {
          answerRaw = line.substring(prefix.length).trim();
          isAnswer = true;
          break;
        }
      }
      if (isAnswer) continue;

      // 選択肢行チェック（A. B. ① ② ・ - * で始まる）
      final choiceMatch = RegExp(r'^([A-Za-zａ-ｚＡ-Ｚ①②③④⑤⑥⑦⑧・\-\*][\.\．。]?\s*)(.+)$').firstMatch(line);
      if (i > 0 && choiceMatch != null && choiceMatch.group(1)!.length <= 4) {
        choices.add(choiceMatch.group(2)!.trim());
        continue;
      }

      // それ以外 → 問題文として連結
      if (questionText.isEmpty) {
        questionText = line;
      } else if (choices.isEmpty) {
        // 選択肢が始まる前は問題文に追加
        questionText += '\n$line';
      }
    }

    if (questionText.isEmpty) questionText = lines[0];

    setState(() {
      _questionCtrl.text = questionText;

      if (choices.isNotEmpty) {
        // 選択肢あり → singleChoice or multipleChoice に切り替え
        if (_selectedType == QuestionType.trueFalse ||
            _selectedType == QuestionType.shortAnswer) {
          _selectedType = QuestionType.singleChoice;
        }

        // 選択肢フィールドを埋める
        for (int i = 0; i < choices.length; i++) {
          if (i < _choiceCtrl.length) {
            _choiceCtrl[i].text = choices[i];
          } else {
            _choiceCtrl.add(TextEditingController(text: choices[i]));
          }
        }
        // 余分なフィールドをクリア
        for (int i = choices.length; i < _choiceCtrl.length; i++) {
          _choiceCtrl[i].clear();
        }

        // 正解が指定されていれば設定
        if (answerRaw.isNotEmpty) {
          final ansIdx = choices.indexWhere(
              (c) => c == answerRaw || c.startsWith(answerRaw));
          if (ansIdx >= 0) _singleAnswerIndex = ansIdx;
        }
      } else if (answerRaw.isNotEmpty) {
        // 選択肢なし・正解あり → shortAnswer
        _selectedType = QuestionType.shortAnswer;
        _shortAnswerCtrl.text = answerRaw;
      }

      _questionError = null;
      _choicesError = null;
      _shortAnswerError = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(choices.isNotEmpty
            ? '問題文と${choices.length}つの選択肢を取り込みました'
            : '問題文を取り込みました'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  bool _validate() {
    bool ok = true;
    setState(() {
      _questionError = null;
      _choicesError = null;
      _shortAnswerError = null;
    });

    if (_questionCtrl.text.trim().isEmpty) {
      setState(() => _questionError = '問題文を入力してください');
      ok = false;
    }

    switch (_selectedType) {
      case QuestionType.singleChoice:
        final filled = _choiceCtrl.where((c) => c.text.trim().isNotEmpty).length;
        if (filled < 2) {
          setState(() => _choicesError = '選択肢を2つ以上入力してください');
          ok = false;
        }
        break;
      case QuestionType.multipleChoice:
        final filled = _choiceCtrl.where((c) => c.text.trim().isNotEmpty).length;
        if (filled < 2) {
          setState(() => _choicesError = '選択肢を2つ以上入力してください');
          ok = false;
        } else if (_multiAnswerIndices.isEmpty) {
          setState(() => _choicesError = '正解を1つ以上選択してください');
          ok = false;
        }
        break;
      case QuestionType.shortAnswer:
        if (_shortAnswerCtrl.text.trim().isEmpty) {
          setState(() => _shortAnswerError = '模範解答を入力してください');
          ok = false;
        }
        break;
      case QuestionType.trueFalse:
        break;
    }
    return ok;
  }

  dynamic _buildAnswer() {
    switch (_selectedType) {
      case QuestionType.trueFalse: return _tfAnswer;
      case QuestionType.singleChoice: return _choiceCtrl[_singleAnswerIndex].text.trim();
      case QuestionType.multipleChoice:
        return _multiAnswerIndices.where((i) => i < _choiceCtrl.length)
            .map((i) => _choiceCtrl[i].text.trim()).where((s) => s.isNotEmpty).toList();
      case QuestionType.shortAnswer: return _shortAnswerCtrl.text.trim();
    }
  }

  List<String>? _buildChoices() {
    if (_selectedType == QuestionType.singleChoice || _selectedType == QuestionType.multipleChoice) {
      return _choiceCtrl.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    }
    return null;
  }

  Future<void> _register() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);
    final points = int.tryParse(_pointsCtrl.text.trim()) ?? 1;
    final memo = _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim();

    if (_isEditMode) {
      final updated = Question(
        id: widget.editingQuestion!.id, setId: widget.setId,
        type: _selectedType, question: _questionCtrl.text.trim(),
        choices: _buildChoices(), answer: _buildAnswer(),
        explanation: _explanationCtrl.text.trim().isEmpty ? null : _explanationCtrl.text.trim(),
        imagePath: _selectedImagePath, points: points, memo: memo, tags: List.from(_tags),
      );
      await _service.updateQuestion(updated);
      setState(() => _isLoading = false);
      if (!mounted) return;
      Navigator.pop(context, true);
    } else {
      final questions = await _service.loadQuestions();
      final newQ = Question(
        id: _service.generateId(questions), setId: widget.setId,
        type: _selectedType, question: _questionCtrl.text.trim(),
        choices: _buildChoices(), answer: _buildAnswer(),
        explanation: _explanationCtrl.text.trim().isEmpty ? null : _explanationCtrl.text.trim(),
        imagePath: _selectedImagePath, points: points, memo: memo, tags: List.from(_tags),
      );
      await _service.addQuestion(newQ);
      setState(() => _isLoading = false);
      if (!mounted) return;
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('登録完了'),
        content: const Text('問題を登録しました。'),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _resetForm(); }, child: const Text('続けて登録')),
          ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text('完了')),
        ],
      ),
    );
  }

  void _removeChoice(int i) {
    if (_choiceCtrl.length <= 2) return;
    setState(() {
      _choiceCtrl[i].dispose();
      _choiceCtrl.removeAt(i);

      if (_singleAnswerIndex == i) {
        _singleAnswerIndex = 0;
      } else if (_singleAnswerIndex > i) {
        _singleAnswerIndex--;
      }

      final updated = <int>{};
      for (final idx in _multiAnswerIndices) {
        if (idx == i) continue;
        updated.add(idx > i ? idx - 1 : idx);
      }
      _multiAnswerIndices
        ..clear()
        ..addAll(updated);

      if (_choicesError != null) _choicesError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        title: Text(_isEditMode ? '問題編集 — ${widget.setName}' : '問題登録 — ${widget.setName}'),
        actions: [
          // ★ クリップボード貼り付けボタン
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: 'クリップボードから貼り付け',
            onPressed: _pasteFromClipboard,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ★ クリップボード貼り付けバナー（新規登録時のみ）
          if (!_isEditMode)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Row(children: [
                Icon(Icons.content_paste, size: 18, color: Colors.indigo.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'テキストをコピーして「貼り付け」すると問題文・選択肢を自動入力できます',
                    style: TextStyle(fontSize: 12, color: Colors.indigo.shade800),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _pasteFromClipboard,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('貼り付け', style: TextStyle(fontSize: 12)),
                ),
              ]),
            ),

          // 問題タイプ
          const Text('問題タイプ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          _typeSelector(),
          const SizedBox(height: 20),

          // 問題文
          const Text('問題文 *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _questionCtrl,
            maxLines: 4,
            onChanged: (_) { if (_questionError != null) setState(() => _questionError = null); },
            decoration: InputDecoration(
              hintText: '問題文を入力してください',
              border: const OutlineInputBorder(),
              errorText: _questionError,
              errorBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.red, width: 2)),
            ),
          ),
          const SizedBox(height: 20),

          // 画像
          _imageSection(),
          const SizedBox(height: 20),

          // タイプ別入力
          _typeSpecificInput(),
          const SizedBox(height: 20),

          // 配点
          const Text('配点（任意）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _pointsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '未入力の場合は1点', border: OutlineInputBorder(), suffixText: '点'),
          ),
          const SizedBox(height: 20),

          // 解説
          const Text('解説（任意）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _explanationCtrl, maxLines: 3,
            decoration: const InputDecoration(hintText: '解説を入力してください（任意）', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),

          // メモ
          const Text('メモ（任意）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text('自分だけが見るノート。解答後の一言メモなど。', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _memoCtrl, maxLines: 2,
            decoration: const InputDecoration(
              hintText: '例：この概念は○○の本のp.42に詳しい',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.sticky_note_2_outlined),
            ),
          ),
          const SizedBox(height: 20),

          // タグ
          const Text('タグ（任意）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text('Enterまたは「追加」で登録。タグで絞り込み演習できます。', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 8),
          _tagInput(),
          const SizedBox(height: 28),

          ElevatedButton.icon(
            onPressed: _isLoading ? null : _register,
            icon: _isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_isEditMode ? '更新' : '登録', style: const TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _tagInput() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _tagCtrl,
            decoration: const InputDecoration(
              hintText: '例: 重要、要復習、計算問題',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.label_outline),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (v) => _addTag(v),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => _addTag(_tagCtrl.text),
          child: const Text('追加'),
        ),
      ]),
      if (_tags.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6, runSpacing: 4,
          children: _tags.map((tag) => Chip(
            label: Text(tag, style: const TextStyle(fontSize: 12)),
            deleteIcon: const Icon(Icons.close, size: 14),
            onDeleted: () => setState(() => _tags.remove(tag)),
            backgroundColor: Colors.indigo.shade50,
            side: BorderSide(color: Colors.indigo.shade200),
            labelStyle: TextStyle(color: Colors.indigo.shade800),
          )).toList(),
        ),
      ],
    ]);
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() => _tags.add(tag));
    }
    _tagCtrl.clear();
  }

  Widget _typeSelector() {
    return Wrap(
      spacing: 8, runSpacing: 4,
      children: QuestionType.values.map((t) {
        final selected = _selectedType == t;
        return ChoiceChip(
          label: Text(t.label),
          selected: selected,
          onSelected: (_) => setState(() {
            _selectedType = t;
            _singleAnswerIndex = 0;
            _multiAnswerIndices.clear();
            _questionError = null;
            _choicesError = null;
            _shortAnswerError = null;
          }),
        );
      }).toList(),
    );
  }

  Widget _imageSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('画像（任意）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 10),
      if (_selectedImagePath != null) ...[
        ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
        AppImageWidget(path: _selectedImagePath!, width: double.infinity, height: 200, fit: BoxFit.cover),
            Positioned(top: 8, right: 8, child: GestureDetector(
              onTap: () => setState(() => _selectedImagePath = null),
              child: Container(
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                padding: const EdgeInsets.all(6),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            )),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: _pickImage, icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: const Text('画像を変更する'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
        )),
      ] else
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300, width: 1.5),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_photo_alternate_outlined, size: 44, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text('タップして画像を追加', style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('問題に画像を添付できます（任意）', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            ]),
          ),
        ),
    ]);
  }

  Widget _typeSpecificInput() {
    switch (_selectedType) {
      case QuestionType.trueFalse: return _tfInput();
      case QuestionType.singleChoice: return _singleChoiceInput();
      case QuestionType.multipleChoice: return _multipleChoiceInput();
      case QuestionType.shortAnswer: return _shortAnswerInput();
    }
  }

  Widget _tfInput() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('正解 *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _tfButton('○（正しい）', 'true', Colors.green)),
        const SizedBox(width: 12),
        Expanded(child: _tfButton('✕（誤り）', 'false', Colors.red)),
      ]),
    ]);
  }

  Widget _tfButton(String label, String value, Color color) {
    final selected = _tfAnswer == value;
    return GestureDetector(
      onTap: () => setState(() => _tfAnswer = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : Colors.grey.shade300, width: 2),
        ),
        child: Center(child: Text(label,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: selected ? color : Colors.grey))),
      ),
    );
  }

  Widget _singleChoiceInput() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('選択肢と正解 *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 4),
      Text('◉ をタップして正解を選択してください', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      if (_choicesError != null) ...[
        const SizedBox(height: 4),
        Text(_choicesError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
      ],
      const SizedBox(height: 10),
      ...List.generate(_choiceCtrl.length, (i) {
        final selected = _singleAnswerIndex == i;
        final canDelete = _choiceCtrl.length > 2;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            GestureDetector(
              onTap: () => setState(() => _singleAnswerIndex = i),
              child: Padding(padding: const EdgeInsets.all(4),
                  child: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: selected ? Colors.indigo : Colors.grey, size: 26)),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              controller: _choiceCtrl[i],
              onChanged: (_) { if (_choicesError != null) setState(() => _choicesError = null); },
              decoration: InputDecoration(
                hintText: '選択肢 ${i + 1}',
                border: OutlineInputBorder(borderSide: BorderSide(color: selected ? Colors.indigo : Colors.grey)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: selected ? Colors.indigo : Colors.grey.shade400, width: selected ? 2 : 1)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.indigo, width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            )),
            if (canDelete) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _removeChoice(i),
                icon: const Icon(Icons.remove_circle_outline),
                color: Colors.red.shade300,
                tooltip: '選択肢を削除',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ] else
              const SizedBox(width: 36),
          ]),
        );
      }),
      _addChoiceButton(),
    ]);
  }

  Widget _multipleChoiceInput() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('選択肢と正解（複数可） *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 4),
      Text('☑ をタップして正解を選択してください（複数可）', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      if (_choicesError != null) ...[
        const SizedBox(height: 4),
        Text(_choicesError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
      ],
      const SizedBox(height: 10),
      ...List.generate(_choiceCtrl.length, (i) {
        final selected = _multiAnswerIndices.contains(i);
        final canDelete = _choiceCtrl.length > 2;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            GestureDetector(
              onTap: () => setState(() {
                if (selected) _multiAnswerIndices.remove(i); else _multiAnswerIndices.add(i);
                if (_choicesError != null) _choicesError = null;
              }),
              child: Padding(padding: const EdgeInsets.all(4),
                  child: Icon(selected ? Icons.check_box : Icons.check_box_outline_blank,
                      color: selected ? Colors.indigo : Colors.grey, size: 26)),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              controller: _choiceCtrl[i],
              onChanged: (_) { if (_choicesError != null) setState(() => _choicesError = null); },
              decoration: InputDecoration(
                hintText: '選択肢 ${i + 1}', border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            )),
            if (canDelete) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _removeChoice(i),
                icon: const Icon(Icons.remove_circle_outline),
                color: Colors.red.shade300,
                tooltip: '選択肢を削除',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ] else
              const SizedBox(width: 36),
          ]),
        );
      }),
      _addChoiceButton(),
    ]);
  }

  Widget _addChoiceButton() {
    if (_choiceCtrl.length >= 8) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 4),
        child: TextButton.icon(
            onPressed: () => setState(() => _choiceCtrl.add(TextEditingController())),
            icon: const Icon(Icons.add, size: 18), label: const Text('選択肢を追加')));
  }

  Widget _shortAnswerInput() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('模範解答 *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 8),
      TextField(
        controller: _shortAnswerCtrl, maxLines: 3,
        onChanged: (_) { if (_shortAnswerError != null) setState(() => _shortAnswerError = null); },
        decoration: InputDecoration(
          hintText: '模範解答を入力してください', border: const OutlineInputBorder(),
          errorText: _shortAnswerError,
          errorBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.red, width: 2)),
        ),
      ),
      const SizedBox(height: 6),
      Text('※ 記述問題はユーザーが自己採点します', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
    ]);
  }
}
