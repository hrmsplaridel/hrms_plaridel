import 'package:flutter/material.dart';

class EmployeeLocatorMobileRequestList extends StatelessWidget {
  const EmployeeLocatorMobileRequestList({
    super.key,
    required this.children,
    required this.maxHeight,
    required this.useScrollableList,
    this.scrollController,
    this.gap = 10,
  });

  final List<Widget> children;
  final double maxHeight;
  final bool useScrollableList;
  final ScrollController? scrollController;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (!useScrollableList) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    }

    final list = ListView.separated(
      controller: scrollController,
      shrinkWrap: true,
      primary: false,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: children.length,
      separatorBuilder: (_, __) => SizedBox(height: gap),
      itemBuilder: (_, index) => children[index],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        child: list,
      ),
    );
  }
}
