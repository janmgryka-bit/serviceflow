import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Keeps JPEG payloads within Groq base64 limits (~4 MB before encoding).
abstract final class MicroscopeCaptureService {
  static const int _groqRawBudget = 3_500_000;

  /// Re-encode / downscale so size stays under the API limit before base64.
  static Uint8List ensureJpegUnderApiLimit(Uint8List raw) {
    if (raw.length <= _groqRawBudget) return raw;
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    var image = decoded;
    for (var step = 0; step < 16; step++) {
      final quality = (82 - step * 2).clamp(45, 85);
      final out = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      if (out.length <= _groqRawBudget) return out;
      if (image.width <= 480) {
        return out.length < raw.length ? out : raw;
      }
      image = img.copyResize(image, width: (image.width * 0.8).round());
    }
    image = img.copyResize(image, width: 480);
    return Uint8List.fromList(img.encodeJpg(image, quality: 45));
  }
}
