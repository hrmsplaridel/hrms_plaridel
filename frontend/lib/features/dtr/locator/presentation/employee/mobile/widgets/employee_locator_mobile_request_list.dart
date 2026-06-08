import 'package:flutter/material.dart';

class EmployeeLocatorMobileRequestList extends StatelessWidget {
  const EmployeeLocatorMobileRequestList({
    super.key,
    required this.children,
    required this.maxHeight,
    required this.useScrollableList,
    this.gap = 12,
  });

  final List<Widget> children;
  final double maxHeight;
  final bool useScrollableList;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );

    if (!useScrollableList) return list;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        primary: false,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        child: list,
      ),
    );
  }
}
