// Web 実装：<input type="file"> でファイル選択
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';
import 'app_file_picker.dart';

class _WebFilePicker extends AppFilePicker {
  @override
  Future<PickedFile?> pickFile({
    required String label,
    required List<String> extensions,
  }) async {
    final completer = Completer<PickedFile?>();
    final accept = extensions.map((e) => '.$e').join(',');

    final input = html.FileUploadInputElement()
      ..accept = accept
      ..style.display = 'none';

    html.document.body?.append(input);
    input.click();

    input.onChange.listen((event) async {
      final files = input.files;
      if (files == null || files.isEmpty) {
        completer.complete(null);
      } else {
        final file = files[0];
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        reader.onLoad.listen((_) {
          final result = reader.result as List<int>;
          completer.complete(PickedFile(
            name: file.name,
            path: null,
            bytes: Uint8List.fromList(result),
          ));
        });
        reader.onError.listen((_) => completer.complete(null));
      }
      input.remove();
    });

    // ダイアログを閉じた場合（change が発火しない場合）のタイムアウト
    Future.delayed(const Duration(seconds: 60), () {
      if (!completer.isCompleted) completer.complete(null);
      input.remove();
    });

    return completer.future;
  }
}

final AppFilePicker filePickerInstance = _WebFilePicker();
