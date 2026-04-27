import 'dart:io';
import 'dart:typed_data';

/// Native: ローカルパスから同期的に画像バイトを読み込む
Uint8List? loadImageBytesSync(String? path) {
  if (path == null || path.isEmpty) return null;
  try {
    return File(path).readAsBytesSync();
  } catch (_) {
    return null;
  }
}
