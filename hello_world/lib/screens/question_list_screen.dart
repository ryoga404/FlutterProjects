import 'package:flutter/material.dart';
import '../models/question.dart';
import '../models/question_set.dart';
import '../services/question_service.dart';
import 'register_screen.dart';

class QuestionListScreen extends StatefulWidget {
  final QuestionSet set;
  const QuestionListScreen({super.key, required this.set});

  @override
  State<QuestionListScreen> createState() => _QuestionListScreenState();
}

class _QuestionListScreenState extends State<QuestionListScreen> {
  final _service = QuestionService();
  List<Question> _questions = [];
  bool _isLoading = true;
  bool _reorderMode = false;
  String _searchQuery = '';

  static const int _perPage = 10;
  int _currentPage = 1;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final questions = await _service.loadQuestionsForSet(widget.set.id);
    setState(() {
      _questions = questions; _isLoading = false;
      if (_currentPage > _totalPages) _currentPage = _totalPages;
    });
  }

  List<Question> get _searchFiltered {
    if (_searchQuery.isEmpty) return _questions;
    final q = _searchQuery.toLowerCase();
    return _questions.where((item) =>
      item.question.toLowerCase().contains(q) ||
      (item.explanation ?? '').toLowerCase().contains(q) ||
      item.tags.any((t) => t.toLowerCase().contains(q))
    ).toList();
  }

  List<Question> get _paginated {
    if (_reorderMode) return _questions;
    final filtered = _searchFiltered;
    final start = (_currentPage - 1) * _perPage;
    final end = (start + _perPage).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  int get _totalPages => (_searchFiltered.length / _perPage).ceil().clamp(1, 99999);

  Future<void> _deleteQuestion(Question q) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('問題を削除'),
        content: Text('「${q.question.length > 30 ? '${q.question.substring(0, 30)}...' : q.question}」\nを削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('削除')),
        ],
      ),
    );
    if (confirmed == true) { await _service.deleteAndRenumber(q.id, widget.set.id); _load(); }
  }

  Future<void> _editQuestion(Question q) async {
    final result = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => RegisterScreen(setId: widget.set.id, setName: widget.set.name, editingQuestion: q)));
    if (result == true) _load();
  }

  Future<void> _duplicateQuestion(Question q) async {
    await _service.duplicateQuestion(q);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('問題を複製しました')));
    _load();
  }

  Future<void> _saveReorder() async {
    await _service.reorderQuestionsForSet(widget.set.id, _questions);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('並べ替えを保存しました')));
    setState(() => _reorderMode = false);
    _load();
  }

  List<int?> get _pageItems {
    final total = _totalPages; final cur = _currentPage;
    if (total <= 6) return List.generate(total, (i) => i + 1);
    if (cur <= 4) return [1, 2, 3, 4, 5, null, total];
    if (cur >= total - 3) return [1, null, total - 4, total - 3, total - 2, total - 1, total];
    return [1, null, cur - 1, cur, cur + 1, null, total];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        title: Text('問題管理 — ${widget.set.name}'),
        bottom: _reorderMode ? null : PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() {
                _searchQuery = v.trim();
                _currentPage = 1;
              }),
              decoration: InputDecoration(
                hintText: '問題文・解説・タグを検索...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() { _searchQuery = ''; _currentPage = 1; }),
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
            TextButton(onPressed: () { setState(() => _reorderMode = false); _load(); }, child: const Text('キャンセル')),
          ] else
            IconButton(
              icon: const Icon(Icons.swap_vert), tooltip: '並べ替え',
              onPressed: _questions.isEmpty ? null : () => setState(() { _reorderMode = true; _currentPage = 1; }),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.quiz_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('問題がありません', style: TextStyle(color: Colors.grey.shade500)),
                ]))
              : Column(children: [
                  if (_reorderMode)
                    Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.orange.shade50,
                        child: Row(children: [
                          const Icon(Icons.drag_handle, color: Colors.orange, size: 18), const SizedBox(width: 8),
                          const Text('ドラッグして並べ替え', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text('${_questions.length}問', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        ]))
                  else
                    Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.grey.shade50,
                        child: Row(children: [
                          Text('${_questions.length}問登録済み', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          const Spacer(),
                          Text('${_perPage}問/ページ', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                        ])),
                  Expanded(child: _reorderMode ? _buildReorderList() : _buildNormalList()),
                  if (!_reorderMode && _totalPages > 1) _buildPaging(),
                ]),
    );
  }

  Widget _buildNormalList() {
    final items = _paginated;
    return ListView.separated(
      itemCount: items.length, separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final q = items[index];
        final globalIndex = (_currentPage - 1) * _perPage + index;
        return _questionTile(q, globalIndex + 1);
      },
    );
  }

  Widget _questionTile(Question q, int displayNo) {
    return InkWell(
      onTap: () => _editQuestion(q),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text('$displayNo',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.primary)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(q.question.length > 40 ? '${q.question.substring(0, 40)}...' : q.question,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(children: [
              _typeChip(q.type), const SizedBox(width: 6),
              Text('${q.points}点', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              if (q.imagePath != null) ...[const SizedBox(width: 6), Icon(Icons.image, size: 13, color: Colors.grey.shade400)],
              if (q.tags.isNotEmpty) ...[
                const SizedBox(width: 6),
                ...q.tags.take(2).map((t) => Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.indigo.shade200)),
                  child: Text(t, style: TextStyle(fontSize: 9, color: Colors.indigo.shade700)),
                )),
                if (q.tags.length > 2) Text('+${q.tags.length - 2}', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
              ],
              if (q.memo != null && q.memo!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Icon(Icons.sticky_note_2_outlined, size: 13, color: Colors.amber.shade600),
              ],
            ]),
          ])),
          // 操作ボタン（複製追加）
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
            onSelected: (v) {
              if (v == 'edit') _editQuestion(q);
              else if (v == 'duplicate') _duplicateQuestion(q);
              else if (v == 'delete') _deleteQuestion(q);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, color: Colors.indigo, size: 18), SizedBox(width: 8), Text('編集')])),
              const PopupMenuItem(value: 'duplicate', child: Row(children: [Icon(Icons.copy_outlined, color: Colors.teal, size: 18), SizedBox(width: 8), Text('複製')])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 18), SizedBox(width: 8), Text('削除', style: TextStyle(color: Colors.red))])),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _buildReorderList() {
    return ReorderableListView.builder(
      itemCount: _questions.length,
      onReorder: (oldIndex, newIndex) {
        setState(() { if (newIndex > oldIndex) newIndex--; final item = _questions.removeAt(oldIndex); _questions.insert(newIndex, item); });
      },
      itemBuilder: (context, index) {
        final q = _questions[index];
        return ListTile(
          key: ValueKey(q.id),
          leading: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.drag_handle, color: Colors.grey), const SizedBox(width: 8),
            Container(width: 30, height: 30,
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
          ]),
          title: Text(q.question.length > 40 ? '${q.question.substring(0, 40)}...' : q.question, style: const TextStyle(fontSize: 14)),
          subtitle: Row(children: [_typeChip(q.type), const SizedBox(width: 6), Text('${q.points}点', style: TextStyle(fontSize: 11, color: Colors.grey.shade500))]),
        );
      },
    );
  }

  Widget _typeChip(QuestionType type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: _typeColor(type).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
      child: Text(type.label, style: TextStyle(fontSize: 10, color: _typeColor(type), fontWeight: FontWeight.bold)),
    );
  }

  Color _typeColor(QuestionType type) {
    switch (type) {
      case QuestionType.trueFalse: return Colors.teal;
      case QuestionType.singleChoice: return Colors.blue;
      case QuestionType.multipleChoice: return Colors.purple;
      case QuestionType.shortAnswer: return Colors.orange;
    }
  }

  Widget _buildPaging() {
    final pageItems = _pageItems;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _pageBtn('«', _currentPage > 1 ? () => setState(() => _currentPage = 1) : null),
          _pageBtn('‹', _currentPage > 1 ? () => setState(() => _currentPage--) : null),
          ...pageItems.map((p) => p == null
              ? const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('...', style: TextStyle(color: Colors.grey)))
              : _pageNumBtn(p)),
          _pageBtn('›', _currentPage < _totalPages ? () => setState(() => _currentPage++) : null),
          _pageBtn('»', _currentPage < _totalPages ? () => setState(() => _currentPage = _totalPages) : null),
        ]),
        Text('${(_currentPage - 1) * _perPage + 1}〜${(_currentPage * _perPage).clamp(0, _questions.length)} / ${_questions.length}件',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }

  Widget _pageBtn(String label, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(label, style: TextStyle(fontSize: 18, color: onTap == null ? Colors.grey.shade300 : Colors.grey.shade600))),
  );

  Widget _pageNumBtn(int page) {
    final isSelected = page == _currentPage;
    return GestureDetector(
      onTap: () => setState(() => _currentPage = page),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 3), width: 32, height: 32,
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300),
        ),
        child: Center(child: Text('$page', style: TextStyle(fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.grey.shade700))),
      ),
    );
  }
}
