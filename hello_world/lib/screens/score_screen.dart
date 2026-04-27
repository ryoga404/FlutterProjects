import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/answer_history.dart';
import '../models/question.dart';
import '../models/question_set.dart';
import '../services/history_service.dart';
import '../services/question_service.dart';
import '../services/pdf_service.dart';
import '../platform/app_file_saver.dart';

enum ScoreFilter { all, correct, incorrect }
enum SortOrder { asc, desc }

class ScoreScreen extends StatefulWidget {
  final QuestionSet set;
  const ScoreScreen({super.key, required this.set});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen>
    with SingleTickerProviderStateMixin {
  final _historyService = HistoryService();
  final _questionService = QuestionService();
  final _pdfService = PdfService();
  final _fileSaver = AppFileSaver.instance;

  List<AnswerHistory> _history = [];
  List<Question> _questions = [];
  bool _isLoading = true;
  bool _isPdfGenerating = false;

  ScoreFilter _filter = ScoreFilter.all;
  SortOrder _sortOrder = SortOrder.desc;
  int _currentPage = 1;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const int _perPage = 10;
  String _trendUnit = 'day';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final history   = await _historyService.loadHistoryForSet(widget.set.id);
    final questions = await _questionService.loadQuestionsForSet(widget.set.id);
    setState(() { _history = history; _questions = questions; _isLoading = false; });
  }

  Future<void> _resetHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解答履歴をリセット'),
        content: Text('「${widget.set.name}」の解答履歴をすべて削除しますか？\n問題は残ります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('リセット'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _historyService.deleteHistoryForSet(widget.set.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('解答履歴をリセットしました')));
      _load();
    }
  }

  // ──────────────────────────────────────────────
  // ★ 統計 CSV エクスポート（Web / Native 共通）
  // ──────────────────────────────────────────────
  Future<void> _exportStatsCsv() async {
    try {
      final buffer = StringBuffer();

      // サマリー
      buffer.writeln('# サマリー');
      buffer.writeln('セット名,${_csvEscape(widget.set.name)}');
      final total   = _history.length;
      final correct = _history.where((h) => h.correct).length;
      final rate    = total > 0 ? correct / total : 0.0;
      buffer.writeln('総回答数,$total');
      buffer.writeln('正解数,$correct');
      buffer.writeln('不正解数,${total - correct}');
      buffer.writeln('正答率,${(rate * 100).toStringAsFixed(1)}%');
      buffer.writeln('エクスポート日時,${DateTime.now().toIso8601String()}');
      buffer.writeln();

      // 問題別統計
      buffer.writeln('# 問題別統計');
      buffer.writeln('問題ID,問題文（先頭50文字）,タイプ,タグ,総回答,正解,不正解,正答率,連続正解数,次回復習日');
      final stats = _questionStats;
      for (final s in stats) {
        final q       = s['question'] as Question;
        final qTotal  = s['total'] as int;
        final qCorrect = s['correct'] as int;
        final qRate   = qTotal > 0 ? (qCorrect / qTotal * 100).toStringAsFixed(1) : '-';
        final qHistories = _history.where((h) => h.questionId == q.id).toList()
          ..sort((a, b) => a.answeredAt.compareTo(b.answeredAt));
        int consecutive = 0;
        for (int i = qHistories.length - 1; i >= 0; i--) {
          if (qHistories[i].correct) consecutive++;
          else break;
        }
        final preview    = q.question.length > 50 ? q.question.substring(0, 50) : q.question;
        final nextReview = q.nextReviewAt != null
            ? '${q.nextReviewAt!.year}/${q.nextReviewAt!.month.toString().padLeft(2,'0')}/${q.nextReviewAt!.day.toString().padLeft(2,'0')}'
            : '未解答';
        buffer.writeln([
          _csvEscape(q.id), _csvEscape(preview), q.type.label, _csvEscape(q.tags.join('|')),
          qTotal, qCorrect, qTotal - qCorrect, '$qRate%', consecutive, nextReview,
        ].join(','));
      }
      buffer.writeln();

      // 日別統計
      buffer.writeln('# 日別統計（直近30日）');
      buffer.writeln('日付,総回答,正解,不正解,正答率');
      for (final d in _dailyRateData) {
        final dTotal   = d['total'] as int;
        final dCorrect = d['correct'] as int;
        final dRate    = d['rate'] as double?;
        final date     = d['date'] as DateTime;
        final dateStr  = '${date.year}/${date.month.toString().padLeft(2,'0')}/${date.day.toString().padLeft(2,'0')}';
        buffer.writeln([
          dateStr, dTotal, dCorrect, dTotal - dCorrect,
          dRate != null ? '${(dRate * 100).toStringAsFixed(1)}%' : '-',
        ].join(','));
      }
      buffer.writeln();

      // 全履歴
      buffer.writeln('# 解答履歴（全件）');
      buffer.writeln('履歴ID,セットID,問題ID,問題文（先頭30文字）,正誤,解答日時');
      final sorted = List<AnswerHistory>.from(_history)
        ..sort((a, b) => b.answeredAt.compareTo(a.answeredAt));
      for (final h in sorted) {
        final preview = h.questionText.length > 30 ? h.questionText.substring(0, 30) : h.questionText;
        buffer.writeln([
          _csvEscape(h.id), _csvEscape(h.setId), _csvEscape(h.questionId),
          _csvEscape(preview), h.correct ? '正解' : '不正解', h.answeredAt.toIso8601String(),
        ].join(','));
      }

      // BOM 付き UTF-8
      final bom   = [0xEF, 0xBB, 0xBF];
      final body  = utf8.encode(buffer.toString());
      final bytes = Uint8List.fromList([...bom, ...body]);

      final safeName = widget.set.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = '${safeName}_stats_${DateTime.now().millisecondsSinceEpoch}.csv';
      final path     = await _fileSaver.save(bytes: bytes, fileName: fileName);

      if (!mounted) return;
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSVをダウンロードしました'), backgroundColor: Colors.green));
      } else {
        _showExportSuccessDialog(path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV出力エラー: $e'), backgroundColor: Colors.red));
    }
  }

  void _showExportSuccessDialog(String filePath) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('CSV出力完了'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('以下のパスに保存しました：'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
            child: SelectableText(filePath, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 8),
          Text('Excel やスプレッドシートで開いて分析できます。\n（BOM付きUTF-8形式）',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  String _csvEscape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n'))
      return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  List<AnswerHistory> get _filtered {
    List<AnswerHistory> list = List.from(_history);
    switch (_filter) {
      case ScoreFilter.correct:   list = list.where((h) => h.correct).toList();  break;
      case ScoreFilter.incorrect: list = list.where((h) => !h.correct).toList(); break;
      case ScoreFilter.all: break;
    }
    if (_dateFrom != null) list = list.where((h) => !h.answeredAt.isBefore(_dateFrom!)).toList();
    if (_dateTo != null) {
      final toEnd = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
      list = list.where((h) => !h.answeredAt.isAfter(toEnd)).toList();
    }
    if (_sortOrder == SortOrder.asc) list.sort((a, b) => a.answeredAt.compareTo(b.answeredAt));
    else list.sort((a, b) => b.answeredAt.compareTo(a.answeredAt));
    return list;
  }

  List<AnswerHistory> get _paginated {
    final f = _filtered;
    final start = (_currentPage - 1) * _perPage;
    final end   = (start + _perPage).clamp(0, f.length);
    return f.sublist(start, end);
  }

  int get _totalPages => (_filtered.length / _perPage).ceil().clamp(1, 99999);

  List<Map<String, dynamic>> get _questionStats {
    final stats = <String, Map<String, dynamic>>{};
    for (final q in _questions) stats[q.id] = {'question': q, 'total': 0, 'correct': 0};
    for (final h in _history) {
      if (stats.containsKey(h.questionId)) {
        stats[h.questionId]!['total']   = (stats[h.questionId]!['total']   as int) + 1;
        if (h.correct) stats[h.questionId]!['correct'] = (stats[h.questionId]!['correct'] as int) + 1;
      }
    }
    final result = stats.values.where((s) => (s['total'] as int) > 0).toList();
    result.sort((a, b) {
      final ra = a['total'] == 0 ? 0.0 : (a['correct'] as int) / (a['total'] as int);
      final rb = b['total'] == 0 ? 0.0 : (b['correct'] as int) / (b['total'] as int);
      return ra.compareTo(rb);
    });
    return result;
  }

  List<Map<String, dynamic>> get _dailyRateData {
    final today = DateTime.now();
    final stats = <String, Map<String, int>>{};
    for (final h in _history) {
      final key = '${h.answeredAt.year}-${h.answeredAt.month.toString().padLeft(2,'0')}-${h.answeredAt.day.toString().padLeft(2,'0')}';
      stats.putIfAbsent(key, () => {'total': 0, 'correct': 0});
      stats[key]!['total'] = stats[key]!['total']! + 1;
      if (h.correct) stats[key]!['correct'] = stats[key]!['correct']! + 1;
    }
    final result = <Map<String, dynamic>>[];
    for (int i = 29; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final key  = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
      final s    = stats[key];
      result.add({'date': date, 'key': key,
        'total': s?['total'] ?? 0, 'correct': s?['correct'] ?? 0,
        'rate': (s != null && s['total']! > 0) ? s['correct']! / s['total']! : null});
    }
    return result;
  }

  List<Map<String, dynamic>> get _weeklyRateData {
    final now   = DateTime.now();
    final stats = <String, Map<String, int>>{};
    for (final h in _history) {
      final dt     = h.answeredAt;
      final day    = DateTime(dt.year, dt.month, dt.day);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      final key    = '${monday.year}-${monday.month.toString().padLeft(2,'0')}-${monday.day.toString().padLeft(2,'0')}';
      stats.putIfAbsent(key, () => {'total': 0, 'correct': 0});
      stats[key]!['total'] = stats[key]!['total']! + 1;
      if (h.correct) stats[key]!['correct'] = stats[key]!['correct']! + 1;
    }
    final today      = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final result = <Map<String, dynamic>>[];
    for (int i = 11; i >= 0; i--) {
      final date = thisMonday.subtract(Duration(days: i * 7));
      final key  = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
      final s    = stats[key];
      result.add({'date': date, 'key': key, 'label': '${date.month}/${date.day}',
        'total': s?['total'] ?? 0, 'correct': s?['correct'] ?? 0,
        'rate': (s != null && s['total']! > 0) ? s['correct']! / s['total']! : null});
    }
    return result;
  }

  List<Map<String, dynamic>> get _monthlyRateData {
    final now   = DateTime.now();
    final stats = <String, Map<String, int>>{};
    for (final h in _history) {
      final key = '${h.answeredAt.year}-${h.answeredAt.month.toString().padLeft(2,'0')}';
      stats.putIfAbsent(key, () => {'total': 0, 'correct': 0});
      stats[key]!['total'] = stats[key]!['total']! + 1;
      if (h.correct) stats[key]!['correct'] = stats[key]!['correct']! + 1;
    }
    final result = <Map<String, dynamic>>[];
    for (int i = 11; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final key   = '${month.year}-${month.month.toString().padLeft(2,'0')}';
      final s     = stats[key];
      result.add({'date': month, 'key': key, 'label': '${month.month}月',
        'total': s?['total'] ?? 0, 'correct': s?['correct'] ?? 0,
        'rate': (s != null && s['total']! > 0) ? s['correct']! / s['total']! : null});
    }
    return result;
  }

  // ──────────────────────────────────────────────
  // PDF
  // ──────────────────────────────────────────────
  Future<void> _showPdfDialog() async {
    DateTime? fromDate;
    DateTime? toDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          List<AnswerHistory> preview = List.from(_history);
          if (fromDate != null) preview = preview.where((h) => !h.answeredAt.isBefore(fromDate!)).toList();
          if (toDate != null) {
            final toEnd = DateTime(toDate!.year, toDate!.month, toDate!.day, 23, 59, 59);
            preview = preview.where((h) => !h.answeredAt.isAfter(toEnd)).toList();
          }
          final previewCount = preview.length;
          return AlertDialog(
            title: const Row(children: [Icon(Icons.picture_as_pdf, color: Colors.red), SizedBox(width: 8), Text('PDF出力')]),
            content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [const Icon(Icons.folder, size: 16, color: Colors.indigo), const SizedBox(width: 8),
                    Expanded(child: Text(widget.set.name, style: const TextStyle(fontWeight: FontWeight.bold)))])),
              const SizedBox(height: 18),
              const Text('抽出期間', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _datePickerField(ctx, fromDate, '開始日', (d) => setD(() => fromDate = d), () => setD(() => fromDate = null))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('〜', style: TextStyle(fontSize: 18))),
                Expanded(child: _datePickerField(ctx, toDate, '終了日', (d) => setD(() => toDate = d), () => setD(() => toDate = null))),
              ]),
              const SizedBox(height: 6),
              Text('$previewCount 件が対象', style: TextStyle(fontSize: 12,
                  color: previewCount > 0 ? Colors.indigo : Colors.red, fontWeight: FontWeight.bold)),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
              ElevatedButton.icon(
                onPressed: previewCount == 0 ? null : () async {
                  Navigator.pop(ctx);
                  await _generatePdf(fromDate: fromDate, toDate: toDate);
                },
                icon: const Icon(Icons.download), label: const Text('出力'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _generatePdf({DateTime? fromDate, DateTime? toDate}) async {
    setState(() => _isPdfGenerating = true);
    try {
      List<AnswerHistory> target = List.from(_history);
      if (fromDate != null) target = target.where((h) => !h.answeredAt.isBefore(fromDate)).toList();
      if (toDate != null) {
        final toEnd = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);
        target = target.where((h) => !h.answeredAt.isAfter(toEnd)).toList();
      }
      final filePath = await _pdfService.generateScoreReport(
          set: widget.set, history: target, questions: _questions, saveDir: null);
      if (!mounted) return;
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDFをダウンロードしました'), backgroundColor: Colors.green));
      } else {
        _showPdfSuccessDialog(filePath);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF生成エラー: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isPdfGenerating = false);
    }
  }

  void _showPdfSuccessDialog(String filePath) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('PDF出力完了')]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('以下のパスに保存しました：'), const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
            child: SelectableText(filePath, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
      ]),
      actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ));
  }

  Widget _datePickerField(BuildContext ctx, DateTime? value, String hint,
      Function(DateTime) onPick, VoidCallback onClear) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(context: ctx,
            initialDate: value ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          const Icon(Icons.calendar_today, size: 14, color: Colors.grey), const SizedBox(width: 6),
          Expanded(child: Text(value != null ? _fmtDate(value) : hint,
              style: TextStyle(fontSize: 12, color: value != null ? Colors.black : Colors.grey))),
          if (value != null) GestureDetector(onTap: onClear, child: const Icon(Icons.close, size: 14, color: Colors.grey)),
        ]),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final total   = _history.length;
    final correct = _history.where((h) => h.correct).length;
    final rate    = total > 0 ? correct / total : 0.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        title: Text('成績 — ${widget.set.name}'),
        actions: [
          if (!_isLoading && _history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.table_chart_outlined),
              tooltip: '統計をCSVエクスポート',
              onPressed: _exportStatsCsv,
            ),
          IconButton(icon: const Icon(Icons.replay), tooltip: '履歴をリセット',
              onPressed: _history.isEmpty ? null : _resetHistory),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.history),     text: '解答履歴'),
            Tab(icon: Icon(Icons.trending_up), text: '推移'),
            Tab(icon: Icon(Icons.analytics),   text: '問題別'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _summaryCard(total, correct, rate),
              Expanded(child: TabBarView(controller: _tabController,
                  children: [_historyTab(), _trendTab(), _analysisTab()])),
            ]),
      floatingActionButton: _history.isEmpty ? null
          : FloatingActionButton.extended(
              onPressed: _isPdfGenerating ? null : _showPdfDialog,
              backgroundColor: Colors.red.shade700, foregroundColor: Colors.white,
              icon: _isPdfGenerating
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_isPdfGenerating ? '生成中...' : 'PDF出力')),
    );
  }

  Widget _summaryCard(int total, int correct, double rate) {
    final incorrect = total - correct;
    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _statItem('総回答', total, Colors.blue, ScoreFilter.all),
        _vDivider(),
        _statItem('正解', correct, Colors.green, ScoreFilter.correct),
        _vDivider(),
        _statItem('不正解', incorrect, Colors.red, ScoreFilter.incorrect),
        _vDivider(),
        Column(children: [
          Text(total > 0 ? '${(rate * 100).toStringAsFixed(1)}%' : '-',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.purple)),
          const Text('正答率', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ]),
    );
  }

  Widget _statItem(String label, int count, Color color, ScoreFilter filter) {
    final selected = _filter == filter;
    return GestureDetector(
      onTap: () => setState(() { _filter = filter; _currentPage = 1; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        ),
        child: Column(children: [
          Text('$count', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }

  Widget _vDivider() => Container(height: 40, width: 1, color: Colors.grey.shade300);

  // ──────────────────────────────────────────────
  // 解答履歴タブ
  // ──────────────────────────────────────────────
  Widget _historyTab() {
    final filtered  = _filtered;
    final paginated = _paginated;
    if (_history.isEmpty) return const Center(child: Text('解答履歴がありません', style: TextStyle(color: Colors.grey)));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: _showDateFilter,
            icon: Icon(Icons.date_range, size: 15,
                color: (_dateFrom != null || _dateTo != null) ? Colors.orange : null),
            label: Text((_dateFrom != null || _dateTo != null) ? _dateRangeLabel() : '日付絞り込み',
                style: TextStyle(fontSize: 11,
                    color: (_dateFrom != null || _dateTo != null) ? Colors.orange : null)),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() {
              _sortOrder = _sortOrder == SortOrder.asc ? SortOrder.desc : SortOrder.asc;
              _currentPage = 1;
            }),
            child: Row(children: [
              const Text('解答日', style: TextStyle(fontSize: 12)),
              Icon(_sortOrder == SortOrder.asc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14, color: Theme.of(context).colorScheme.primary),
            ]),
          ),
          const SizedBox(width: 8),
          Text('${filtered.length}件', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
      Container(
        color: Theme.of(context).colorScheme.surfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: const Row(children: [
          SizedBox(width: 36, child: Text('種別', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text('問題', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('解答日時', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          SizedBox(width: 40, child: Text('正誤', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        ]),
      ),
      Expanded(
        child: filtered.isEmpty
            ? const Center(child: Text('該当なし', style: TextStyle(color: Colors.grey)))
            : ListView.separated(
                itemCount: paginated.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final h = paginated[i];
                  final q = _questions.where((q) => q.id == h.questionId).firstOrNull;
                  return InkWell(
                    onTap: () => _showHistoryDetail(h, q),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        SizedBox(width: 36, child: _typeMini(q?.type)),
                        Expanded(flex: 3, child: Text(_truncate(h.questionText, 15),
                            style: const TextStyle(fontSize: 13))),
                        Expanded(flex: 2, child: Text(_fmt(h.answeredAt),
                            style: const TextStyle(fontSize: 10, color: Colors.grey))),
                        SizedBox(width: 40, child: Center(child: Icon(
                            h.correct ? Icons.check_circle : Icons.cancel,
                            color: h.correct ? Colors.green : Colors.red, size: 22))),
                      ]),
                    ),
                  );
                },
              ),
      ),
      _pagination(),
    ]);
  }

  void _showHistoryDetail(AnswerHistory h, Question? q) {
    showDialog(
      context: context,
      builder: (ctx) {
        final screen = MediaQuery.of(ctx).size;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: EdgeInsets.symmetric(
              horizontal: screen.width * 0.075, vertical: screen.height * 0.075),
          child: SizedBox(
            width: screen.width * 0.85,
            height: screen.height * 0.85,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
                decoration: BoxDecoration(
                  color: h.correct ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(
                      color: h.correct ? Colors.green.shade200 : Colors.red.shade200)),
                ),
                child: Row(children: [
                  Icon(h.correct ? Icons.check_circle : Icons.cancel,
                      color: h.correct ? Colors.green : Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Text(h.correct ? '正解' : '不正解',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                          color: h.correct ? Colors.green.shade700 : Colors.red.shade700)),
                  const SizedBox(width: 10),
                  if (q != null) _typeMini(q.type),
                  const Spacer(),
                  Text(_fmt(h.answeredAt).replaceAll('\n', '  '),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  IconButton(onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close), iconSize: 20,
                      padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _sectionLabel('問題文'),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
                    ),
                    child: SelectableText(h.questionText, style: const TextStyle(fontSize: 14, height: 1.6)),
                  ),
                ]),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _sectionLabel(
                        (q != null && (q.type == QuestionType.singleChoice || q.type == QuestionType.multipleChoice))
                            ? '選択肢' : '正解',
                      ),
                      const SizedBox(height: 6),
                      Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (q != null &&
                            (q.type == QuestionType.singleChoice || q.type == QuestionType.multipleChoice) &&
                            q.choices != null)
                          _historyChoiceList(q, h)
                        else if (q != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade300)),
                            child: _correctAnswerWidget(q),
                          ),
                        if (q == null || q.type == QuestionType.shortAnswer || q.type == QuestionType.trueFalse) ...[
                          const SizedBox(height: 10),
                          _sectionLabel('あなたの回答'),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: h.correct ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: h.correct ? Colors.green.shade300 : Colors.red.shade300),
                            ),
                            child: SelectableText(_formatUserAnswer(h.userAnswer),
                                style: TextStyle(fontSize: 13, height: 1.5,
                                    color: h.correct ? Colors.green.shade800 : Colors.red.shade800)),
                          ),
                        ],
                      ]))),
                    ])),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(width: 1, color: Colors.grey.shade200)),
                    Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _sectionLabel('解説'),
                      const SizedBox(height: 6),
                      if (q?.explanation != null && q!.explanation!.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200)),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.lightbulb_outline, color: Colors.blue, size: 14),
                            const SizedBox(width: 6),
                            Expanded(child: SelectableText(q.explanation!,
                                style: const TextStyle(fontSize: 13, height: 1.6))),
                          ]),
                        )
                      else
                        Text('解説なし', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 16),
                      _sectionLabel('メモ'),
                      const SizedBox(height: 6),
                      if (q != null)
                        _memoEditWidget(q, onSaved: (updatedQ) {
                          setState(() {
                            final idx = _questions.indexWhere((e) => e.id == updatedQ.id);
                            if (idx != -1) _questions[idx] = updatedQ;
                          });
                        })
                      else
                        Text('メモなし', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
                    ]))),
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Row(children: [
      Container(width: 3, height: 13,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700)),
    ]);
  }

  Widget _historyChoiceList(Question q, AnswerHistory h) {
    final choices    = q.choices ?? [];
    final correctSet = q.type == QuestionType.multipleChoice
        ? Set<String>.from(List<String>.from(q.answer))
        : <String>{q.answer.toString()};
    Set<String> userSet = {};
    if (h.userAnswer is List) {
      userSet = Set<String>.from(List<String>.from(h.userAnswer as List));
    } else if (h.userAnswer != null) {
      userSet = {h.userAnswer.toString()};
    }
    return Column(children: choices.map((c) {
      final isCorrect = correctSet.contains(c);
      final isUser    = userSet.contains(c);
      Color bgColor; Color borderColor; IconData icon; Color iconColor;
      if (isCorrect && isUser) {
        bgColor = Colors.green.shade50; borderColor = Colors.green.shade300;
        icon = Icons.check_circle; iconColor = Colors.green;
      } else if (!isCorrect && isUser) {
        bgColor = Colors.red.shade50; borderColor = Colors.red.shade300;
        icon = Icons.cancel; iconColor = Colors.red;
      } else if (isCorrect && !isUser) {
        bgColor = Colors.green.shade50.withOpacity(0.5); borderColor = Colors.green.shade200;
        icon = Icons.check_circle_outline; iconColor = Colors.green.shade400;
      } else {
        bgColor = Colors.grey.shade50; borderColor = Colors.grey.shade200;
        icon = Icons.radio_button_unchecked; iconColor = Colors.grey.shade400;
      }
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: iconColor, size: 16), const SizedBox(width: 7),
          Expanded(child: SelectableText(c,
              style: TextStyle(fontSize: 13,
                  fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
                  color: isCorrect ? Colors.black87 : Colors.grey.shade700))),
          if (isUser || isCorrect) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                  color: isUser ? (isCorrect ? Colors.green.shade100 : Colors.red.shade100) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(isUser ? 'あなたの選択' : '未選択',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                      color: isUser ? (isCorrect ? Colors.green.shade800 : Colors.red.shade800) : Colors.grey.shade700)),
            ),
          ],
        ]),
      );
    }).toList());
  }

  String _formatUserAnswer(dynamic userAnswer) {
    if (userAnswer == null) return '（未回答）';
    if (userAnswer is List) return (List<String>.from(userAnswer)).isEmpty ? '（未回答）' : List<String>.from(userAnswer).join('\n');
    final s = userAnswer.toString();
    if (s == 'true')  return '○（正しい）';
    if (s == 'false') return '✕（誤り）';
    return s.isEmpty ? '（未回答）' : s;
  }

  // ──────────────────────────────────────────────
  // 推移タブ
  // ──────────────────────────────────────────────
  List<Map<String, dynamic>> _buildTrendData() {
    switch (_trendUnit) {
      case 'week':  return _weeklyRateData;
      case 'month': return _monthlyRateData;
      default:      return _dailyRateData;
    }
  }

  Widget _trendTab() {
    if (_history.isEmpty) return const Center(child: Text('解答履歴がありません', style: TextStyle(color: Colors.grey)));
    final data    = _buildTrendData();
    final hasData = data.any((d) => d['total'] as int > 0);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('正答率推移', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day',   label: Text('日別')),
              ButtonSegment(value: 'week',  label: Text('週別')),
              ButtonSegment(value: 'month', label: Text('月別')),
            ],
            selected: {_trendUnit},
            onSelectionChanged: (s) => setState(() => _trendUnit = s.first),
            style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        ]),
        const SizedBox(height: 4),
        Text('棒グラフの高さ = 正答率、数字 = 回答数',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        const SizedBox(height: 16),
        if (!hasData)
          Container(padding: const EdgeInsets.all(24), alignment: Alignment.center,
              child: Text('この期間のデータがありません', style: TextStyle(color: Colors.grey.shade400)))
        else
          SizedBox(height: 200, child: _buildBarChart(data)),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 4, children: [
          _legendItem(Colors.green.shade400, '正答率 ≥ 80%'),
          _legendItem(Colors.orange,          '50% 〜 80%'),
          _legendItem(Colors.red.shade400,    '正答率 < 50%'),
          _legendItem(Colors.grey.shade300,   '回答なし'),
        ]),
        const SizedBox(height: 24),
        _recentSummary(data),
      ]),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 12, height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  Widget _buildBarChart(List<Map<String, dynamic>> data) {
    return LayoutBuilder(builder: (context, constraints) {
      const double yAxisWidth = 30.0;
      const double yAxisGap   = 4.0;
      final double chartWidth = constraints.maxWidth - yAxisWidth - yAxisGap;
      final double barWidth   = chartWidth / data.length;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: yAxisWidth,
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                Text('100%', style: TextStyle(fontSize: 9, color: Colors.grey)),
                Text('75%',  style: TextStyle(fontSize: 9, color: Colors.grey)),
                Text('50%',  style: TextStyle(fontSize: 9, color: Colors.grey)),
                Text('25%',  style: TextStyle(fontSize: 9, color: Colors.grey)),
                Text('0%',   style: TextStyle(fontSize: 9, color: Colors.grey)),
              ]),
        ),
        const SizedBox(width: yAxisGap),
        Expanded(child: Stack(children: [
          Column(children: [0, 1, 2, 3, 4].map((_) => Expanded(child: Container(
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)))))).toList()),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.map((d) {
              final total   = d['total'] as int;
              final rate    = d['rate']  as double?;
              final date    = d['date']  as DateTime;
              final label   = d['label'] as String? ?? '${date.month}/${date.day}';
              final now     = DateTime.now();
              final isToday = date.day == now.day && date.month == now.month && date.year == now.year;
              Color barColor = Colors.grey.shade200;
              if (rate != null) {
                if (rate >= 0.8) barColor = Colors.green.shade400;
                else if (rate >= 0.5) barColor = Colors.orange;
                else barColor = Colors.red.shade400;
              }
              return Expanded(child: Tooltip(
                message: total > 0 ? '$label\n$total回答\n${(rate! * 100).toStringAsFixed(0)}%正解' : '$label\n回答なし',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0.5),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (total > 0 && barWidth > 14)
                      Text('$total', style: const TextStyle(fontSize: 7, color: Colors.grey), overflow: TextOverflow.clip),
                    Container(
                      height: rate != null ? 150 * rate : 2,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        border: isToday ? Border.all(color: Colors.indigo, width: 1) : null,
                      ),
                    ),
                    if (barWidth > 12)
                      Text(label, style: const TextStyle(fontSize: 7, color: Colors.grey), overflow: TextOverflow.clip)
                    else
                      const SizedBox(height: 10),
                  ]),
                ),
              ));
            }).toList(),
          ),
        ])),
      ]);
    });
  }

  Widget _recentSummary(List<Map<String, dynamic>> data) {
    final recent7      = data.where((d) => (d['total'] as int) > 0).take(7).toList();
    if (recent7.isEmpty) return const SizedBox.shrink();
    final totalAns     = recent7.fold<int>(0, (s, d) => s + (d['total']   as int));
    final totalCorrect = recent7.fold<int>(0, (s, d) => s + (d['correct'] as int));
    final avgRate = totalAns > 0 ? totalCorrect / totalAns : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('直近の学習サマリー', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        Row(children: [
          _summaryItem('学習期間数', '${recent7.length}', Colors.blue),
          _summaryItem('総回答', '$totalAns問', Colors.orange),
          _summaryItem('平均正答率', '${(avgRate * 100).toStringAsFixed(1)}%',
              avgRate >= 0.8 ? Colors.green : avgRate >= 0.5 ? Colors.orange : Colors.red),
        ]),
      ]),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Expanded(child: Column(children: [
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]));
  }

  // ──────────────────────────────────────────────
  // 問題別分析タブ
  // ──────────────────────────────────────────────
  Widget _analysisTab() {
    final stats = _questionStats;
    if (stats.isEmpty) return const Center(child: Text('まだ回答データがありません', style: TextStyle(color: Colors.grey)));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: stats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s       = stats[i];
        final q       = s['question'] as Question;
        final total   = s['total']    as int;
        final correct = s['correct']  as int;
        final rate    = total > 0 ? correct / total : 0.0;
        final rateColor = rate >= 0.8 ? Colors.green : rate >= 0.5 ? Colors.orange : Colors.red;
        return GestureDetector(
          onTap: () => _showQuestionDetail(q, total, correct, rate),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _typeMini(q.type), const SizedBox(width: 8),
                Expanded(child: Text(_truncate(q.question, 35),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                Text('${(rate * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: rateColor)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
              ]),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
                  value: rate, minHeight: 8, backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(rateColor))),
              const SizedBox(height: 4),
              Row(children: [
                Text('$total回中 $correct回正解', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (q.tags.isNotEmpty) ...[
                  const Spacer(),
                  ...q.tags.take(2).map((t) => Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
                    child: Text(t, style: TextStyle(fontSize: 9, color: Colors.indigo.shade700)),
                  )),
                ],
              ]),
            ]),
          ),
        );
      },
    );
  }

  void _showQuestionDetail(Question q, int total, int correct, double rate) {
    final rateColor = rate >= 0.8 ? Colors.green : rate >= 0.5 ? Colors.orange : Colors.red;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.3,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              _typeMini(q.type), const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: rateColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: rateColor.withOpacity(0.4))),
                child: Text('正答率 ${(rate * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: rateColor, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('問題文', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2))),
              child: SelectableText(q.question, style: const TextStyle(fontSize: 15, height: 1.6)),
            ),
            const SizedBox(height: 16),
            if ((q.type == QuestionType.singleChoice || q.type == QuestionType.multipleChoice) && q.choices != null) ...[
              const Text('選択肢', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 6),
              Column(children: (q.choices ?? []).asMap().entries.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                child: Row(children: [
                  Text('${e.key + 1}.', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText(e.value, style: const TextStyle(fontSize: 14))),
                ]),
              )).toList()),
              const SizedBox(height: 12),
            ],
            const Text('正解', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade300)),
              child: _correctAnswerWidget(q),
            ),
            if (q.explanation != null && q.explanation!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('解説', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.lightbulb_outline, color: Colors.blue, size: 16), const SizedBox(width: 6),
                  Expanded(child: SelectableText(q.explanation!, style: const TextStyle(fontSize: 14, height: 1.5))),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            const Text('回答統計', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 6),
            Row(children: [
              _detailStatItem('総回答', '$total回', Colors.blue),
              _detailStatItem('正解', '$correct回', Colors.green),
              _detailStatItem('不正解', '${total - correct}回', Colors.red),
            ]),
            const SizedBox(height: 20),
            const Text('メモ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 6),
            _memoEditWidget(q, onSaved: (updatedQ) {
              setState(() {
                final idx = _questions.indexWhere((e) => e.id == updatedQ.id);
                if (idx != -1) _questions[idx] = updatedQ;
              });
              Navigator.pop(ctx);
              _showQuestionDetail(updatedQ, total, correct, rate);
            }),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _correctAnswerWidget(Question q) {
    switch (q.type) {
      case QuestionType.trueFalse:
        return Text(q.answer == 'true' ? '○（正しい）' : '✕（誤り）',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold));
      case QuestionType.singleChoice:
        return SelectableText(q.answer.toString(), style: const TextStyle(fontSize: 15));
      case QuestionType.multipleChoice:
        return Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: List<String>.from(q.answer).map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.check, color: Colors.green, size: 16), const SizedBox(width: 6),
                  Expanded(child: SelectableText(a, style: const TextStyle(fontSize: 15))),
                ]))).toList());
      case QuestionType.shortAnswer:
        return SelectableText(q.answer.toString(), style: const TextStyle(fontSize: 15, height: 1.5));
    }
  }

  Widget _detailStatItem(String label, String value, Color color) {
    return Expanded(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    ));
  }

  // メモ編集ウィジェット —— 問題詳細・解答履歴履歴画面共通
  Widget _memoEditWidget(Question q, {required Function(Question) onSaved}) {
    final ctrl = TextEditingController(text: q.memo ?? '');
    return StatefulBuilder(
      builder: (ctx, setW) {
        bool saving = false;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'メモを入力…',
              filled: true,
              fillColor: Colors.amber.shade50,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.amber.shade300)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.amber.shade300)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.amber.shade600, width: 2)),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: saving ? null : () async {
                setW(() => saving = true);
                final newMemo = ctrl.text.trim();
                final updated = newMemo.isEmpty
                    ? q.copyWith(clearMemo: true)
                    : q.copyWith(memo: newMemo);
                await _questionService.updateQuestion(updated);
                onSaved(updated);
              },
              icon: const Icon(Icons.save, size: 16),
              label: Text(saving ? '保存中…' : 'メモを保存'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13)),
            ),
          ),
        ]);
      },
    );
  }

  Widget _typeMini(QuestionType? type) {
    if (type == null) return const SizedBox.shrink();
    final colors = {
      QuestionType.trueFalse: Colors.purple, QuestionType.singleChoice: Colors.blue,
      QuestionType.multipleChoice: Colors.teal, QuestionType.shortAnswer: Colors.orange,
    };
    final labels = {
      QuestionType.trueFalse: '○×', QuestionType.singleChoice: '単',
      QuestionType.multipleChoice: '複', QuestionType.shortAnswer: '記',
    };
    final color = colors[type]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
      child: Text(labels[type]!, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _pagination() {
    final f        = _filtered;
    final startItem = f.isEmpty ? 0 : (_currentPage - 1) * _perPage + 1;
    final endItem   = ((_currentPage * _perPage).clamp(0, f.length));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _pBtn('‹', _currentPage > 1 ? () => setState(() => _currentPage--) : null),
        const SizedBox(width: 4),
        Text(f.isEmpty ? '0件' : '$startItem〜$endItem / ${f.length}件',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(width: 8),
        Text('$_currentPage / $_totalPages ページ',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        _pBtn('›', _currentPage < _totalPages ? () => setState(() => _currentPage++) : null),
      ]),
    );
  }

  Widget _pBtn(String label, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(label, style: TextStyle(fontSize: 22,
            color: onTap == null ? Colors.grey.shade300 : Colors.grey.shade600))),
  );

  Future<void> _showDateFilter() async {
    DateTime? tempFrom = _dateFrom;
    DateTime? tempTo   = _dateTo;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('日付フィルター'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('開始日', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _datePicker(ctx, tempFrom, (d) => setD(() => tempFrom = d), () => setD(() => tempFrom = null)),
            const SizedBox(height: 12),
            const Text('終了日', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _datePicker(ctx, tempTo, (d) => setD(() => tempTo = d), () => setD(() => tempTo = null)),
          ]),
          actions: [
            TextButton(onPressed: () { setState(() { _dateFrom = null; _dateTo = null; }); Navigator.pop(ctx); }, child: const Text('クリア')),
            ElevatedButton(
              onPressed: () { setState(() { _dateFrom = tempFrom; _dateTo = tempTo; _currentPage = 1; }); Navigator.pop(ctx); },
              child: const Text('適用'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _datePicker(BuildContext ctx, DateTime? value,
      Function(DateTime) onPick, VoidCallback onClear) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(context: ctx,
            initialDate: value ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          const Icon(Icons.calendar_today, size: 16, color: Colors.grey), const SizedBox(width: 8),
          Text(value != null ? _fmtDate(value) : '指定なし',
              style: TextStyle(color: value != null ? Colors.black : Colors.grey)),
          const Spacer(),
          if (value != null) GestureDetector(onTap: onClear, child: const Icon(Icons.close, size: 16, color: Colors.grey)),
        ]),
      ),
    );
  }

  String _dateRangeLabel() {
    if (_dateFrom != null && _dateTo != null) return '${_fmtDate(_dateFrom!)}〜${_fmtDate(_dateTo!)}';
    if (_dateFrom != null) return '${_fmtDate(_dateFrom!)}〜';
    if (_dateTo != null)   return '〜${_fmtDate(_dateTo!)}';
    return '';
  }

  String _truncate(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;
  String _fmt(DateTime dt) =>
      '${dt.year}/${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')}\n'
      '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  String _fmtDate(DateTime dt) =>
      '${dt.year}/${dt.month.toString().padLeft(2,'0')}/${dt.day.toString().padLeft(2,'0')}';
}
