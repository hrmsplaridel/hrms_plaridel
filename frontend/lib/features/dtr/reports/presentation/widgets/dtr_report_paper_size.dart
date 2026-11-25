import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';

Future<PdfPageFormat?> chooseDtrReportPaperSize(BuildContext context) {
  final choices = <(String, String, PdfPageFormat)>[
    ('A4', '210 × 297 mm', PdfPageFormat.a4),
    ('Short / Letter', '8.5 × 11 in', PdfPageFormat.letter),
    (
      'Long',
      '8.5 × 13 in',
      PdfPageFormat(8.5 * PdfPageFormat.inch, 13 * PdfPageFormat.inch),
    ),
    ('Legal', '8.5 × 14 in', PdfPageFormat.legal),
  ];
  return showDialog<PdfPageFormat>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.print_rounded,
              color: AppTheme.primaryNavy,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Print setup',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  'Select the paper loaded in your printer',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
        ],
      ),
      children: [
        for (var index = 0; index < choices.length; index++)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, choices[index].$3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: index == 0
                    ? AppTheme.primaryNavy.withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(
                    alpha: index == 0 ? 0.28 : 0.1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    color: index == 0
                        ? AppTheme.primaryNavy
                        : AppTheme.dashTextSecondaryOf(dialogContext),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          choices[index].$1,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          choices[index].$2,
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(dialogContext),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ),
      ],
    ),
  );
}
