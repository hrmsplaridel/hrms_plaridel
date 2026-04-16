import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/recruitment_application.dart';
import '../../data/rsp_screening_scores.dart';
import '../../landingpage/constants/app_theme.dart';

/// Admin dialog: read BEI answers, enter 0–100 per question, save into [answers_json] and recalc overall %.
Future<void> showRspBeiGradingDialog({
  required BuildContext context,
  required RecruitmentApplication applicant,
  required RecruitmentExamResult exam,
  required VoidCallback onSaved,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RspBeiGradingDialog(
      applicant: applicant,
      exam: exam,
      onSaved: onSaved,
    ),
  );
}

class _RspBeiGradingDialog extends StatefulWidget {
  const _RspBeiGradingDialog({
    required this.applicant,
    required this.exam,
    required this.onSaved,
  });

  final RecruitmentApplication applicant;
  final RecruitmentExamResult exam;
  final VoidCallback onSaved;

  @override
  State<_RspBeiGradingDialog> createState() => _RspBeiGradingDialogState();
}

class _RspBeiGradingDialogState extends State<_RspBeiGradingDialog> {
  late Map<String, dynamic> _answersJsonCopy;
  Map<String, dynamic>? _bei;
  late List<String> _questions;
  late List<String> _answers;
  late List<TextEditingController> _scoreControllers;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final raw = widget.exam.answersJson;
    _answersJsonCopy = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(jsonEncode(raw)) as Map<dynamic, dynamic>,
          );
    final beiRaw = _answersJsonCopy['bei'];
    _bei = beiRaw is Map ? Map<String, dynamic>.from(beiRaw) : null;
    final q = (_bei?['questions'] as List?) ?? const [];
    final a = (_bei?['answers'] as List?) ?? const [];
    _questions = q.map((e) => e.toString()).toList();
    _answers = a.map((e) => e.toString()).toList();
    final n = _answers.isEmpty ? 0 : _answers.length;
    final existingScores = (_bei?['scores'] as List?) ?? [];
    _scoreControllers = List.generate(n, (i) {
      if (i < existingScores.length && existingScores[i] != null) {
        return TextEditingController(
          text: existingScores[i].toString(),
        );
      }
      return TextEditingController();
    });
  }

  @override
  void dispose() {
    for (final c in _scoreControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? _mergedAnswersWithScores(List<double> scores) {
    if (_bei == null) return null;
    final bei = Map<String, dynamic>.from(_bei!);
    bei['scores'] = scores;
    bei['questions'] = _questions;
    bei['answers'] = _answers;
    final merged = Map<String, dynamic>.from(_answersJsonCopy);
    merged['bei'] = bei;
    return merged;
  }

  String _previewLine(Map<String, dynamic> merged) {
    final overall = RspScreeningScores.overallPercent(merged);
    final beiMap = merged['bei'];
    final bei = RspScreeningScores.beiSectionPercent(
      beiMap is Map ? Map<String, dynamic>.from(beiMap) : null,
    );
    if (overall == null) return 'Overall: —';
    final o = RspScreeningScores.roundOverall(overall);
    final beiStr = bei == null ? '—' : '${bei.toStringAsFixed(1)}%';
    return 'BEI section: $beiStr  ·  Overall screening: ${o.toStringAsFixed(1)}% (${o >= 60 ? 'pass' : 'fail'} at 60%)';
  }

  String? _livePreviewText() {
    if (_bei == null || _answers.isEmpty) return null;
    for (final c in _scoreControllers) {
      final t = c.text.trim();
      if (t.isEmpty) return 'Enter all scores to preview overall.';
      final v = double.tryParse(t.replaceAll(',', '.'));
      if (v == null || v < 0 || v > 100) {
        return 'Fix invalid scores to preview overall.';
      }
    }
    final scores = _scoreControllers
        .map(
          (c) =>
              (double.parse(c.text.trim().replaceAll(',', '.')))
                  .clamp(0, 100)
                  .toDouble(),
        )
        .toList();
    final merged = _mergedAnswersWithScores(scores);
    if (merged == null) return null;
    return _previewLine(merged);
  }

  Map<String, String>? _previewMetrics() {
    final text = _livePreviewText();
    if (text == null || text.startsWith('Enter all') || text.startsWith('Fix invalid')) {
      return null;
    }
    final merged = _mergedAnswersWithScores(
      _scoreControllers
          .map(
            (c) =>
                (double.parse(c.text.trim().replaceAll(',', '.')))
                    .clamp(0, 100)
                    .toDouble(),
          )
          .toList(),
    );
    if (merged == null) return null;
    final overall = RspScreeningScores.overallPercent(merged);
    final beiMap = merged['bei'];
    final bei = RspScreeningScores.beiSectionPercent(
      beiMap is Map ? Map<String, dynamic>.from(beiMap) : null,
    );
    if (overall == null) return null;
    final o = RspScreeningScores.roundOverall(overall);
    final pass = overall >= 60;
    return {
      'bei': bei == null ? '—' : '${bei.toStringAsFixed(1)}%',
      'overall': '${o.toStringAsFixed(1)}%',
      'status': pass ? 'Pass' : 'Below 60%',
    };
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
    });
    if (_bei == null || _answers.isEmpty) {
      setState(() => _error = 'No BEI answers to grade.');
      return;
    }
    if (_scoreControllers.length != _answers.length) {
      setState(() => _error = 'Internal error: score field count mismatch.');
      return;
    }
    final scores = <double>[];
    for (int i = 0; i < _scoreControllers.length; i++) {
      final t = _scoreControllers[i].text.trim();
      if (t.isEmpty) {
        setState(
          () => _error =
              'Enter a score (0–100) for every question (${i + 1} is empty).',
        );
        return;
      }
      final v = double.tryParse(t.replaceAll(',', '.'));
      if (v == null || v < 0 || v > 100) {
        setState(
          () => _error = 'Question ${i + 1}: use a number from 0 to 100.',
        );
        return;
      }
      scores.add(v);
    }

    final merged = _mergedAnswersWithScores(scores);
    if (merged == null) return;
    final overall = RspScreeningScores.overallPercent(merged);
    if (overall == null) {
      setState(() => _error = 'Could not compute overall score.');
      return;
    }
    final rounded = RspScreeningScores.roundOverall(overall);
    final passed = overall >= 60;

    setState(() => _saving = true);
    try {
      await RecruitmentRepo.instance.updateExamResult(
        widget.applicant.id,
        answersJson: merged,
        scorePercent: rounded,
        passed: passed,
        syncApplicationStatus: true,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      widget.onSaved();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'BEI saved. Overall screening score is now ${rounded.toStringAsFixed(1)}%.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Widget _previewBar() {
    final hint = _livePreviewText();
    final metrics = _previewMetrics();
    if (hint == null) return const SizedBox.shrink();
    if (metrics == null) {
      return Material(
        color: AppTheme.primaryNavy.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(
            hint,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      );
    }
    final pass = metrics['status'] == 'Pass';
    return Material(
      color: AppTheme.primaryNavy.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _metricChip(
              label: 'BEI average',
              value: metrics['bei']!,
            ),
            _metricChip(
              label: 'Overall screening',
              value: metrics['overall']!,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: pass
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: pass
                      ? const Color(0xFF43A047).withValues(alpha: 0.4)
                      : const Color(0xFFE57373).withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                pass ? 'Meets 60% threshold' : 'Below 60% threshold',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: pass
                      ? const Color(0xFF1B5E20)
                      : const Color(0xFFB71C1C),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _metricChip({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionCard(int i) {
    final qText = i < _questions.length && _questions[i].trim().isNotEmpty
        ? _questions[i]
        : 'Question ${i + 1}';
    final answerText =
        _answers[i].trim().isEmpty ? '(No answer text)' : _answers[i];

    final answerBox = Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 132),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.offWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Scrollbar(
        thumbVisibility: false,
        child: SingleChildScrollView(
          child: SelectableText(
            answerText,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary.withValues(alpha: 0.88),
              height: 1.45,
            ),
          ),
        ),
      ),
    );

    final scoreColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Points (max 100)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _scoreControllers[i],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            hintText: '0–100',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            filled: true,
            fillColor: AppTheme.white,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 520;
              final header = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryNavy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      qText,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.35,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              );

              if (wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: answerBox),
                        const SizedBox(width: 16),
                        SizedBox(width: 108, child: scoreColumn),
                      ],
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 10),
                  answerBox,
                  const SizedBox(height: 12),
                  scoreColumn,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBei = _bei != null && _answers.isNotEmpty;
    final screenH = MediaQuery.sizeOf(context).height;

    return Dialog(
      backgroundColor: AppTheme.offWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: screenH * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grade BEI — ${widget.applicant.fullName}',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Score each response from 0 to 100. When every item has a score, the overall screening result updates using the average of General, Math, General Information, and BEI.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.black.withValues(alpha: 0.08)),
            if (!hasBei)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'This applicant has no BEI responses stored (older submission or missing data).',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              )
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _previewBar(),
                      const SizedBox(height: 14),
                      Expanded(
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _answers.length,
                            itemBuilder: (context, i) => _questionCard(i),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            Divider(height: 1, color: Colors.black.withValues(alpha: 0.08)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: (!hasBei || _saving) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 20),
                    label: Text(_saving ? 'Saving…' : 'Save & update exam'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
