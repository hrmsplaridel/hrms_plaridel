import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Page title for an RSP or L&D form, with Add / Refresh / View Records
/// beside the title. On a narrow width the actions wrap under the title.
class RspLdFormHeader extends StatelessWidget {
  const RspLdFormHeader({
    super.key,
    this.module,
    required this.title,
    this.subtitle,
    required this.actions,
  });

  final String? module;
  final String title;
  final String? subtitle;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final primary = AppTheme.dashTextPrimaryOf(context);

    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: primary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(color: secondary, fontSize: 14, height: 1.35),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (module != null && module!.trim().isNotEmpty) ...[
          Row(
            children: [
              Text(
                module!,
                style: TextStyle(
                  color: secondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: secondary),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 980;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titles,
                  const SizedBox(height: 12),
                  actions,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: titles),
                const SizedBox(width: 16),
                Flexible(
                  flex: 6,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: actions,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
