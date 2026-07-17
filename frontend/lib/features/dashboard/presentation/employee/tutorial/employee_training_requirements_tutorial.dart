import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeTrainingRequirementsTutorial {
  EmployeeTrainingRequirementsTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required GlobalKey headerKey,
    required GlobalKey programKey,
    required GlobalKey preTrainingKey,
    required GlobalKey postTrainingKey,
  }) => [
    EmployeeTutorialTarget(
      key: headerKey,
      title: 'Training Requirements',
      body:
          'Follow your pre-training and post-training document progress from this page.',
    ),
    EmployeeTutorialTarget(
      key: programKey,
      title: 'Identify the training program',
      body:
          'Enter and save the training or program title so the uploaded documents are easy to identify.',
    ),
    EmployeeTutorialTarget(
      key: preTrainingKey,
      title: 'Complete pre-training requirements',
      body:
          'Upload the required invitation letter and wait for HR approval before proceeding.',
    ),
    EmployeeTutorialTarget(
      key: postTrainingKey,
      title: 'Complete post-training requirements',
      body:
          'After training and pre-approval, upload the Learning Application Plan and training certificate.',
    ),
  ];
}
