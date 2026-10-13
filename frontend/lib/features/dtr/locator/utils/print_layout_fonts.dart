import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

final _layoutFontCache = <String, Future<(pw.Font, pw.Font)>>{};
Future<(pw.Font, pw.Font)> loadPrintLayoutFonts(String family) =>
    _layoutFontCache.putIfAbsent(family, () async {
      final name = switch (family) {
        'serif' => 'NotoSerif',
        'mono' => 'NotoSansMono',
        _ => 'NotoSans',
      };
      final folder = family == 'sans'
          ? 'assets/fonts'
          : 'assets/fonts/form-layout';
      return (
        pw.Font.ttf(await rootBundle.load('$folder/$name-Regular.ttf')),
        pw.Font.ttf(await rootBundle.load('$folder/$name-Bold.ttf')),
      );
    });
