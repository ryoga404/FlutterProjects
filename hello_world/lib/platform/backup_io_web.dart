import 'dart:typed_data';
import '../services/backup_service.dart';

// Web ビルド時に dart:io を使う Native 実装の代わりに読み込まれるスタブ。
// backup_service.dart の conditional import で選択される。

Future<Uint8List> readNativeFileBytes(String path) async {
  throw UnsupportedError('Web ではファイルパス指定でのバックアップ読み込みはできません');
}

Future<List<BackupInfo>> listNativeBackups(String baseDir) async => [];

Future<void> deleteNativeFile(String path) async {}
