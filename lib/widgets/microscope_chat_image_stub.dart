import 'package:flutter/material.dart';

/// Web: no local file preview.
Widget buildMicroscopeChatImage(String path) {
  return const Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Text(
      '(Podgląd zdjęcia — tylko w aplikacji desktopowej)',
      style: TextStyle(fontSize: 11, color: Colors.grey),
    ),
  );
}
