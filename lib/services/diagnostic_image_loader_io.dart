import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'microscope_capture_service.dart';

/// Linux / desktop: read JPEG and emit data URL for Groq (within size limits).
String? jpegFileToDataUrl(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    var bytes = f.readAsBytesSync();
    bytes = MicroscopeCaptureService.ensureJpegUnderApiLimit(bytes);
    final b64 = base64Encode(bytes);
    return 'data:image/jpeg;base64,$b64';
  } catch (e, st) {
    debugPrint('jpegFileToDataUrl: $e\n$st');
    return null;
  }
}
