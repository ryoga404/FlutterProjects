import 'dart:typed_data';
import 'app_file_saver_native.dart'
    if (dart.library.html) 'app_file_saver_web.dart' as impl;

/// バイト列をファイルとしてユーザーに届ける抽象層。
/// Web: ブラウザの「ダウンロード」として保存
/// Native: 指定パスにファイルとして保存
abstract class AppFileSaver {
  /// [bytes] を [fileName] というファイル名で保存する。
  /// 保存先パス（またはダウンロードされたファイル名）を返す。
  Future<String> save({
    required Uint8List bytes,
    required String fileName,
    String? directory, // Native のみ有効
  });

  /// テキストデータを保存する。
  Future<String> saveText({
    required String text,
    required String fileName,
    String? directory,
    String encoding = 'utf-8',
  });

  static AppFileSaver get instance => impl.fileSaverInstance;
}
