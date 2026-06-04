import 'package:flutter/material.dart';

class EmployeeLocatorMobileRequestList extends StatelessWidget {
  const EmployeeLocatorMobileRequestList({
    super.key,
    required this.children,
    required this.maxHeight,
    required this.useScrollableList,
  });

  final List<Widget> children;
  final double maxHeight;
  final bool useScrollableList;

  @override
  Widget build(BuildContext context) {
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
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
