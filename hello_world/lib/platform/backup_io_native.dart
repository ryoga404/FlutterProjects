import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../services/backup_service.dart';

// dart:io を使う Native 専用処理。
// backup_service.dart から直接参照せず、
// conditional import で Web ビルド時には除外される。

Future<Uint8List> readNativeFileBytes(String path) async {
  return File(path).readAsBytes();
}

Future<List<BackupInfo>> listNativeBackups(String baseDir) async {
  final backupDir = Directory(p.join(baseDir, 'backups'));
  if (!await backupDir.exists()) return [];

  final files = await backupDir
      .list()
      .where((e) => e is File && e.path.endsWith('.zip'))
      .cast<File>()
      .toList();
  files.sort((a, b) => b.path.compareTo(a.path));

  final result = <BackupInfo>[];
  for (final f in files) {
    final stat = await f.stat();
    result.add(BackupInfo(
      path: f.path,
      fileName: p.basename(f.path),
      size: stat.size,
      createdAt: stat.modified,
    ));
  }
  return result;
}

Future<void> deleteNativeFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
