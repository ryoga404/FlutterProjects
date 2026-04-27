import 'dart:typed_data';
import 'app_file_picker_native.dart'
    if (dart.library.html) 'app_file_picker_web.dart' as impl;

class PickedFile {
  final String name;
  final String? path; // Web では null
  final Uint8List bytes;
  const PickedFile({required this.name, this.path, required this.bytes});
}

/// ファイル選択ダイアログの抽象層。
abstract class AppFilePicker {
  /// ファイル選択ダイアログを開き、選択されたファイルを返す。
  /// キャンセルされた場合は null。
  Future<PickedFile?> pickFile({
    required String label,
    required List<String> extensions,
  });

  static AppFilePicker get instance => impl.filePickerInstance;
}
