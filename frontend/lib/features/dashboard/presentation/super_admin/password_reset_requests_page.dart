import 'dart:async';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/services/app_realtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';

class PasswordResetRequestsPage extends StatefulWidget {
  const PasswordResetRequestsPage({
    super.key,
    this.load,
    this.act,
    this.events,
  });
  final Stream<AppRealtimeEvent>? events;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? load;
  final Future<void> Function(String id, String action)? act;
  @override
  State<PasswordResetRequestsPage> createState() =>
      _PasswordResetRequestsPageState();
}

class _PasswordResetRequestsPageState extends State<PasswordResetRequestsPage>
    with WidgetsBindingObserver {
  StreamSubscription<AppRealtimeEvent>? _subscription;
  Timer? _poll;
  bool _refreshPending = false;
  AppRealtimeProvider? _realtime;
  bool _connected = false;
  List<Map<String, dynamic>> _rows = [];
  String _status = 'pending';
  int _page = 1;
  bool _busy = false, _more = false;
  bool _confirming = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _realtime = widget.events == null
        ? context.read<AppRealtimeProvider?>()
        : null;
    _connected = _realtime?.connected ?? false;
    _realtime?.addListener(_connectionChanged);
    _subscription = (widget.events ?? _realtime?.events)?.listen((event) {
      if (event.name == 'password_reset_requests_changed') _refreshLive();
    });
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshLive());
    _load();
  }

  void _connectionChanged() {
    final connected = _realtime?.connected ?? false;
    if (connected && !_connected) _refreshLive();
    _connected = connected;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshLive();
  }

  void _refreshLive() {
    if (!mounted) return;
    if (_busy) {
      _refreshPending = true;
      return;
    }
    _refreshPending = false;
    unawaited(_load(page: _page));
  }

  void _flushLiveRefresh() {
    if (mounted && _refreshPending && !_busy) _refreshLive();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _subscription?.cancel();
    _realtime?.removeListener(_connectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({int page = 1, String? status}) async {
    if (_busy) return;
    _refreshPending = false;
    final nextStatus = status ?? _status;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final query = <String, dynamic>{
        'page': page,
        if (nextStatus.isNotEmpty) 'status': nextStatus,
      };
      final data = widget.load != null
          ? await widget.load!(query)
          : (await ApiClient.instance.get<Map<String, dynamic>>(
              '/api/password-reset-requests',
              queryParameters: query,
            )).data!;
      if (!mounted) return;
      setState(() {
        _rows = (data['requests'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _more = data['has_more'] == true;
        _page = page;
        _status = nextStatus;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = 'Unable to load requests. ${userFacingApiError(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _flushLiveRefresh();
    }
  }

  Future<void> _act(Map<String, dynamic> row, String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _confirming = true;
    });
    var verified = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            action == 'send' ? 'Send reset OTP?' : 'Close this request?',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action == 'send'
                      ? 'Send a short-lived code to ${row['email']}. Verify the requester through your established identity-check procedure. A public submission alone does not verify identity.'
                      : 'Close the request and invalidate its outstanding email code. This does not change the password.',
                ),
                if (action == 'send')
                  CheckboxListTile(
                    value: verified,
                    onChanged: (value) =>
                        update(() => verified = value == true),
                    title: const Text('I have verified the requester.'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: action == 'send' && !verified
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(action == 'send' ? 'Send code' : 'Close request'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) {
      setState(() => _busy = false);
      _flushLiveRefresh();
      return;
    }
    try {
      if (widget.act != null) {
        await widget.act!(row['id'] as String, action);
      } else {
        await ApiClient.instance.post(
          '/api/password-reset-requests/${row['id']}/$action',
          data: {if (action == 'send') 'verified': true},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'send'
                ? 'Code sent to the registered email.'
                : 'Request closed.',
          ),
        ),
      );
      setState(() => _busy = false);
      await _load(page: _page);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Unable to update request. ${userFacingApiError(error)}';
          _busy = false;
        });
        _flushLiveRefresh();
      }
    }
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? 'Unknown date' : date.toString().split('.').first;
  }

  Color _statusColor(String status) => switch (status) {
    'sent' => Colors.blue,
    'closed' => Colors.teal,
    _ => Colors.orange,
  };

  String _statusLabel(String status) => switch (status) {
    'sent' => 'Code sent',
    'closed' => 'Closed',
    _ => 'Pending verification',
  };

  Widget _badge(String text, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _detail(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _requestCard(
    Map<String, dynamic> row, {
    bool compact = false,
    bool horizontal = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final status = row['status']?.toString() ?? 'pending';
    final accent = _statusColor(status);
    final name = row['full_name']?.toString().trim();
    final displayName = name == null || name.isEmpty ? 'Account' : name;
    final initials = displayName
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
    if (horizontal) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withValues(alpha: .14),
              child: Text(
                initials,
                style: TextStyle(color: accent, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    row['email']?.toString() ?? 'Email unavailable',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row['role'] == 'admin' ? 'Administrator' : 'Employee',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detail(
                    Icons.schedule,
                    'Requested ${_date(row['created_at'])}',
                  ),
                  if (row['sent_at'] != null)
                    _detail(
                      Icons.outgoing_mail,
                      'Sent ${_date(row['sent_at'])}',
                    ),
                  if (row['handled_by_name'] != null)
                    _detail(
                      Icons.person_outline,
                      'Handled by ${row['handled_by_name']}',
                    ),
                  if (row['completed_at'] != null)
                    _detail(
                      Icons.check_circle_outline,
                      'Password reset completed ${_date(row['completed_at'])}',
                    )
                  else if (row['closed_at'] != null)
                    _detail(
                      Icons.task_alt,
                      'Closed ${_date(row['closed_at'])}',
                    ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _badge(_statusLabel(status), accent),
                if (status != 'closed') ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _act(row, 'send'),
                        icon: const Icon(Icons.send_outlined, size: 16),
                        label: const Text('Send reset OTP'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _act(row, 'close'),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: accent),
          Padding(
            padding: EdgeInsets.all(compact ? 14 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: compact ? 18 : 23,
                      backgroundColor: accent.withValues(alpha: .14),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          _badge(
                            row['role'] == 'admin'
                                ? 'Administrator'
                                : 'Employee',
                            colors.onSurfaceVariant,
                            icon: row['role'] == 'admin'
                                ? Icons.shield_outlined
                                : Icons.person_outline,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 18),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(compact ? 8 : 12),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.mail_outline, size: 18, color: accent),
                          const SizedBox(width: 9),
                          Expanded(
                            child: SelectableText(
                              row['email']?.toString() ?? 'Email unavailable',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _detail(
                        Icons.schedule,
                        'Requested ${_date(row['created_at'])}',
                      ),
                      if (row['sent_at'] != null)
                        _detail(
                          Icons.outgoing_mail,
                          'Sent ${_date(row['sent_at'])}',
                        ),
                      if (row['handled_by_name'] != null)
                        _detail(
                          Icons.person_outline,
                          'Handled by ${row['handled_by_name']}',
                        ),
                      if (row['completed_at'] != null)
                        _detail(
                          Icons.check_circle_outline,
                          'Password reset completed ${_date(row['completed_at'])}',
                        )
                      else if (row['closed_at'] != null)
                        _detail(
                          Icons.task_alt,
                          'Closed ${_date(row['closed_at'])}',
                        ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 8 : 14),
                _badge(
                  _statusLabel(status),
                  accent,
                  icon: status == 'pending'
                      ? Icons.hourglass_top
                      : status == 'sent'
                      ? Icons.mark_email_read_outlined
                      : Icons.check_circle_outline,
                ),
                if (status != 'closed') ...[
                  SizedBox(height: compact ? 12 : 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final send = FilledButton.icon(
                        onPressed: _busy ? null : () => _act(row, 'send'),
                        icon: const Icon(Icons.send_outlined, size: 18),
                        label: const Text('Send reset OTP'),
                        style: FilledButton.styleFrom(
                          minimumSize: Size(0, compact ? 40 : 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                      final close = OutlinedButton(
                        onPressed: _busy ? null : () => _act(row, 'close'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size(0, compact ? 40 : 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Close'),
                      );
                      if (constraints.maxWidth < 300 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [send, const SizedBox(height: 8), close],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: send),
                          const SizedBox(width: 10),
                          close,
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) {
      final colors = Theme.of(context).colorScheme;
      return SingleChildScrollView(
        padding: EdgeInsets.all(viewport.maxWidth < 600 ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Password Reset Requests',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh requests',
                  onPressed: _busy ? null : () => _load(page: _page),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Verify the requester before sending a code to their registered email.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in const {
                  'pending': 'Pending',
                  'sent': 'Sent',
                  'closed': 'Closed',
                  '': 'All requests',
                }.entries)
                  ChoiceChip(
                    label: Text(item.value),
                    selected: _status == item.key,
                    avatar: Icon(
                      Icons.circle,
                      size: 9,
                      color: item.key.isEmpty
                          ? colors.onSurfaceVariant
                          : _statusColor(item.key),
                    ),
                    onSelected: _busy ? null : (_) => _load(status: item.key),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 22,
              child: _busy && !_confirming
                  ? const Center(child: LinearProgressIndicator(minHeight: 2))
                  : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!, style: TextStyle(color: colors.error)),
              ),
            if (_rows.isEmpty && !_busy)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 56,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 38,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text('No requests in this category.'),
                    const SizedBox(height: 6),
                    Text(
                      'New requests appear automatically.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = viewport.maxWidth >= 600;
                  final horizontal =
                      constraints.maxWidth >= 1000 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3;
                  final width = horizontal
                      ? constraints.maxWidth
                      : compact
                      ? constraints.maxWidth.clamp(0.0, 380.0)
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 18,
                    runSpacing: 18,
                    children: [
                      for (final row in _rows)
                        SizedBox(
                          width: width,
                          child: _requestCard(
                            row,
                            compact: compact,
                            horizontal: horizontal,
                          ),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: !_busy && _page > 1
                      ? () => _load(page: _page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Page $_page'),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: !_busy && _more
                      ? () => _load(page: _page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
