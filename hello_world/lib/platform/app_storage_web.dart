// Web 実装：localStorage をバックエンドとして使用
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'app_storage.dart';

class _WebStorage extends AppStorage {
  static const _prefix = 'elearning_';

  @override
  Future<String> get baseDirPath async => ''; // Web に概念なし

  @override
  Future<String?> read(String key) async {
    return html.window.localStorage['$_prefix$key'];
  }

  @override
  Future<void> write(String key, String value) async {
    html.window.localStorage['$_prefix$key'] = value;
  }

  @override
  Future<void> delete(String key) async {
    html.window.localStorage.remove('$_prefix$key');
  }
}

// ignore: library_private_types_in_public_api
final AppStorage storageInstance = _WebStorage();
