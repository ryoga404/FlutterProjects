import 'package:flutter/material.dart';

/// Web では imagePath はローカルファイルパスではなく使えないため、
/// プレースホルダーを返す。
/// （Web で画像を使う場合は image_picker が返す XFile.readAsBytes() を
///   MemoryImage に渡す形で別途対応が必要）
Widget buildImage({
  required String path,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  // path が http/https URL であれば表示できる
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return Image.network(path, width: width, height: height, fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(width, height));
  }
  // ローカルパスは Web では表示不可 → プレースホルダー
  return _placeholder(width, height);
}

Widget _placeholder(double? width, double? height) {
  return Container(
    width: width,
    height: height ?? 150,
    color: const Color(0xFFEEEEEE),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_not_supported, color: Colors.grey, size: 32),
        SizedBox(height: 4),
        Text('画像はネイティブアプリのみ対応', style: TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    ),
  );
}
