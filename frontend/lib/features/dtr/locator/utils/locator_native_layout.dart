import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/locator_print_layout.dart';
import '../models/locator_request_type.dart';
import 'locator_form_signatories.dart';
import 'locator_layout_pdf.dart';
import 'locator_slip_print.dart';

/// Keeps the existing form's border, headings and logo while exposing the
/// variable fields and signatories to the same editor as saved custom layouts.
class LocatorNativeLayoutCapture {
  LocatorNativeLayoutCapture({this.layout});
  final LocatorPrintLayout? layout;
  final elements = <String, LocatorPrintElement>{};
  List<pw.Widget> overlays = [];

  pw.Widget slot(
    String source,
    pw.Widget child, {
    bool signature = false,
    String? caption,
  }) => _LocatorNativeSlot(
    this,
    source,
    signature ? pw.SizedBox(width: double.infinity, height: 80) : child,
    signature,
    caption,
  );

  pw.Widget page(pw.Widget native) {
    final current = layout;
    if (current == null) return native;
    final box =
        current.baseFormBox ??
        {'x': 0.0, 'y': 0.0, 'width': 841.89, 'height': 595.28};
    return pw.SizedBox(
      width: current.pageWidth,
      height: current.pageHeight,
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
                  width: 841.89,
                  height: 595.28,
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
    elements[source] = LocatorPrintElement(
      id: 'native_$source',
      kind: signature ? 'signature' : 'field',
      source: source,
      label: signature && source != 'hr_approver' ? caption ?? '' : '',
      x: global.left,
      y: context.page.pageFormat.height - global.top,
      width: math.max(signature ? 100 : 20, global.width),
      height: math.max(signature ? 60 : 20, global.height),
      fontSize: 12,
      showLabel: false,
      align: signature || source == 'time_segments' ? 'center' : 'left',
    );
  }
}

class _LocatorNativeSlot extends pw.SingleChildWidget {
  _LocatorNativeSlot(
    this.capture,
    this.source,
    pw.Widget child,
    this.signature,
    this.caption,
  ) : super(child: child);
  final LocatorNativeLayoutCapture capture;
  final String source;
  final bool signature;
  final String? caption;
  @override
  void paint(pw.Context context) {
    super.paint(context);
    // Leave these slots empty on the native background; the editable elements
    // supply their content once, including after a move or resize.
    capture.record(context, box!, source, signature, caption);
  }
}

Future<pw.Document> _nativeDocument(
  Map<String, dynamic> form,
  LocatorFormSignatories signatories,
  LocatorNativeLayoutCapture capture,
) => LocatorSlipPrint.buildNativeDocument(
  employeeName: form['employee_name']?.toString() ?? '',
  dateText: form['slip_date']?.toString() ?? '',
  requestTypeLabel: form['request_type_label']?.toString() ?? '',
  locationLabel: form['location_label']?.toString() ?? 'Office / Destination',
  office: form['office']?.toString() ?? '',
  remarks: form['reason']?.toString() ?? '',
  amIn: form['am_in'] == true,
  amOut: form['am_out'] == true,
  pmIn: form['pm_in'] == true,
  pmOut: form['pm_out'] == true,
  signatories: signatories,
  capture: capture,
);

Future<({LocatorPrintLayout layout, Uint8List background})>
importLocatorNativeLayout(LocatorRequestType type) async {
  final capture = LocatorNativeLayoutCapture();
  final form = {
    ...locatorLayoutSample(type),
    'location_label': type.locationLabel,
  };
  final doc = await _nativeDocument(
    form,
    LocatorFormSignatories(form: form),
    capture,
  );
  final background = await doc.save();
  final layout = LocatorPrintLayout(
    orientation: 'landscape',
    baseForm: 'locator',
    baseFormBox: const {'x': 0, 'y': 0, 'width': 841.89, 'height': 595.28},
    elements: capture.elements.values.toList(),
  );
  final error = layout.validate();
  if (error != null) throw FormatException(error);
  return (layout: layout, background: background);
}

Future<Uint8List> buildLocatorNativeLayoutPdf({
  required LocatorPrintLayout layout,
  required Map<String, dynamic> form,
  required LocatorFormSignatories signatories,
}) async {
  final capture = LocatorNativeLayoutCapture(layout: layout);
  final doc = await _nativeDocument(form, signatories, capture);
  return buildLocatorLayoutPdf(
    layout: layout,
    form: form,
    signatories: signatories,
    document: doc,
    onMainPageWidgets: (widgets) => capture.overlays = widgets,
  );
}

Future<Uint8List> locatorNativeLayoutBackground(
  LocatorRequestType type,
  LocatorPrintLayout layout,
) async {
  final form = {
    ...locatorLayoutSample(type),
    'location_label': type.locationLabel,
  };
  final doc = await _nativeDocument(
    form,
    LocatorFormSignatories(form: form),
    LocatorNativeLayoutCapture(layout: layout),
  );
  return doc.save();
}

/// Uses exactly the same fit and header/footer reservation as the server's
/// built-in-form/letterhead merge, so conversion does not move existing slots.
LocatorPrintLayout locatorNativeLayoutOnBackground(
  LocatorPrintLayout layout,
  double width,
  double height,
) {
  final scale = math.min(
    (width - 64) / layout.pageWidth,
    (height - 220) / layout.pageHeight,
  );
  final x = (width - layout.pageWidth * scale) / 2;
  final y = (height - layout.pageHeight * scale) / 2;
  return layout.copyWith(
    orientation: width > height ? 'landscape' : 'portrait',
    paperSize: printPaperFromAspect(width, height),
    baseFormBox: {
      'x': x,
      'y': y,
      'width': layout.pageWidth * scale,
      'height': layout.pageHeight * scale,
    },
    elements: [
      for (final item in layout.elements)
        item.copyWith(
          x: x + item.x * scale,
          y: y + item.y * scale,
          width: math.max(
            item.kind == 'signature' ? 100 : 20,
            item.width * scale,
          ),
          height: math.max(
            item.kind == 'signature' ? 60 : 20,
            item.height * scale,
          ),
          fontSize: math.max(6, item.fontSize * scale),
        ),
    ],
  );
}
