// Web 実装：<a download> でブラウザダウンロードを起動
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:convert';
import 'app_file_saver.dart';

class _WebFileSaver extends AppFileSaver {
  @override
  Future<String> save({
    required Uint8List bytes,
    required String fileName,
    String? directory,
  }) async {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
    return fileName; // Web ではローカルパスは不明
  }

  @override
  Future<String> saveText({
    required String text,
    required String fileName,
    String? directory,
    String encoding = 'utf-8',
  }) async {
    // BOM 付き UTF-8 の場合
    List<int> bytes;
    if (encoding == 'utf-8-bom') {
      bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(text)];
    } else {
      bytes = utf8.encode(text);
    }
    return save(
        bytes: Uint8List.fromList(bytes),
        fileName: fileName);
  }
}

final AppFileSaver fileSaverInstance = _WebFileSaver();
