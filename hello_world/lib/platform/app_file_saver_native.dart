import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_file_saver.dart';

class _NativeFileSaver extends AppFileSaver {
  @override
  Future<String> save({
    required Uint8List bytes,
    required String fileName,
    String? directory,
  }) async {
    final dir = directory != null
        ? Directory(directory)
        : Directory(p.join(
            (await getApplicationDocumentsDirectory()).path,
            'e-learning', 'exports'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(dir.path, fileName);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  @override
  Future<String> saveText({
    required String text,
    required String fileName,
    String? directory,
    String encoding = 'utf-8',
  }) async {
    final bytes = utf8.encode(text);
    return save(bytes: Uint8List.fromList(bytes), fileName: fileName, directory: directory);
  }
}

final AppFileSaver fileSaverInstance = _NativeFileSaver();
