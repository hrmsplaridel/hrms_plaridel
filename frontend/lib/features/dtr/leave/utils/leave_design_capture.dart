import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../locator/models/locator_print_layout.dart';

/// Records the native form's variable slots while leaving its printed structure
/// intact. The same native builder supplies the base when a converted form prints.
class LeaveDesignCapture {
  LeaveDesignCapture({
    required this.fields,
    this.renderingLayout,
    this.signatureStyle = 'csc',
  });
  final Map<String, String> fields;
  final LocatorPrintLayout? renderingLayout;
  final String signatureStyle;
  final elements = <String, LocatorPrintElement>{};
  List<pw.Widget> overlays = [];

  pw.Widget field(String source, pw.Widget child, {bool underline = false}) =>
      fields.containsKey(source)
      ? _Slot(this, source, child, underline: underline)
      : child;
  pw.Widget signature(String source, pw.Widget child, {String? caption}) =>
      _Slot(this, source, child, signature: true, caption: caption);

  pw.Widget page(
    pw.Widget native, {
    required double width,
    required double height,
    required double margin,
    bool wellness = false,
  }) {
    final layout = renderingLayout;
    if (layout == null) return native;
    final nativeWidth = wellness ? width - 104 : width - 2 * margin;
    final nativeHeight = wellness ? height - 230 : height - 2 * margin;
    final box =
        layout.baseFormBox ??
        {
          'x': margin,
          'y': margin,
          'width': width - 2 * margin,
          'height': height - 2 * margin,
        };
    return pw.SizedBox(
      width: layout.pageWidth,
      height: layout.pageHeight,
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: box['x']!,
            top: box['y']!,
            child: pw.SizedBox(
              width: box['width']!,
              height: box['height']!,
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.topLeft,
                child: pw.SizedBox(
                  width: nativeWidth,
                  height: nativeHeight,
                  child: native,
                ),
              ),
            ),
          ),
          ...overlays,
        ],
      ),
    );
  }

  void record(
    pw.Context context,
    PdfRect rect,
    String source,
    bool signature,
    String? caption,
  ) {
    final global = context.localToGlobal(rect);
    final paperHeight = context.page.pageFormat.height;
    final minimumHeight = signature
        ? (signatureStyle == 'csc'
              ? (source == 'applicant' ? 18.0 : 32.0)
              : 60.0)
        : 20.0;
    final h = math.max(minimumHeight, global.height);
    final y = signature
        ? paperHeight - global.bottom - h
        : paperHeight - global.top;
    elements[source] = LocatorPrintElement(
      id: 'native_$source',
      kind: signature ? 'signature' : 'field',
      source: source,
      label: signature
          ? (caption ??
                (source == 'applicant' ? '(Signature of Applicant)' : ''))
          : fields[source] ?? '',
      x: global.left,
      y: math.max(0, y),
      width: math.max(signature ? 100 : 20, global.width),
      height: h,
      fontSize: 8,
      showLabel: false,
      signatureStyle: signature ? signatureStyle : 'standard',
    );
  }
}

class _Slot extends pw.SingleChildWidget {
  _Slot(
    this.capture,
    this.source,
    pw.Widget child, {
    this.signature = false,
    this.underline = false,
    this.caption,
  }) : super(child: child);
  final LeaveDesignCapture capture;
  final String source;
  final bool signature, underline;
  final String? caption;
  @override
  void paint(pw.Context context) {
    super.paint(context);
    capture.record(context, box!, source, signature, caption);
    if (underline) {
      context.canvas
        ..setStrokeColor(PdfColors.black)
        ..setLineWidth(.8)
        ..drawLine(box!.left, box!.bottom, box!.right, box!.bottom)
        ..strokePath();
    }
  }
}
