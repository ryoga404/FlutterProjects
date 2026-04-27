import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../platform/app_storage.dart';
import '../platform/app_file_saver.dart';
import '../platform/app_file_picker.dart';
import '../platform/backup_io_native.dart'
    if (dart.library.html) '../platform/backup_io_web.dart' as io;

class BackupService {
  static const _backupKeys = [
    'questions.json',
    'question_sets.json',
    'answer_history.json',
    'settings.json',
  ];

  final _storage = AppStorage.instance;
  final _saver   = AppFileSaver.instance;
  final _picker  = AppFilePicker.instance;

  // ──────────────────────────────────────────────
  // バックアップ作成
  // ──────────────────────────────────────────────
  Future<String> createBackup() async {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final zipName = 'backup_$stamp.zip';

    final archive = Archive();
    for (final key in _backupKeys) {
      final content = await _storage.read(key);
      if (content != null) {
        final bytes = utf8.encode(content);
        archive.addFile(ArchiveFile(key, bytes.length, bytes));
      }
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw Exception('zip エンコード失敗');

    if (kIsWeb) {
      await _saver.save(bytes: Uint8List.fromList(zipBytes), fileName: zipName);
      return zipName;
    } else {
      final baseDir = await _storage.baseDirPath;
      return _saver.save(
        bytes: Uint8List.fromList(zipBytes),
        fileName: zipName,
        directory: '$baseDir/backups',
      );
    }
  }

  // ──────────────────────────────────────────────
  // リストア（パス指定 — Native のみ）
  // ──────────────────────────────────────────────
  Future<RestoreResult> restoreBackup(String zipPath) async {
    if (kIsWeb) {
      return RestoreResult(
          success: false, error: 'Web ではファイル選択からリストアしてください');
    }
    try {
      final bytes = await io.readNativeFileBytes(zipPath);
      return _restoreFromBytes(bytes);
    } catch (e) {
      return RestoreResult(success: false, error: 'リストアに失敗しました: $e');
    }
  }

  /// ファイル選択ダイアログからリストア（Web / Native 共通）
  Future<RestoreResult> restoreBackupFromPicker() async {
    final file = await _picker.pickFile(
        label: 'バックアップ ZIP', extensions: ['zip']);
    if (file == null) {
      return RestoreResult(success: false, error: 'ファイルが選択されませんでした');
    }
    return _restoreFromBytes(file.bytes);
  }

  Future<RestoreResult> _restoreFromBytes(Uint8List bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final restored = <String>[];
      for (final entry in archive) {
        if (!entry.isFile) continue;
        if (!_backupKeys.contains(entry.name)) continue;
        final content = utf8.decode(entry.content as List<int>);
        await _storage.write(entry.name, content);
        restored.add(entry.name);
      }
      if (restored.isEmpty) {
        return RestoreResult(
            success: false, error: 'バックアップに有効なデータが含まれていません');
      }
      return RestoreResult(success: true, restoredFiles: restored);
    } catch (e) {
      return RestoreResult(success: false, error: 'zip 展開に失敗しました: $e');
    }
  }

  // ──────────────────────────────────────────────
  // バックアップ一覧（Native のみ、Web は []）
  // ──────────────────────────────────────────────
  Future<List<BackupInfo>> listBackups() async {
    if (kIsWeb) return [];
    try {
      final baseDir = await _storage.baseDirPath;
      return io.listNativeBackups(baseDir);
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteBackup(String path) async {
    if (kIsWeb) return;
    await io.deleteNativeFile(path);
  }
}

class RestoreResult {
  final bool success;
  final String? error;
  final List<String>? restoredFiles;
  RestoreResult({required this.success, this.error, this.restoredFiles});
}

class BackupInfo {
  final String path;
  final String fileName;
  final int size;
  final DateTime createdAt;
  BackupInfo({
    required this.path,
    required this.fileName,
    required this.size,
    required this.createdAt,
  });

  String get sizeLabel {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)}MB';
  }
}
