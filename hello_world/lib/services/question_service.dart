import 'dart:convert';
import 'dart:typed_data';
import '../models/exercise_progress.dart';
import '../models/question.dart';
import '../models/question_set.dart';
import '../services/history_service.dart';
import '../platform/app_storage.dart';
import '../platform/app_file_saver.dart';
import '../platform/question_service_io_native.dart'
    if (dart.library.html) '../platform/question_service_io_web.dart' as _io;

class QuestionService {
  static const _questionsFile = 'questions.json';
  static const _setsFile      = 'question_sets.json';

  final _storage = AppStorage.instance;
  final _saver   = AppFileSaver.instance;

  List<Question>? _qCache;
  DateTime?       _qCacheTime;
  static const _cacheTtl = Duration(seconds: 30);

  bool get _isQCacheValid =>
      _qCache != null &&
      _qCacheTime != null &&
      DateTime.now().difference(_qCacheTime!) < _cacheTtl;

  void _invalidateQCache() { _qCache = null; _qCacheTime = null; }

  // ──────────────────────────────────────────────
  // 問題セット CRUD
  // ──────────────────────────────────────────────
  Future<List<QuestionSet>> loadSets() async {
    try {
      final raw = await _storage.read(_setsFile);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => QuestionSet.fromJson(e))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    } catch (_) { return []; }
  }

  Future<void> saveSets(List<QuestionSet> sets) async {
    await _storage.write(_setsFile, jsonEncode(sets.map((s) => s.toJson()).toList()));
  }

  Future<QuestionSet> addSet(String name, String description) async {
    final sets     = await loadSets();
    final maxOrder = sets.isEmpty ? 0 : sets.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b);
    final newSet   = QuestionSet(
      id: 'set_${DateTime.now().millisecondsSinceEpoch}',
      name: name, description: description,
      createdAt: DateTime.now(), sortOrder: maxOrder + 1,
    );
    sets.add(newSet);
    await saveSets(sets);
    return newSet;
  }

  Future<void> deleteSet(String setId) async {
    final sets = await loadSets();
    sets.removeWhere((s) => s.id == setId);
    await saveSets(sets);
    final questions = await loadQuestions();
    questions.removeWhere((q) => q.setId == setId);
    await _writeQuestions(questions);
    await HistoryService().deleteHistoryForSet(setId);
  }

  Future<void> updateSet(QuestionSet updated) async {
    final sets = await loadSets();
    final idx  = sets.indexWhere((s) => s.id == updated.id);
    if (idx != -1) { sets[idx] = updated; await saveSets(sets); }
  }

  Future<void> reorderSets(List<QuestionSet> reordered) async {
    await saveSets(
        reordered.asMap().entries.map((e) => e.value.copyWith(sortOrder: e.key)).toList());
  }

  // ──────────────────────────────────────────────
  // セット複製
  // ──────────────────────────────────────────────
  Future<QuestionSet> duplicateSet(QuestionSet original, String newName) async {
    final sets     = await loadSets();
    final maxOrder = sets.isEmpty ? 0 : sets.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b);
    final newSetId = 'set_${DateTime.now().millisecondsSinceEpoch}';
    final newSet   = QuestionSet(
      id: newSetId, name: newName, description: original.description,
      createdAt: DateTime.now(), sortOrder: maxOrder + 1,
    );
    sets.add(newSet);
    await saveSets(sets);
    final origQs     = await loadQuestionsForSet(original.id);
    final allQs      = await loadQuestions();
    final duplicated = origQs.asMap().entries.map((e) => Question(
      id: 'q_dup_${DateTime.now().millisecondsSinceEpoch}_${e.key}',
      setId: newSetId, type: e.value.type, question: e.value.question,
      choices: e.value.choices, answer: e.value.answer,
      explanation: e.value.explanation, imagePath: e.value.imagePath,
      points: e.value.points, memo: e.value.memo, tags: List.from(e.value.tags),
    )).toList();
    allQs.addAll(duplicated);
    await _writeQuestions(allQs);
    return newSet;
  }

  // ──────────────────────────────────────────────
  // ホーム一括集計
  // ──────────────────────────────────────────────
  Future<Map<String, int>> loadQuestionCountBySet(List<String> setIds) async {
    final all    = await loadQuestions();
    final counts = {for (final id in setIds) id: 0};
    for (final q in all) {
      if (counts.containsKey(q.setId)) counts[q.setId] = counts[q.setId]! + 1;
    }
    return counts;
  }

  Future<Map<String, int>> loadWeakCountBySet(
    List<String> setIds, {
    double threshold   = 0.6,
    int    minAttempts = 1,
  }) async {
    final all        = await loadQuestions();
    final allHistory = await HistoryService().loadHistory();
    final stats      = <String, Map<String, int>>{};
    for (final q in all) stats[q.id] = {'total': 0, 'correct': 0};
    for (final h in allHistory) {
      if (stats.containsKey(h.questionId)) {
        stats[h.questionId]!['total'] = stats[h.questionId]!['total']! + 1;
        if (h.correct) stats[h.questionId]!['correct'] = stats[h.questionId]!['correct']! + 1;
      }
    }
    final counts = {for (final id in setIds) id: 0};
    for (final q in all) {
      if (!counts.containsKey(q.setId)) continue;
      final s     = stats[q.id];
      final total = s?['total'] ?? 0;
      if (total < minAttempts) continue;
      if (s!['correct']! / total < threshold) counts[q.setId] = counts[q.setId]! + 1;
    }
    return counts;
  }

  // ──────────────────────────────────────────────
  // 問題 CRUD
  // ──────────────────────────────────────────────
  Future<List<Question>> loadQuestions() async {
    if (_isQCacheValid) return List.from(_qCache!);
    try {
      final raw = await _storage.read(_questionsFile);
      if (raw == null) { _qCache = []; _qCacheTime = DateTime.now(); return []; }
      _qCache     = (jsonDecode(raw) as List).map((e) => Question.fromJson(e)).toList();
      _qCacheTime = DateTime.now();
      return List.from(_qCache!);
    } catch (_) { return []; }
  }

  Future<List<Question>> loadQuestionsForSet(String setId) async {
    final all = await loadQuestions();
    return all.where((q) => q.setId == setId).toList();
  }

  Future<void> saveQuestions(List<Question> questions) async => _writeQuestions(questions);

  Future<void> _writeQuestions(List<Question> questions) async {
    await _storage.write(_questionsFile, jsonEncode(questions.map((q) => q.toJson()).toList()));
    _qCache     = List.from(questions);
    _qCacheTime = DateTime.now();
  }

  Future<void> addQuestion(Question question) async {
    final questions = await loadQuestions();
    questions.add(question);
    await _writeQuestions(questions);
  }

  Future<void> updateQuestion(Question updated) async {
    final questions = await loadQuestions();
    final index     = questions.indexWhere((q) => q.id == updated.id);
    if (index != -1) { questions[index] = updated; await _writeQuestions(questions); }
  }

  Future<void> updateQuestionResult({
    required String id, required bool correct, required DateTime answeredAt,
  }) async {
    final raw = await _storage.read(_questionsFile);
    if (raw == null) return;
    final jsonList = jsonDecode(raw) as List;
    for (final item in jsonList) {
      if (item['id'] == id) {
        item['lastCorrect'] = correct;
        item['answeredAt']  = answeredAt.toIso8601String();
        break;
      }
    }
    await _storage.write(_questionsFile, jsonEncode(jsonList));
    _invalidateQCache();
  }

  Future<void> deleteQuestion(String id) async {
    final questions = await loadQuestions();
    questions.removeWhere((q) => q.id == id);
    await _writeQuestions(questions);
  }

  Future<Question> duplicateQuestion(Question original) async {
    final newQ = Question(
      id: 'q_dup_${DateTime.now().millisecondsSinceEpoch}',
      setId: original.setId, type: original.type,
      question: '${original.question}（コピー）',
      choices: original.choices, answer: original.answer,
      explanation: original.explanation, imagePath: original.imagePath,
      points: original.points, memo: original.memo, tags: List.from(original.tags),
    );
    await addQuestion(newQ);
    return newQ;
  }

  Future<void> reorderQuestionsForSet(String setId, List<Question> reordered) async {
    final all      = await loadQuestions();
    final others   = all.where((q) => q.setId != setId).toList();
    final renumbered = reordered.asMap().entries.map((e) {
      final idx = e.key + 1;
      return Question(
        id: 'q${idx.toString().padLeft(4, '0')}_${DateTime.now().millisecondsSinceEpoch + idx}',
        setId: e.value.setId, type: e.value.type, question: e.value.question,
        choices: e.value.choices, answer: e.value.answer,
        explanation: e.value.explanation, imagePath: e.value.imagePath,
        points: e.value.points, memo: e.value.memo, tags: e.value.tags,
      );
    }).toList();
    await _writeQuestions([...others, ...renumbered]);
  }

  Future<void> deleteAndRenumber(String id, String setId) async {
    final all          = await loadQuestions();
    final setQuestions = all.where((q) => q.setId == setId && q.id != id).toList();
    await reorderQuestionsForSet(setId, setQuestions);
  }

  String generateId(List<Question> questions) => 'q_${DateTime.now().millisecondsSinceEpoch}';

  // ──────────────────────────────────────────────
  // 苦手問題フォーカス
  // ──────────────────────────────────────────────
  Future<List<Question>> loadWeakQuestions({
    required String setId, double threshold = 0.6, int minAttempts = 1,
  }) async {
    final questions = await loadQuestionsForSet(setId);
    final history   = await HistoryService().loadHistoryForSet(setId);
    final stats     = <String, Map<String, int>>{};
    for (final q in questions) stats[q.id] = {'total': 0, 'correct': 0};
    for (final h in history) {
      if (stats.containsKey(h.questionId)) {
        stats[h.questionId]!['total'] = stats[h.questionId]!['total']! + 1;
        if (h.correct) stats[h.questionId]!['correct'] = stats[h.questionId]!['correct']! + 1;
      }
    }
    return questions.where((q) {
      final s     = stats[q.id];
      if (s == null) return false;
      final total = s['total']!;
      if (total < minAttempts) return false;
      return s['correct']! / total < threshold;
    }).toList();
  }

  Future<Map<String, double>> getCorrectRates(String setId) async {
    final questions = await loadQuestionsForSet(setId);
    final history   = await HistoryService().loadHistoryForSet(setId);
    final stats     = <String, Map<String, int>>{};
    for (final q in questions) stats[q.id] = {'total': 0, 'correct': 0};
    for (final h in history) {
      if (stats.containsKey(h.questionId)) {
        stats[h.questionId]!['total'] = stats[h.questionId]!['total']! + 1;
        if (h.correct) stats[h.questionId]!['correct'] = stats[h.questionId]!['correct']! + 1;
      }
    }
    return {
      for (final q in questions)
        q.id: () {
          final s = stats[q.id]!;
          return s['total']! == 0 ? -1.0 : s['correct']! / s['total']!;
        }(),
    };
  }

  // ──────────────────────────────────────────────
  // JSON エクスポート
  // ──────────────────────────────────────────────
  Future<String> exportSetToJson(QuestionSet set) async {
    final questions  = await loadQuestionsForSet(set.id);
    final exportData = {
      'version': 1, 'exportedAt': DateTime.now().toIso8601String(),
      'set': set.toJson(), 'questions': questions.map((q) => q.toJson()).toList(),
    };
    final json     = const JsonEncoder.withIndent('  ').convert(exportData);
    final safeName = set.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = '${safeName}_${DateTime.now().millisecondsSinceEpoch}.json';
    return _saver.saveText(text: json, fileName: fileName);
  }

  // ──────────────────────────────────────────────
  // JSON インポート（バイト列 — Web / Native 共通）
  // ──────────────────────────────────────────────
  Future<ImportResult> importSetFromJsonBytes(Uint8List bytes) async {
    try {
      return _importJson(utf8.decode(bytes));
    } catch (e) {
      return ImportResult(success: false, error: 'ファイル読み込みに失敗しました: $e');
    }
  }

  /// Native のみ：パス指定インポート
  Future<ImportResult> importSetFromJson(String filePath) async {
    try {
      final bytes = await _io.readFileBytes(filePath);
      return importSetFromJsonBytes(bytes);
    } catch (e) {
      return ImportResult(success: false, error: 'ファイルが見つかりません: $e');
    }
  }

  Future<ImportResult> _importJson(String raw) async {
    try {
      final data          = jsonDecode(raw) as Map<String, dynamic>;
      final setData       = data['set']       as Map<String, dynamic>;
      final questionsData = data['questions'] as List<dynamic>;
      final existingSets  = await loadSets();
      final existingSetIds = existingSets.map((s) => s.id).toSet();
      final originalSetId  = setData['id'] as String;
      final newSetId       = existingSetIds.contains(originalSetId)
          ? 'set_${DateTime.now().millisecondsSinceEpoch}' : originalSetId;
      final maxOrder = existingSets.isEmpty ? 0
          : existingSets.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b);
      final importedSet = QuestionSet(
        id: newSetId, name: setData['name'] as String,
        description: setData['description'] as String? ?? '',
        createdAt: DateTime.now(), sortOrder: maxOrder + 1,
      );
      existingSets.add(importedSet);
      await saveSets(existingSets);
      final allQuestions = await loadQuestions();
      final existingIds  = allQuestions.map((q) => q.id).toSet();
      final imported     = <Question>[];
      for (final qData in questionsData) {
        final map        = qData as Map<String, dynamic>;
        final originalId = map['id'] as String;
        final newId      = existingIds.contains(originalId)
            ? 'q_${DateTime.now().millisecondsSinceEpoch}_${imported.length}' : originalId;
        existingIds.add(newId);
        imported.add(Question.fromJson({...map, 'id': newId, 'setId': newSetId, 'imagePath': null}));
      }
      allQuestions.addAll(imported);
      await _writeQuestions(allQuestions);
      return ImportResult(success: true, setName: importedSet.name, questionCount: imported.length);
    } catch (e) {
      return ImportResult(success: false, error: 'ファイル形式が不正です: $e');
    }
  }

  // ──────────────────────────────────────────────
  // CSV エクスポート
  // ──────────────────────────────────────────────
  Future<String> exportSetToCsv(QuestionSet set) async {
    final questions = await loadQuestionsForSet(set.id);
    final buffer    = StringBuffer();
    buffer.writeln(
        'type,question,choice1,choice2,choice3,choice4,choice5,choice6,choice7,choice8,'
        'answer,explanation,points,memo,tags');
    for (final q in questions) {
      final choices       = q.choices ?? [];
      final paddedChoices = List<String>.filled(8, '');
      for (int i = 0; i < choices.length && i < 8; i++) paddedChoices[i] = _csvEscape(choices[i]);
      final answerStr = q.answer is List
          ? _csvEscape((q.answer as List).join('|'))
          : _csvEscape(q.answer.toString());
      buffer.writeln([
        q.type.jsonKey, _csvEscape(q.question), ...paddedChoices, answerStr,
        _csvEscape(q.explanation ?? ''), q.points.toString(),
        _csvEscape(q.memo ?? ''), _csvEscape(q.tags.join('|')),
      ].join(','));
    }
    final safeName = set.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = '${safeName}_${DateTime.now().millisecondsSinceEpoch}.csv';
    return _saver.saveText(text: buffer.toString(), fileName: fileName);
  }

  // ──────────────────────────────────────────────
  // CSV インポート（バイト列 — Web / Native 共通）
  // ──────────────────────────────────────────────
  Future<ImportResult> importSetFromCsvBytes(Uint8List bytes, String setName) async {
    try {
      String raw;
      if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        raw = utf8.decode(bytes.sublist(3));
      } else {
        raw = utf8.decode(bytes);
      }
      return _importCsv(raw, setName);
    } catch (e) {
      return ImportResult(success: false, error: 'ファイル読み込みに失敗しました: $e');
    }
  }

  Future<ImportResult> importSetFromCsv(String filePath, String setName) async {
    try {
      final bytes = await _io.readFileBytes(filePath);
      return importSetFromCsvBytes(bytes, setName);
    } catch (e) {
      return ImportResult(success: false, error: 'ファイルが見つかりません: $e');
    }
  }

  Future<ImportResult> _importCsv(String raw, String setName) async {
    final lines = raw.split('\n').map((l) => l.trimRight()).toList();
    if (lines.isEmpty) return ImportResult(success: false, error: 'ファイルが空です');
    final header = _parseCsvLine(lines[0]);
    if (header.isEmpty || header[0].toLowerCase() != 'type') {
      return ImportResult(success: false,
          error: 'CSVのヘッダーが正しくありません。\n1行目は "type,question,choice1,..." の形式にしてください');
    }
    final memoIdx = header.indexWhere((h) => h.toLowerCase() == 'memo');
    final tagsIdx = header.indexWhere((h) => h.toLowerCase() == 'tags');
    final existingSets = await loadSets();
    final maxOrder     = existingSets.isEmpty ? 0
        : existingSets.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b);
    final newSetId    = 'set_${DateTime.now().millisecondsSinceEpoch}';
    final importedSet = QuestionSet(
      id: newSetId, name: setName, description: 'CSVインポート',
      createdAt: DateTime.now(), sortOrder: maxOrder + 1,
    );
    existingSets.add(importedSet);
    await saveSets(existingSets);
    final imported = <Question>[];
    final errors   = <String>[];
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      try {
        final fields       = _parseCsvLine(line);
        if (fields.length < 2) { errors.add('行${i + 1}: フィールドが不足'); continue; }
        final typeStr      = fields[0].trim();
        final questionText = fields[1].trim();
        if (questionText.isEmpty) { errors.add('行${i + 1}: 問題文が空'); continue; }
        final choices = <String>[];
        for (int c = 2; c <= 9 && c < fields.length; c++) {
          final ch = fields[c].trim();
          if (ch.isNotEmpty) choices.add(ch);
        }
        final answerRaw   = fields.length > 10 ? fields[10].trim() : '';
        final explanation = fields.length > 11 ? fields[11].trim() : '';
        final points      = fields.length > 12 ? (int.tryParse(fields[12].trim()) ?? 1) : 1;
        final memo        = (memoIdx > 0 && memoIdx < fields.length) ? fields[memoIdx].trim() : '';
        final tagsRaw     = (tagsIdx > 0 && tagsIdx < fields.length) ? fields[tagsIdx].trim() : '';
        final tags        = tagsRaw.isEmpty ? <String>[]
            : tagsRaw.split('|').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
        final type        = QuestionTypeExt.fromString(typeStr);
        dynamic answer;
        switch (type) {
          case QuestionType.trueFalse:
            final v = answerRaw.toLowerCase();
            answer = (v == 'true' || v == '○' || v == '1' || v == 'o') ? 'true' : 'false';
            break;
          case QuestionType.singleChoice:  answer = answerRaw; break;
          case QuestionType.multipleChoice:
            answer = answerRaw.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            break;
          case QuestionType.shortAnswer:   answer = answerRaw; break;
        }
        imported.add(Question(
          id: 'q_csv_${DateTime.now().millisecondsSinceEpoch}_$i',
          setId: newSetId, type: type, question: questionText,
          choices: choices.isEmpty ? null : choices, answer: answer,
          explanation: explanation.isEmpty ? null : explanation,
          imagePath: null, points: points,
          memo: memo.isEmpty ? null : memo, tags: tags,
        ));
      } catch (e) { errors.add('行${i + 1}: パースエラー ($e)'); }
    }
    if (imported.isEmpty) {
      final sets = await loadSets();
      sets.removeWhere((s) => s.id == newSetId);
      await saveSets(sets);
      return ImportResult(success: false,
          error: '有効な問題が見つかりませんでした。\n${errors.take(3).join('\n')}');
    }
    final allQuestions = await loadQuestions();
    allQuestions.addAll(imported);
    await _writeQuestions(allQuestions);
    return ImportResult(
        success: true, setName: importedSet.name, questionCount: imported.length,
        warnings: errors.isEmpty ? null : errors);
  }

  // ──────────────────────────────────────────────
  // 問題集 PDF 用データ取得
  // ──────────────────────────────────────────────
  Future<Map<String, dynamic>> buildQuestionBookData(QuestionSet set) async {
    final questions = await loadQuestionsForSet(set.id);
    return {'set': set, 'questions': questions};
  }

  // ──────────────────────────────────────────────
  // 間隔反復スケジューラー
  // ──────────────────────────────────────────────
  Future<void> updateReviewSchedule({
    required String questionId,
    required bool correct,
  }) async {
    final questions = await loadQuestions();
    final idx       = questions.indexWhere((q) => q.id == questionId);
    if (idx == -1) return;
    final q       = questions[idx];
    final history = await HistoryService().loadHistoryForSet(q.setId);
    final qHistory = history
        .where((h) => h.questionId == questionId)
        .toList()
      ..sort((a, b) => a.answeredAt.compareTo(b.answeredAt));
    int consecutiveCorrect = 0;
    if (correct) {
      for (int i = qHistory.length - 1; i >= 0; i--) {
        if (qHistory[i].correct) consecutiveCorrect++;
        else break;
      }
      consecutiveCorrect++;
    }
    const intervalDays = [1, 3, 7, 14, 30, 60];
    final days         = intervalDays[consecutiveCorrect.clamp(0, intervalDays.length - 1)];
    final now          = DateTime.now();
    final nextReview   = DateTime(now.year, now.month, now.day).add(Duration(days: days));
    questions[idx] = q.copyWith(nextReviewAt: nextReview);
    await _writeQuestions(questions);
  }

  Future<List<Question>> loadTodaysReviewQuestions(String setId) async =>
      (await loadQuestionsForSet(setId)).where((q) => q.isDueForReview).toList();

  Future<Map<String, int>> loadTodaysReviewCountBySet(List<String> setIds) async {
    final all    = await loadQuestions();
    final counts = {for (final id in setIds) id: 0};
    for (final q in all) {
      if (counts.containsKey(q.setId) && q.isDueForReview) {
        counts[q.setId] = counts[q.setId]! + 1;
      }
    }
    return counts;
  }

  // ──────────────────────────────────────────────
  // CSV ユーティリティ
  // ──────────────────────────────────────────────
  List<String> _parseCsvLine(String line) {
    final fields  = <String>[];
    final buf     = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') { buf.write('"'); i++; }
          else inQuotes = false;
        } else { buf.write(ch); }
      } else {
        if (ch == '"') inQuotes = true;
        else if (ch == ',') { fields.add(buf.toString()); buf.clear(); }
        else buf.write(ch);
      }
    }
    fields.add(buf.toString());
    return fields;
  }

  String _csvEscape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n'))
      return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  // ──────────────────────────────────────────────
  // タグ一覧取得（セット内の全タグを重複なしで返す）
  // ──────────────────────────────────────────────
  Future<List<String>> loadTagsForSet(String setId) async {
    final questions = await loadQuestionsForSet(setId);
    final tags = <String>{};
    for (final q in questions) tags.addAll(q.tags);
    return tags.toList()..sort();
  }

  // ──────────────────────────────────────────────
  // 演習中断状態の保存・読み込み・削除
  // ──────────────────────────────────────────────
  static const _progressKey = 'exercise_progress.json';

  Future<void> saveExerciseProgress(ExerciseProgress progress) async {
    await _storage.write(_progressKey, jsonEncode(progress.toJson()));
  }

  Future<ExerciseProgress?> loadExerciseProgress() async {
    try {
      final raw = await _storage.read(_progressKey);
      if (raw == null) return null;
      return ExerciseProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearExerciseProgress() async {
    await _storage.delete(_progressKey);
  }
}

class ImportResult {
  final bool          success;
  final String?       setName;
  final int?          questionCount;
  final String?       error;
  final List<String>? warnings;
  ImportResult({required this.success, this.setName, this.questionCount, this.error, this.warnings});
}
