import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeLeaveTutorial {
  EmployeeLeaveTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required bool showHeader,
    required GlobalKey headerKey,
    required GlobalKey contentKey,
  }) => [
    if (showHeader)
      EmployeeTutorialTarget(
        key: headerKey,
        title: 'My Leave',
        body:
            'Use this module to review balances, file leave, and follow approval progress.',
      ),
    EmployeeTutorialTarget(
      key: contentKey,
      title: 'Balances and requests',
      body:
          'Check your available credits and request history here. Select File Leave to create, save, or submit a request.',
    ),
  ];
}
