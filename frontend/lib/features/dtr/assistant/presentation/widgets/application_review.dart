import 'package:flutter/material.dart';

class ApplicationReviewIssue {
  const ApplicationReviewIssue(this.message, {this.target});
  final String message;
  final BuildContext? target;
}

List<ApplicationReviewIssue> reviewFormFields(FormState? form) {
  if (form == null) {
    return [
      const ApplicationReviewIssue('The form is not ready. Please try again.'),
    ];
  }
  return form
      .validateGranularly()
      .map(
        (field) => ApplicationReviewIssue(
          field.errorText ?? 'Check this field.',
          target: field.context,
        ),
      )
      .toList();
}

Future<void> showApplicationReview(
  BuildContext context,
  List<ApplicationReviewIssue> issues,
) async {
  final selected = await showDialog<ApplicationReviewIssue>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Application review'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                issues.isEmpty
                    ? 'No issues found by the current form checks.'
                    : 'Please address these items before submitting:',
              ),
              for (final issue in issues)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(issue.message),
                  trailing: issue.target == null
                      ? null
                      : TextButton(
                          onPressed: () => Navigator.pop(dialogContext, issue),
                          child: const Text('Go to field'),
                        ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Nothing has been submitted. Final eligibility, availability, and approval checks still apply when you submit.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Back to application'),
        ),
      ],
    ),
  );
  final target = selected?.target;
  if (target != null && target.mounted) {
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      alignment: 0.2,
    );
  }
}
