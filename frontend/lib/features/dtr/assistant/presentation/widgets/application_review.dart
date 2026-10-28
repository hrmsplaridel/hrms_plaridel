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
        r'\b(review|check|validate|ready|missing|kulang|suriin|tan-awa|tanawa|i-check)\b',
        caseSensitive: false,
      ).hasMatch(text) &&
      RegExp(
        r'\b(application|aplikasyon|form|before submitting|before i submit|ready to submit)\b',
        caseSensitive: false,
      ).hasMatch(text) &&
      !RegExp(
        r'\b(status|approved|pending|reviewer|who)\b',
        caseSensitive: false,
      ).hasMatch(text);

  static String reply([String message = '']) {
    final bisaya = RegExp(
      r'\b(tan-awa|tanawa|unsa|naa|nako|ug|akong)\b',
      caseSensitive: false,
    ).hasMatch(message);
    final tagalog =
        RegExp(
          r'\b(suriin|paki|ko|ng|ano|bago)\b',
          caseSensitive: false,
        ).hasMatch(message) &&
        !bisaya;
    final review = _review;
    if (review == null) {
      return bisaya
          ? 'Ablihi ang imong leave o locator application, unya pangayo ug review aron ma-check nako ang current entries.'
          : tagalog
          ? 'Buksan ang leave o locator application mo, pagkatapos hilingin ang review para masuri ang kasalukuyang entries.'
          : 'Open your leave or locator application, then ask me to review it. I need the open form to check your current entries.';
    }
    final issues = review();
    final title = bisaya
        ? 'Review sa imong $_module application'
        : tagalog
        ? 'Pagsusuri ng $_module application mo'
        : 'Review of your $_module application';
    final details = issues.isEmpty
        ? (bisaya
              ? 'Walay nakitang issue sa current form checks.'
              : tagalog
              ? 'Walang nakitang problema sa kasalukuyang form checks.'
              : 'No issues found by the current form checks.')
        : '${bisaya
              ? 'Palihug ayuha kini'
              : tagalog
              ? 'Pakiayos ang mga ito'
              : 'Please address these items'}:\n${issues.map((issue) => '- ${issue.message}').join('\n')}';
    final reminder = bisaya
        ? 'Wala pay na-submit. Ang final eligibility, availability ug approval checks buhaton gihapon sa pag-submit.'
        : tagalog
        ? 'Wala pang naisumite. Susuriin pa rin ang final eligibility, availability at approval kapag nagsumite.'
        : 'Nothing has been submitted. Final eligibility, availability, and approval checks still apply when you submit.';
    return '$title\n\n$details\n\n$reminder';
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
        (field) =>
            ApplicationReviewIssue(_fieldError(field), target: field.context),
      )
      .toList();
}

String _fieldError(FormFieldState<dynamic> field) {
  String? label;
  void inspect(Element element) {
    final widget = element.widget;
    if (widget is InputDecorator) {
      label ??= widget.decoration.labelText ?? widget.decoration.hintText;
    }
    element.visitChildren(inspect);
  }

  field.context.visitChildElements(inspect);
  final error = field.errorText ?? 'Check this field.';
  return label == null ||
          label!.trim().isEmpty ||
          error.toLowerCase().contains(label!.toLowerCase())
      ? error
      : '${label!.trim()}: $error';
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
