import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:hrms_plaridel/shared/widgets/rsp_form_header_footer.dart';

/// Official, print-safe Municipality/HRMD background around editable content.
///
/// The frame is intentionally outside the editor so users cannot accidentally
/// delete the official header or footer. The full-page BI-form background is
/// used when available, with a programmatic header/footer fallback. Because the
/// full page is captured, the same frame appears in print and export results.
class DocuTrackerPrintablePageFrame extends StatelessWidget {
  const DocuTrackerPrintablePageFrame({
    super.key,
    required this.documentTitle,
    required this.child,
    this.letterheadImageBytes,
  });

  final String documentTitle;
  final Widget child;
  final Uint8List? letterheadImageBytes;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: letterheadImageBytes == null
          ? _ProgrammaticLetterhead(documentTitle: documentTitle, child: child)
          : ColoredBox(
              color: Colors.white,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: Image.memory(
                      letterheadImageBytes!,
                      key: const ValueKey<String>(
                        'docutracker-letterhead-background',
                      ),
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 230, 56, 117),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          documentTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFE85D04),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ProgrammaticLetterhead extends StatelessWidget {
  const _ProgrammaticLetterhead({
    required this.documentTitle,
    required this.child,
  });

  final String documentTitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 28, 36, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IgnorePointer(
              child: KeyedSubtree(
                key: const ValueKey<String>('docutracker-printable-header'),
                child: RspFormHeader(formTitle: documentTitle),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: child,
              ),
            ),
            const IgnorePointer(
              child: KeyedSubtree(
                key: ValueKey<String>('docutracker-printable-footer'),
                child: RspFormFooter(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
