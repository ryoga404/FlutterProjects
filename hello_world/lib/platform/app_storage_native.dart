import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_storage.dart';

class _NativeStorage extends AppStorage {
  static const _subDir = 'e-learning';

  Future<Directory> get _dir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _subDir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String> get baseDirPath async => (await _dir).path;

  @override
  Future<String?> read(String key) async {
    try {
      final file = File(p.join((await _dir).path, key));
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final file = File(p.join((await _dir).path, key));
    await file.writeAsString(value);
  }

  @override
  Future<void> delete(String key) async {
    final file = File(p.join((await _dir).path, key));
    if (await file.exists()) await file.delete();
  }
}

// ignore: library_private_types_in_public_api
final AppStorage storageInstance = _NativeStorage();
