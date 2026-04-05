import 'dart:io';

import 'package:flutter/material.dart';

Widget buildMicroscopeChatImage(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        '(Brak pliku zdjęcia)',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
    );
  }
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        f,
        width: 260,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image_outlined),
      ),
    ),
  );
}
