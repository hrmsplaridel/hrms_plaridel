import 'package:flutter/material.dart';

/// The open form supplies its current validation results to the chat.
class ActiveApplicationReview {
  static Object? _owner;
  static List<ApplicationReviewIssue> Function()? _review;
  static String? _module;

  static void register(
    Object owner,
    String module,
    List<ApplicationReviewIssue> Function() review,
  ) {
    _owner = owner;
    _module = module;
    _review = review;
  }

  static void clear([Object? owner]) {
    if (owner != null && !identical(owner, _owner)) return;
    _owner = null;
    _module = null;
    _review = null;
  }

  static bool matches(String text) =>
      RegExp(
        r'\b(review|check|validate|ready|missing|kulang|suriin|i-check)\b',
        caseSensitive: false,
      ).hasMatch(text) &&
      RegExp(
        r'\b(application|form|before submitting|before i submit|ready to submit)\b',
        caseSensitive: false,
      ).hasMatch(text) &&
      !RegExp(
        r'\b(status|approved|pending|reviewer|who)\b',
        caseSensitive: false,
      ).hasMatch(text);

  static String reply() {
    final review = _review;
    if (review == null) {
      return 'Open your leave or locator application, then ask me to review it. I need the open form to check your current entries.';
    }
    final issues = review();
    final details = issues.isEmpty
        ? 'No issues found by the current form checks.'
        : 'Please address these items:\n${issues.map((issue) => '- ${issue.message}').join('\n')}';
    return 'Review of your $_module application\n\n$details\n\nNothing has been submitted. Final eligibility, availability, and approval checks still apply when you submit.';
  }
}

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
