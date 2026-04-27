import 'dart:io';
import 'package:flutter/material.dart';

Widget buildImage({
  required String path,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  return Image.file(
    File(path),
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, __, ___) => _placeholder(width, height),
  );
}

Widget _placeholder(double? width, double? height) {
  return Container(
    width: width,
    height: height ?? 150,
    color: Colors.grey.shade200,
    child: const Icon(Icons.broken_image, color: Colors.grey),
  );
}
