import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question_set.dart';
import '../providers/app_settings_provider.dart';
import '../services/question_service.dart';
import '../services/history_service.dart';
import '../services/share_service.dart';
import 'register_screen.dart';
import 'exercise_menu_screen.dart';
import 'score_screen.dart';
import 'question_list_screen.dart';
import 'settings/settings_screen.dart';
import 'ml/model_training_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late QuestionService _questionService;
  late HistoryService _historyService;
  final _shareService = ShareService();

  List<QuestionSet> _sets = [];
  Map<String, int> _questionCounts = {};
  Map<String, int> _historyCounts = {};
  Map<String, int> _weakCounts = {};
  // ★ 今日の復習問題数（間隔反復スケジューラー）
  Map<String, int> _reviewCounts = {};
  bool _isLoading = true;
  bool _reorderMode = false;
  bool _didInit = false;
  String _searchQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _questionService = context.read<QuestionService>();
      _historyService  = context.read<HistoryService>();
      _didInit = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final sets   = await _questionService.loadSets();
    final setIds = sets.map((s) => s.id).toList();

    final results = await Future.wait([
      _questionService.loadQuestionCountBySet(setIds),
      _historyService.loadHistoryCountBySet(setIds),
      _questionService.loadWeakCountBySet(setIds, minAttempts: 1),
      // ★ 今日の復習問題数を取得
      _questionService.loadTodaysReviewCountBySet(setIds),
    ]);

    setState(() {
      _sets          = sets;
      _questionCounts = results[0];
      _historyCounts  = results[1];
      _weakCounts     = results[2];
      _reviewCounts   = results[3];
      _isLoading      = false;
    });
  }

  // ──────────────────────────────────────────────
  // セット新規作成
  // ──────────────────────────────────────────────
  Future<void> _addSet() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('問題セットを新規作成'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'セット名 *', border: OutlineInputBorder()),
              autofocus: true),
          const SizedBox(height: 12),
          TextField(controller: descCtrl,
              decoration: const InputDecoration(labelText: '説明（任意）', border: OutlineInputBorder()),
              maxLines: 2),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () { if (nameCtrl.text.trim().isEmpty) return; Navigator.pop(context, true); },
            child: const Text('作成'),
          ),
        ],
      ),
    );
    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      await _questionService.addSet(nameCtrl.text.trim(), descCtrl.text.trim());
      _load();
    }
  }

  // ──────────────────────────────────────────────
  // セット複製
  // ──────────────────────────────────────────────
  Future<void> _duplicateSet(QuestionSet set) async {
    final nameCtrl = TextEditingController(text: '${set.name}（コピー）');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.copy, color: Colors.indigo, size: 20), SizedBox(width: 8), Text('セットを複製'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('問題もすべてコピーされます。'),
          const SizedBox(height: 12),
          TextField(controller: nameCtrl, autofocus: true,
              decoration: const InputDecoration(labelText: '新しいセット名 *', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () { if (nameCtrl.text.trim().isEmpty) return; Navigator.pop(ctx, true); },
            child: const Text('複製'),
          ),
        ],
      ),
    );
    if (confirmed == true && nameCtrl.text.trim().isNotEmpty) {
      await _questionService.duplicateSet(set, nameCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${nameCtrl.text.trim()}」に複製しました')));
      _load();
    }
  }

  // ──────────────────────────────────────────────
  // セット情報修正（試験日も含む）
  // ──────────────────────────────────────────────
  Future<void> _editSetInfo(QuestionSet set) async {
    final nameCtrl = TextEditingController(text: set.name);
    final descCtrl = TextEditingController(text: set.description);
    DateTime? examDate = set.examDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.edit, color: Colors.indigo, size: 20), SizedBox(width: 8), Text('セット情報を修正'),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, autofocus: true,
                  decoration: const InputDecoration(labelText: 'セット名 *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.folder))),
              const SizedBox(height: 12),
              TextField(controller: descCtrl, maxLines: 2,
                  decoration: const InputDecoration(labelText: '説明（任意）', border: OutlineInputBorder(), prefixIcon: Icon(Icons.notes))),
              const SizedBox(height: 16),
              const Align(alignment: Alignment.centerLeft,
                  child: Text('試験日', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final picked = await showDatePicker(context: ctx,
                      initialDate: examDate ?? DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)));
                  if (picked != null) setD(() => examDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: examDate != null ? Colors.indigo : Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                    color: examDate != null ? Colors.indigo.withOpacity(0.05) : null,
                  ),
                  child: Row(children: [
                    Icon(Icons.event, size: 18, color: examDate != null ? Colors.indigo : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      examDate != null
                          ? '${examDate!.year}/${examDate!.month.toString().padLeft(2,'0')}/${examDate!.day.toString().padLeft(2,'0')}'
                          : '試験日を設定（任意）',
                      style: TextStyle(color: examDate != null ? Colors.indigo : Colors.grey,
                          fontWeight: examDate != null ? FontWeight.bold : FontWeight.normal),
                    )),
                    if (examDate != null)
                      GestureDetector(onTap: () => setD(() => examDate = null),
                          child: const Icon(Icons.close, size: 16, color: Colors.grey)),
                  ]),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final updated = set.copyWith(
                    name: nameCtrl.text.trim(), description: descCtrl.text.trim(),
                    examDate: examDate, clearExamDate: examDate == null);
                await _questionService.updateSet(updated);
                if (!mounted) return;
                Navigator.pop(ctx);
                _load();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSet(QuestionSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('セットを削除'),
        content: Text('「${set.name}」とその問題・解答履歴をすべて削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('削除')),
        ],
      ),
    );
    if (confirmed == true) { await _questionService.deleteSet(set.id); _load(); }
  }

  Future<void> _resetHistory(QuestionSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解答履歴をリセット'),
        content: Text('「${set.name}」の解答履歴をすべて削除しますか？\n問題は残ります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: const Text('リセット')),
        ],
      ),
    );
    if (confirmed == true) {
      await _historyService.deleteHistoryForSet(set.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${set.name}」の履歴をリセットしました')));
      _load();
    }
  }

  Future<void> _exportSet(QuestionSet set) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.download, color: Colors.indigo), SizedBox(width: 8), Text('エクスポート')]),
        content: const Text('問題セットをファイルとして書き出します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          OutlinedButton.icon(
            icon: const Icon(Icons.table_chart_outlined), label: const Text('CSV'),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final path = await _questionService.exportSetToCsv(set);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('CSV出力: $path'), duration: const Duration(seconds: 4)));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('CSV出力失敗: $e'), backgroundColor: Colors.red));
              }
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.code), label: const Text('JSON共有'),
            onPressed: () async { Navigator.pop(ctx); await _shareService.shareSetAsJson(context, set); },
          ),
        ],
      ),
    );
  }

  Future<void> _saveReorder() async {
    await _questionService.reorderSets(_sets);
    setState(() => _reorderMode = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('並び替えを保存しました')));
  }

  // ──────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        title: const Row(children: [
          Icon(Icons.school, size: 28), SizedBox(width: 8),
          Text('試験対策アプリ', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        bottom: _reorderMode ? null : PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: 'セットを検索...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ),
        ),
        actions: [
          if (_reorderMode) ...[
            TextButton.icon(icon: const Icon(Icons.save), label: const Text('保存'), onPressed: _saveReorder),
            TextButton(
                onPressed: () { setState(() => _reorderMode = false); _load(); },
                child: const Text('キャンセル')),
          ] else ...[
            IconButton(
              icon: Icon(settings.isDark ? Icons.light_mode : Icons.dark_mode),
              tooltip: settings.isDark ? 'ライトモード' : 'ダークモード',
              onPressed: () => settings.toggleTheme(),
            ),
            IconButton(
              icon: const Icon(Icons.file_download), tooltip: 'セットをインポート',
              onPressed: () => _shareService.showImportDialog(context, _load),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '設定',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sets.isEmpty
              ? _emptyState()
              : Column(children: [
                  if (_reorderMode)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.orange.shade50,
                      child: const Row(children: [
                        Icon(Icons.swap_vert, color: Colors.orange, size: 18), SizedBox(width: 8),
                        Text('矢印を押して並び替え',
                            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  Expanded(
                    child: _reorderMode
                        ? _buildReorderList()
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final cols = constraints.maxWidth >= 520 ? 3
                                           : constraints.maxWidth >= 300 ? 2
                                           : 1;
                                final cardWidth =
                                    (constraints.maxWidth - 12 * 2 - 10 * (cols - 1)) / cols;
                                return SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(12),
                                  child: _sets.where((s) =>
                                  _searchQuery.isEmpty ||
                                  s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                                  s.description.toLowerCase().contains(_searchQuery.toLowerCase())
                                  ).isEmpty
                                    ? Padding(
                                          padding: const EdgeInsets.only(top: 60),
                          child: Center(
                            child: Text('「$_searchQuery」に一致するセットがありません',
                                style: TextStyle(color: Colors.grey.shade500)),
                          ),
                        )
                      : Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _sets.where((s) =>
                            _searchQuery.isEmpty ||
                            s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            s.description.toLowerCase().contains(_searchQuery.toLowerCase())
                          ).map((s) =>
                            SizedBox(width: cardWidth, child: _setCard(s))
                          ).toList(),
                        ),
                                );
                              },
                            ),
                          ),
                  ),
                ]),
      floatingActionButton: _reorderMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _addSet, icon: const Icon(Icons.add), label: const Text('問題セット追加')),
    );
  }

  Widget _buildReorderList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 520 ? 3
                   : constraints.maxWidth >= 300 ? 2
                   : 1;
        final cardWidth = (constraints.maxWidth - 12 * 2 - 10 * (cols - 1)) / cols;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(_sets.length, (index) {
              final set = _sets[index];
              final qCount = _questionCounts[set.id] ?? 0;
              final isFirst = index == 0;
              final isLast  = index == _sets.length - 1;
              return SizedBox(
                key: ValueKey(set.id),
                width: cardWidth,
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.orange.shade300, width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: Colors.orange.shade400,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Center(
                                child: Text('${index + 1}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(set.name,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      height: 1.3),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        if (set.description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(set.description,
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 5),
                        _badge(Icons.quiz, '$qCount問', Colors.blue),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: _reorderBtn(
                              icon: Icons.keyboard_arrow_up_rounded,
                              enabled: !isFirst,
                              onTap: () => setState(() {
                                final item = _sets.removeAt(index);
                                _sets.insert(index - 1, item);
                              }),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _reorderBtn(
                              icon: Icons.keyboard_arrow_down_rounded,
                              enabled: !isLast,
                              onTap: () => setState(() {
                                final item = _sets.removeAt(index);
                                _sets.insert(index + 1, item);
                              }),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _reorderBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: enabled ? Colors.orange.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled ? Colors.orange.shade300 : Colors.grey.shade300,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? Colors.orange.shade700 : Colors.grey.shade400,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.library_books_outlined, size: 80, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      Text('問題セットがありません', style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
      const SizedBox(height: 8),
      Text('右下の「＋」ボタンからセットを作成してください',
          style: TextStyle(color: Colors.grey.shade400)),
      const SizedBox(height: 24),
      OutlinedButton.icon(
          onPressed: () => _shareService.showImportDialog(context, _load),
          icon: const Icon(Icons.file_download), label: const Text('JSONからインポート')),
    ]));
  }

  Widget _setCard(QuestionSet set) {
    final qCount = _questionCounts[set.id] ?? 0;
    final hCount = _historyCounts[set.id] ?? 0;
    final wCount = _weakCounts[set.id] ?? 0;
    // ★ 今日の復習問題数
    final rCount = _reviewCounts[set.id] ?? 0;
    final days   = set.daysUntilExam;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          // ── ヘッダー行：セット名 ＋ メニュー ──
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(set.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, height: 1.3),
                maxLines: 2, overflow: TextOverflow.ellipsis)),
            SizedBox(
              width: 28, height: 28,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                onSelected: (v) {
                  switch (v) {
                    case 'edit_info':  _editSetInfo(set); break;
                    case 'duplicate':  _duplicateSet(set); break;
                    case 'manage':
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => QuestionListScreen(set: set)))
                          .then((_) => _load());
                      break;
                    case 'export':        _exportSet(set); break;
                    // ★ 並び替えはメニューからのみ（長押し廃止）
                    case 'reorder':       setState(() => _reorderMode = true); break;
                    case 'reset_history': _resetHistory(set); break;
                    case 'delete':        _deleteSet(set); break;
                  }
                },
                itemBuilder: (_) => [
                  // ★ 「試験日を登録」メニュー項目を削除
                  //    試験日は「セット情報を修正」ダイアログ内で設定可能
                  const PopupMenuItem(value: 'edit_info', child: Row(children: [
                    Icon(Icons.edit, color: Colors.indigo, size: 18), SizedBox(width: 8), Text('セット情報を修正')])),
                  const PopupMenuItem(value: 'duplicate', child: Row(children: [
                    Icon(Icons.copy, color: Colors.teal, size: 18), SizedBox(width: 8), Text('セットを複製')])),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'manage', child: Row(children: [
                    Icon(Icons.edit_note, color: Colors.indigo, size: 18), SizedBox(width: 8), Text('問題管理')])),
                  const PopupMenuItem(value: 'export', child: Row(children: [
                    Icon(Icons.ios_share, color: Colors.teal, size: 18), SizedBox(width: 8), Text('エクスポート / 共有')])),
                  const PopupMenuItem(value: 'reorder', child: Row(children: [
                    Icon(Icons.swap_vert, color: Colors.orange, size: 18), SizedBox(width: 8), Text('セットを並び替え')])),
                  const PopupMenuItem(value: 'reset_history', child: Row(children: [
                    Icon(Icons.replay, color: Colors.orange, size: 18), SizedBox(width: 8),
                    Text('解答履歴をリセット', style: TextStyle(color: Colors.orange))])),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'delete', child: Row(children: [
                    Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8),
                    Text('削除', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ),
          ]),
          if (set.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(set.description,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (days != null) ...[const SizedBox(height: 6), _examDateBadge(set, days)],
          const SizedBox(height: 6),
          // ── バッジ行 ──
          Wrap(spacing: 4, runSpacing: 4, children: [
            _badge(Icons.quiz, '$qCount問', Colors.blue),
            _badge(Icons.history, '$hCount回答', Colors.orange),
            if (wCount > 0 && hCount > 0)
              _badge(Icons.warning_amber_rounded, '苦手$wCount', Colors.red),
            // ★ 今日の復習バッジ（タップで即演習開始）
            if (rCount > 0)
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ExerciseMenuScreen(set: set, startTodaysReview: true),
                )).then((_) => _load()),
                child: _badge(Icons.schedule, '今日の復習 $rCount問', Colors.teal),
              ),
          ]),
          const SizedBox(height: 8),
          // ── アクションボタン群 ──
          _actionButton(
            icon: Icons.edit,
            label: '問題登録',
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) =>
                    RegisterScreen(setId: set.id, setName: set.name)))
                .then((_) => _load()),
          ),
          const SizedBox(height: 4),
          _actionButton(
            icon: Icons.play_arrow,
            label: '演習',
            color: Colors.green.shade700,
            onPressed: qCount == 0 ? null : () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ExerciseMenuScreen(set: set)))
                .then((_) => _load()),
          ),
          const SizedBox(height: 4),
          _actionButton(
            icon: Icons.bar_chart,
            label: '成績',
            color: Colors.purple.shade600,
            onPressed: hCount == 0 ? null : () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ScoreScreen(set: set)))
                .then((_) => _load()),
          ),
          const SizedBox(height: 4),
          _actionButton(
            icon: Icons.smart_toy,
            label: 'AI学習',
            color: Colors.indigo.shade600,
            onPressed: hCount == 0 ? null : () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ModelTrainingScreen(questionSet: set)))
                .then((_) => _load()),
          ),
        ]),
      ),
    );
  }

  Widget _examDateBadge(QuestionSet set, int days) {
    final Color color;
    final String label;
    final IconData icon;
    if (days > 30)      { color = Colors.green;  label = 'あと $days 日';      icon = Icons.event_available; }
    else if (days > 7)  { color = Colors.orange; label = 'あと $days 日';      icon = Icons.event; }
    else if (days > 0)  { color = Colors.red;    label = '⚠ あと $days 日！'; icon = Icons.event_busy; }
    else if (days == 0) { color = Colors.red;    label = '🎯 今日が試験日！'; icon = Icons.flag; }
    else                { color = Colors.grey;   label = '試験終了（${(-days)}日前）'; icon = Icons.event_note; }

    final examDateStr = set.examDate != null
        ? '${set.examDate!.year}/${set.examDate!.month.toString().padLeft(2,'0')}/${set.examDate!.day.toString().padLeft(2,'0')}'
        : '';
    return GestureDetector(
      // ★ タップで「セット情報を修正」に統合（試験日もそこで変更可能）
      onTap: () => _editSetInfo(set),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color), const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 6),
          Text('($examDateStr)', style: TextStyle(color: color.withOpacity(0.7), fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color), const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 32,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          side: BorderSide(
            color: onPressed == null
                ? Colors.grey.shade300
                : color.withOpacity(0.6),
          ),
          foregroundColor: onPressed == null ? Colors.grey.shade400 : color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
