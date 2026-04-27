import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'app_file_picker.dart';

class _NativeFilePicker extends AppFilePicker {
  @override
  Future<PickedFile?> pickFile({
    required String label,
    required List<String> extensions,
  }) async {
    // Web / macOS 以外のデスクトップでは file_selector を使用
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return null;
    }
    final group = XTypeGroup(label: label, extensions: extensions);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedFile(name: file.name, path: file.path, bytes: bytes);
  }
}

final AppFilePicker filePickerInstance = _NativeFilePicker();
