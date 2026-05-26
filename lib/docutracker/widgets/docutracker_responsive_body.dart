import 'package:flutter/material.dart';

/// Constrains content on very wide screens but expands to fill the host area.
class DocuTrackerResponsiveBody extends StatelessWidget {
  const DocuTrackerResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = 1680,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
