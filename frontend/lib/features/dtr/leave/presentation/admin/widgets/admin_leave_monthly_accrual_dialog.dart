import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/widgets/admin_leave_screen_utils.dart';

class AdminMonthlyAccrualDialog extends StatefulWidget {
  const AdminMonthlyAccrualDialog({super.key});

  @override
  State<AdminMonthlyAccrualDialog> createState() =>
      _AdminMonthlyAccrualDialogState();
}

class _AdminMonthlyAccrualDialogState extends State<AdminMonthlyAccrualDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _targetMonthController;
  final _maxCatchUpController = TextEditingController(text: '1');

  MonthlyLeaveAccrualResult? _preview;
  bool _loadingPreview = false;
  bool _applying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _targetMonthController = TextEditingController(text: _defaultTargetMonth());
    _targetMonthController.addListener(_clearPreviewAfterEdit);
    _maxCatchUpController.addListener(_clearPreviewAfterEdit);
  }

  @override
  void dispose() {
    _targetMonthController.removeListener(_clearPreviewAfterEdit);
    _maxCatchUpController.removeListener(_clearPreviewAfterEdit);
    _targetMonthController.dispose();
    _maxCatchUpController.dispose();
    super.dispose();
  }

  String _defaultTargetMonth() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  void _clearPreviewAfterEdit() {
    if (_preview == null || _loadingPreview || _applying) return;
    setState(() => _preview = null);
  }

  String? _validateTargetMonth(String? value) {
    final text = (value ?? '').trim();
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(text);
    if (match == null) return 'Use YYYY-MM';
    final month = int.tryParse(match.group(2) ?? '');
    if (month == null || month < 1 || month > 12) {
      return 'Month must be 01 to 12';
    }
    return null;
  }

  String? _validateMaxCatchUp(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null) return 'Enter a number';
    if (parsed < 1 || parsed > 120) return 'Use 1 to 120';
    return null;
  }

  MonthlyLeaveAccrualInput _input({required bool dryRun}) {
    return MonthlyLeaveAccrualInput(
      dryRun: dryRun,
      targetMonth: _targetMonthController.text.trim(),
      maxCatchUpMonths: int.parse(_maxCatchUpController.text.trim()),
    );
  }

  Future<void> _previewAccrual() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loadingPreview = true;
      _error = null;
      _preview = null;
    });
    final result = await context.read<LeaveProvider>().runMonthlyAccrual(
      _input(dryRun: true),
    );
    if (!mounted) return;
    setState(() {
      _loadingPreview = false;
      _preview = result;
      _error = result == null
          ? context.read<LeaveProvider>().error ?? 'Preview failed.'
          : null;
    });
  }

  Future<void> _applyAccrual() async {
    if (_preview == null || _preview!.rowsUpdated <= 0) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    final result = await context.read<LeaveProvider>().runMonthlyAccrual(
      _input(dryRun: false),
    );
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _applying = false;
        _error = context.read<LeaveProvider>().error ?? 'Apply failed.';
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingPreview || _applying;
    final canApply = !busy && _preview != null && _preview!.rowsUpdated > 0;

    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryNavy.withValues(
                        alpha: AppTheme.dashIsDark(context) ? 0.28 : 0.1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.event_repeat_rounded,
                      color: AppTheme.dashIsDark(context)
                          ? AppTheme.primaryNavyLight
                          : AppTheme.primaryNavy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Run Monthly Accrual',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Preview affected employees before adding monthly VL and SL credits.',
                          style: TextStyle(
                            color: AppTheme.dashTextSecondaryOf(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fields = [
                      TextFormField(
                        controller: _targetMonthController,
                        enabled: !busy,
                        decoration: adminLeaveInputDecoration(
                          context,
                          'Target month',
                        ).copyWith(
                          prefixIcon: const Icon(Icons.calendar_month_outlined),
                          hintText: 'YYYY-MM',
                        ),
                        validator: _validateTargetMonth,
                      ),
                      TextFormField(
                        controller: _maxCatchUpController,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        decoration: adminLeaveInputDecoration(
                          context,
                          'Max catch-up months',
                        ).copyWith(prefixIcon: const Icon(Icons.history)),
                        validator: _validateMaxCatchUp,
                      ),
                    ];
                    if (constraints.maxWidth < 560) {
                      return Column(
                        children: [
                          fields[0],
                          const SizedBox(height: 12),
                          fields[1],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        SizedBox(width: 220, child: fields[1]),
                      ],
                    );
                  },
                ),
              ),
            ),
            Expanded(child: _buildBody(busy)),
            Divider(height: 1, color: AppTheme.dashHairlineOf(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _previewAccrual,
                    icon: _loadingPreview
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                    label: Text(_loadingPreview ? 'Previewing...' : 'Preview'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canApply ? _applyAccrual : null,
                    icon: _applying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(_applying ? 'Applying...' : 'Apply Accrual'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool busy) {
    if (_error != null) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: _AdminMonthlyAccrualStatusPanel(
            icon: Icons.error_outline_rounded,
            message: _error!,
            warning: true,
          ),
        ),
      );
    }
    if (_loadingPreview) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      );
    }
    if (_preview == null) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: const _AdminMonthlyAccrualStatusPanel(
            icon: Icons.search_rounded,
            message:
                'Run preview to see employees who will receive accrual before applying.',
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: _AdminMonthlyAccrualPreview(result: _preview!),
    );
  }
}

class _AdminMonthlyAccrualPreview extends StatefulWidget {
  const _AdminMonthlyAccrualPreview({required this.result});

  final MonthlyLeaveAccrualResult result;

  @override
  State<_AdminMonthlyAccrualPreview> createState() =>
      _AdminMonthlyAccrualPreviewState();
}

class _AdminMonthlyAccrualPreviewState
    extends State<_AdminMonthlyAccrualPreview> {
  final ScrollController _detailsScrollController = ScrollController();

  @override
  void dispose() {
    _detailsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.result.details
        .where((row) => row.willChangeBalance)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AdminMonthlyAccrualSummaryChip(
              label: 'Will update',
              value: widget.result.rowsUpdated.toString(),
            ),
            _AdminMonthlyAccrualSummaryChip(
              label: 'Skipped',
              value: widget.result.rowsSkipped.toString(),
            ),
            _AdminMonthlyAccrualSummaryChip(
              label: 'Missing rows',
              value: widget.result.missingBalanceRowsDetected.toString(),
            ),
            _AdminMonthlyAccrualSummaryChip(
              label: 'Month',
              value: widget.result.targetYearMonth,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const _AdminMonthlyAccrualStatusPanel(
            icon: Icons.check_circle_outline_rounded,
            message:
                'No employees will receive accrual for this target month. They may already be credited.',
          )
        else
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.dashMutedSurfaceOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dashHairlineOf(context)),
              ),
              child: Scrollbar(
                controller: _detailsScrollController,
                child: ListView.separated(
                  controller: _detailsScrollController,
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: AppTheme.dashHairlineOf(context),
                  ),
                  itemBuilder: (context, index) =>
                      _AdminMonthlyAccrualDetailTile(detail: rows[index]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminMonthlyAccrualSummaryChip extends StatelessWidget {
  const _AdminMonthlyAccrualSummaryChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 13,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _AdminMonthlyAccrualDetailTile extends StatelessWidget {
  const _AdminMonthlyAccrualDetailTile({required this.detail});

  final MonthlyLeaveAccrualDetail detail;

  String _daysLabel() {
    final days = detail.daysAdded ?? 0;
    final fixed = days.toStringAsFixed(2);
    final text = fixed.endsWith('.00')
        ? fixed.substring(0, fixed.length - 3)
        : fixed.endsWith('0')
        ? fixed.substring(0, fixed.length - 1)
        : fixed;
    return '+$text days';
  }

  String _actionLabel() {
    return switch (detail.action) {
      'would_apply' => 'Will apply',
      'applied' => 'Applied',
      _ => detail.action.isEmpty ? 'Pending' : detail.action,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tags = <String>[
      _actionLabel(),
      if (detail.createdBalanceRow) 'Creates balance row',
      if (detail.hireProrated) 'Prorated',
      if (detail.monthsCredited != null)
        '${detail.monthsCredited} month${detail.monthsCredited == 1 ? '' : 's'}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.add_rounded,
              color: Color(0xFF2E7D32),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.employeeName,
                  style: TextStyle(
                    color: AppTheme.dashTextPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail.leaveType.displayName,
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12.5,
                  ),
                ),
                if (detail.lastAccrualDate != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Last accrual date: ${detail.lastAccrualDate}',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tags
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppTheme.dashHairlineOf(context),
                            ),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: AppTheme.dashTextSecondaryOf(context),
                              fontSize: 11,
                              height: 1,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _daysLabel(),
            style: const TextStyle(
              color: Color(0xFF2E7D32),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMonthlyAccrualStatusPanel extends StatelessWidget {
  const _AdminMonthlyAccrualStatusPanel({
    required this.icon,
    required this.message,
    this.warning = false,
  });

  final IconData icon;
  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? Colors.red.shade700
        : AppTheme.dashTextSecondaryOf(context);
    final background = warning
        ? Colors.red.shade50
        : AppTheme.dashMutedSurfaceOf(context);
    final border = warning
        ? Colors.red.shade100
        : AppTheme.dashHairlineOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
