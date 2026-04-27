import 'package:flutter/foundation.dart' show kIsWeb;

import 'app_storage_native.dart' if (dart.library.html) 'app_storage_web.dart'
    as impl;

/// アプリデータの読み書きを抽象化するインターフェース。
/// Web では localStorage、Native ではファイルシステムを使用。
abstract class AppStorage {
  /// [key] に対応する JSON 文字列を返す。存在しない場合は null。
  Future<String?> read(String key);

  /// [key] に [value] を書き込む。
  Future<void> write(String key, String value);

  /// [key] を削除する。
  Future<void> delete(String key);

  /// アプリデータが格納されるベースディレクトリパス。
  /// Web では空文字列を返す（概念なし）。
  Future<String> get baseDirPath;

  static AppStorage get instance => impl.storageInstance;
}
