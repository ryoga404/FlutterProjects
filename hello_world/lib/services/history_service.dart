import 'dart:convert';
import '../models/answer_history.dart';
import '../platform/app_storage.dart';

class HistoryService {
  static const _fileName = 'answer_history.json';

  final _storage = AppStorage.instance;

  List<AnswerHistory>? _cache;
  DateTime? _cacheTime;
  static const _cacheTtl = Duration(seconds: 30);

  bool get _isCacheValid =>
      _cache != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _cacheTtl;

  void _invalidateCache() {
    _cache = null;
    _cacheTime = null;
  }

  Future<List<AnswerHistory>> loadHistory() async {
    if (_isCacheValid) return List.from(_cache!);
    try {
      final raw = await _storage.read(_fileName);
      if (raw == null) {
        _cache = [];
        _cacheTime = DateTime.now();
        return [];
      }
      _cache = (jsonDecode(raw) as List)
          .map((e) => AnswerHistory.fromJson(e))
          .toList();
      _cacheTime = DateTime.now();
      return List.from(_cache!);
    } catch (_) {
      return [];
    }
  }

  Future<List<AnswerHistory>> loadHistoryForSet(String setId) async {
    final all = await loadHistory();
    return all.where((h) => h.setId == setId).toList();
  }

  Future<Map<String, int>> loadHistoryCountBySet(List<String> setIds) async {
    final all    = await loadHistory();
    final counts = <String, int>{};
    for (final id in setIds) counts[id] = 0;
    for (final h in all) {
      if (counts.containsKey(h.setId)) counts[h.setId] = counts[h.setId]! + 1;
    }
    return counts;
  }

  Future<void> _writeAll(List<AnswerHistory> list) async {
    await _storage.write(
        _fileName, jsonEncode(list.map((h) => h.toJson()).toList()));
    _cache = List.from(list);
    _cacheTime = DateTime.now();
  }

  Future<void> addHistory(AnswerHistory history) async {
    final list = await loadHistory();
    list.add(history);
    await _writeAll(list);
  }

  Future<void> deleteHistoryForSet(String setId) async {
    final list     = await loadHistory();
    final filtered = list.where((h) => h.setId != setId).toList();
    await _writeAll(filtered);
  }

  Future<void> deleteAllHistory() async {
    await _writeAll([]);
  }

  Future<void> deleteHistoryForQuestion(String questionId) async {
    final list     = await loadHistory();
    final filtered = list.where((h) => h.questionId != questionId).toList();
    await _writeAll(filtered);
  }
}
