import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_balance.dart';
import 'leave_balance_card.dart';

/// Shows one credit wallet at a time on mobile, desktop, and web.
class LeaveCreditSwitcher extends StatefulWidget {
  const LeaveCreditSwitcher({super.key, required this.balances});

  final List<LeaveBalance> balances;

  @override
  State<LeaveCreditSwitcher> createState() => _LeaveCreditSwitcherState();
}

class _LeaveCreditSwitcherState extends State<LeaveCreditSwitcher> {
  String? _selectedType;

  @override
  void didUpdateWidget(covariant LeaveCreditSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.balances.any(
      (balance) => balance.effectiveLeaveTypeName == _selectedType,
    )) {
      _selectedType = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final balances = List<LeaveBalance>.of(widget.balances)
      ..sort((a, b) {
        int rank(LeaveBalance balance) => switch (balance.effectiveLeaveTypeName) {
          'sickLeave' => 0,
          'vacationLeave' => 1,
          _ => 2,
        };
        final order = rank(a).compareTo(rank(b));
        return order == 0 ? a.leaveTypeLabel.compareTo(b.leaveTypeLabel) : order;
      });
    if (balances.isEmpty) return const SizedBox.shrink();
    final matches = balances.indexWhere(
      (balance) => balance.effectiveLeaveTypeName == _selectedType,
    );
    final index = matches < 0 ? 0 : matches;
    final balance = balances[index];
    final next = balances[(index + 1) % balances.length];
    final canSwitch = widget.balances.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: LeaveBalanceCard(
            key: ValueKey(
              'leave-credit-card-${balance.effectiveLeaveTypeName}',
            ),
            balance: balance,
            headerAction: canSwitch
                ? IconButton(
                    tooltip: 'Show ${next.leaveTypeLabel}',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    onPressed: () => setState(
                      () => _selectedType = next.effectiveLeaveTypeName,
                    ),
                  )
                : null,
          ),
        ),
        if (canSwitch) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              '${index + 1} of ${widget.balances.length}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

