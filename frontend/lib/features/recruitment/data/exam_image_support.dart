import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:hrms_plaridel/core/api/config.dart';

/// Limits enforced before upload (the API enforces the same ones).
const int kExamImageMaxBytes = 8 * 1024 * 1024;
const List<String> kExamImageExtensions = ['png', 'jpg', 'jpeg', 'webp'];

/// Public URL of an exam image from its stored relative path
/// (`exam-images/<uuid>.png`). Returns '' when [path] is empty.
String examImageUrl(String? path) {
  final p = (path ?? '').trim();
  if (p.isEmpty) return '';
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  final name = p.split('/').last;
  return '${ApiConfig.baseUrl}/api/files/exam-image/${Uri.encodeComponent(name)}';
}

String? examImagePathOrNull(Object? value) {
  final s = value?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// Per-choice image paths aligned with the options list (null = text only).
List<String?> examOptionImagesFrom(Object? raw, int optionCount) {
  final out = List<String?>.filled(optionCount, null);
  if (raw is List) {
    for (var i = 0; i < optionCount && i < raw.length; i++) {
      out[i] = examImagePathOrNull(raw[i]);
    }
  }
  return out;
}

/// True when the question or any of its choices uses an image. Such questions are
/// always scored with the saved `correct` index (never the legacy text answer key).
bool examQuestionHasImages(Map<String, dynamic> q) {
  if (examImagePathOrNull(q['question_image']) != null) return true;
  final imgs = q['option_images'];
  if (imgs is List) {
    for (final e in imgs) {
      if (examImagePathOrNull(e) != null) return true;
    }
  }
  return false;
}

/// Returns a user-facing error, or null when the image is acceptable.
Future<String?> validateExamImage({
  required Uint8List bytes,
  required String fileName,
}) async {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  if (!kExamImageExtensions.contains(ext)) {
    return 'Unsupported file type. Please use a PNG, JPG or WEBP image.';
  }
  if (bytes.isEmpty) return 'The selected image is empty.';
  if (bytes.length > kExamImageMaxBytes) {
    final mb = (kExamImageMaxBytes / (1024 * 1024)).round();
    return 'Image is too large. Maximum size is $mb MB.';
  }
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      await codec.getNextFrame();
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return 'This image could not be read. It may be corrupted.';
  }
  return null;
}
