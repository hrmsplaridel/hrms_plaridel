import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/forms/models/form_print_template.dart';

class FormPrintTemplateRepo {
  FormPrintTemplateRepo._();
  static final FormPrintTemplateRepo instance = FormPrintTemplateRepo._();

  static const _prefix = '/api/form-print-templates';

  Future<List<FormPrintTemplate>> list({String? module}) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      _prefix,
      queryParameters: {
        if (module != null && module.isNotEmpty) 'module': module,
      },
    );
    final raw = res.data?['templates'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => FormPrintTemplate.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<FormPrintTemplate> save({
    required String module,
    required String formKey,
    required String paperSize,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final res = await ApiClient.instance.uploadBytes<Map<String, dynamic>>(
      _prefix,
      bytes: bytes,
      fileName: fileName,
      extraFields: {
        'module': module,
        'form_key': formKey,
        'paper_size': paperSize,
      },
    );
    return FormPrintTemplate.fromJson(res.data ?? const {});
  }

  Future<FormPrintTemplate?> getMeta({
    required String module,
    required String formKey,
  }) async {
    try {
      final res = await ApiClient.instance.get<Map<String, dynamic>>(
        '$_prefix/$module/$formKey',
      );
      final data = res.data;
      if (data == null) return null;
      return FormPrintTemplate.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Uint8List?> fetchFileBytes({
    required String module,
    required String formKey,
  }) async {
    try {
      final res = await ApiClient.instance.dio.get<List<int>>(
        '$_prefix/$module/$formKey/file',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {Headers.acceptHeader: '*/*'},
        ),
      );
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> delete({
    required String module,
    required String formKey,
  }) async {
    await ApiClient.instance.delete('$_prefix/$module/$formKey');
  }
}
