import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/screens/legal_page.dart';

/// Compact legal links shared by portal footers, with keyboard-accessible buttons.
class PortalLegalFooter extends StatelessWidget {
  const PortalLegalFooter({
    super.key,
    this.year,
    this.stacked = false,
    this.fontSize = 11,
    this.textColor,
    this.linkColor,
  });

  final int? year;
  final bool stacked;
  final double fontSize;
  final Color? textColor;
  final Color? linkColor;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: textColor ?? AppTheme.dashTextSecondaryOf(context),
      fontSize: fontSize,
      height: 1.4,
    );
    final copyright = Text(
      '© ${year ?? DateTime.now().year} Unity Pillar',
      textAlign: TextAlign.center,
      style: textStyle,
    );
    Widget link(String label, VoidCallback onPressed) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 24),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        foregroundColor: linkColor ?? Theme.of(context).colorScheme.primary,
        textStyle: textStyle.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
    final links = <Widget>[
      link('Privacy', () => LegalPage.openPrivacy(context)),
      Text('·', style: textStyle),
      link('Terms', () => LegalPage.openTerms(context)),
    ];
    Widget wrap(List<Widget> children) => Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: children,
    );
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [copyright, const SizedBox(height: 4), wrap(links)],
      );
    }
    return wrap([copyright, Text('·', style: textStyle), ...links]);
  }
}
