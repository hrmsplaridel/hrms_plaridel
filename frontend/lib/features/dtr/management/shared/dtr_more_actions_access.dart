import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

const leaveMoreActionPermissions = {
  'leave_paper_allowed': 'Record approved paper leave',
  'leave_types_allowed': 'Leave Type Rules',
  'leave_ledger_allowed': 'Leave Ledger',
  'leave_card_allowed': "Employee's Leave Card",
  'leave_balances_allowed': 'Manual balance adjustment',
  'leave_month_end_allowed': 'Run Month End',
  'leave_year_end_allowed': 'Year-End Forced Leave Deduction',
};
const locatorMoreActionPermissions = {
  'locator_file_allowed': 'File for employees',
  'locator_corrections_allowed': 'Record Correction',
  'locator_paper_allowed': 'Record approved paper locator',
  'locator_types_allowed': 'Manage Types',
};

/// Menu visibility follows server grants. Server endpoints remain authoritative.
class DtrMoreActionsAccess extends StatefulWidget {
  const DtrMoreActionsAccess({super.key, required this.builder});
  final Widget Function(BuildContext context, bool Function(String) allows)
  builder;
  @override
  State<DtrMoreActionsAccess> createState() => _DtrMoreActionsAccessState();
}

class _DtrMoreActionsAccessState extends State<DtrMoreActionsAccess>
    with WidgetsBindingObserver {
  Map<String, dynamic> _access = const {};
  StreamSubscription<AppRealtimeEvent>? _events;
  String? _identity;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final identity = '${auth.user?.id}:${auth.user?.role}';
    _events ??= context.read<AppRealtimeProvider>().events.listen((event) {
      if (event.name == 'admin_access_changed') unawaited(_load());
    });
    if (_identity != identity) {
      _identity = identity;
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final version = ++_version;
    setState(() => _access = const {});
    if (context.read<AuthProvider>().user?.role != 'admin') return;
    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/dtr-access/me',
      );
      if (!mounted || version != _version) return;
      setState(() => _access = response.data ?? const {});
    } catch (_) {
      // Remain denied on failure; resume or access-change events retry the check.
    }
  }

  bool _allows(String field) {
    final parent = leaveMoreActionPermissions.containsKey(field)
        ? 'leave_allowed'
        : locatorMoreActionPermissions.containsKey(field)
        ? 'locator_allowed'
        : null;
    if (parent == null) return false;
    final role = context.read<AuthProvider>().user?.role;
    if (role == 'hr') return true;
    return role == 'admin' && _access[parent] == true && _access[field] == true;
  }

  @override
  void dispose() {
    _version++;
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _allows);
}
