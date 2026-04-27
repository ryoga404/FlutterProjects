import 'package:flutter/material.dart';
import 'image_widget_native.dart'
    if (dart.library.html) 'image_widget_web.dart' as impl;

/// ローカル画像パスを受け取ってプラットフォームに応じた表示を行う。
/// Web: Image.network / memory / プレースホルダー
/// Native: Image.file
class AppImageWidget extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  const AppImageWidget({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return impl.buildImage(
      path: path,
      width: width,
      height: height,
      fit: fit,
    );
  }
}
