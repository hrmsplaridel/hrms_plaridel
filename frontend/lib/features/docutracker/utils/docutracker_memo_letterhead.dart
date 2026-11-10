import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';

Uint8List? _cachedMemoLetterhead;

/// Official memorandum header and footer. The database copy is installed by
/// migration so a merged database keeps this artwork. The bundled PNG is only
/// the fallback when that row is not reachable.
Future<Uint8List?> loadDocuTrackerMemoLetterheadPng() async {
  final cached = _cachedMemoLetterhead;
  if (cached != null && cached.isNotEmpty) return cached;
  final remote = await _loadRemoteLetterhead();
  if (remote != null && remote.isNotEmpty) {
    return _cachedMemoLetterhead = remote;
  }
  final asset = await _loadAssetLetterhead();
  if (asset != null && asset.isNotEmpty) {
    return _cachedMemoLetterhead = asset;
  }
  return null;
}

Future<Uint8List?> _loadRemoteLetterhead() async {
  final Dio dio;
  try {
    dio = ApiClient.instance.dio;
  } catch (_) {
    return null;
  }
  try {
    final response = await dio.get<List<int>>(
      '/api/docutracker/print/letterheads/memo',
      options: Options(
        responseType: ResponseType.bytes,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final data = response.data;
    if (data == null || data.isEmpty) return null;
    return Uint8List.fromList(data);
  } catch (_) {
    return null;
  }
}

/// One A4 page of the official letterhead, for the printed-form preview.
Future<Uint8List> docuTrackerLetterheadPagePdf(Uint8List png) async {
  final doc = pw.Document();
  final image = pw.MemoryImage(png);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
    ),
  );
  return doc.save();
}

Future<Uint8List?> _loadAssetLetterhead() async {
  try {
    final data = await rootBundle.load(DocuTrackerMemoLayout.letterheadAsset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}
