import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/admin_leave_screen.dart';
import 'package:hrms_plaridel/features/dtr/locator/presentation/admin/pages/admin_locator_management_screen.dart';
import 'package:hrms_plaridel/features/notifications/models/notification_tap_result.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/core/api/user_facing_api_error.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/shared/screens/profile_page.dart'
    show DashboardProfilePanel;
import 'package:hrms_plaridel/shared/widgets/collapsible_dashboard_sidebar.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_content_navigator.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_header_actions.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_mobile_bottom_nav.dart';
import 'package:hrms_plaridel/shared/widgets/portal_sidebar_brand.dart';
import 'package:hrms_plaridel/shared/data/philippine_courses.dart';
import 'package:hrms_plaridel/shared/models/philippine_address_data.dart';
import 'package:hrms_plaridel/shared/widgets/searchable_dropdown_field.dart';
import 'package:hrms_plaridel/features/mayor/data/mayor_endorsement_offices.dart';
import 'package:hrms_plaridel/features/mayor/presentation/widgets/mayor_monitoring_dashboard.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_welcome_banner.dart';
import 'package:hrms_plaridel/shared/widgets/structured_address_fields.dart';
import 'package:provider/provider.dart';

class MayorDashboardPage extends StatefulWidget {
  const MayorDashboardPage({super.key});

  @override
  State<MayorDashboardPage> createState() => _MayorDashboardPageState();
}

enum _MayorMenu {
  dashboard,
  meetings,
  decisions,
  requests,
  scheduling,
  history,
  locator,
  leave,
  profile,
}

class _MayorPortalCapabilities {
  const _MayorPortalCapabilities({
    required this.isMayor,
    required this.isStaff,
  });

  final bool isMayor;
  final bool isStaff;

  bool get canCreateIntake => isStaff;
  bool get canScheduleMeetings => isStaff;
  /// Mayor or Staff — early/sudden meetings may be recorded right after approve.
  bool get canRecordAttendance => isStaff || isMayor;
  bool get canDecideMeetings => isMayor;
  bool get canFinalDecide => isMayor;
}

class _MayorDashboardPageState extends State<MayorDashboardPage> {
  _MayorMenu _selectedMenu = _MayorMenu.dashboard;

  _MayorPortalCapabilities get _caps {
    final role =
        (context.read<AuthProvider>().user?.role ?? '').trim().toLowerCase();
    return _MayorPortalCapabilities(
      isMayor: role == 'mayor',
      isStaff: role == 'mayor_office_staff',
    );
  }
  bool _sidebarCollapsed = false;
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();

  final _repo = MayorEndorsementRepo.instance;

  late Future<MayorDashboardData> _dashboardFuture = _repo.fetchDashboard();
  String _search = '';
  String _office = '';
  String _status = '';
  String _priority = '';
  String _meetingRequestStatus = '';
  DateTime? _fromDate;
  DateTime? _toDate;
  int _page = 1;
  int _historyPage = 1;
  final int _pageSize = 20;
  bool _loadingList = false;
  bool _loadingHistory = false;
  bool _submittingIntake = false;

  // History filters (independent of Requests workspace filters).
  String _historySearch = '';
  String _historyOffice = '';
  String _historyStatus = '';
  DateTime? _historyFromDate;
  DateTime? _historyToDate;
  bool _historyIncludeTest = false;

  /// Bumps [DashboardContentNavigator] homeRefreshKey so list/loading updates paint.
  int _contentEpoch = 0;
  MayorEndorsementListResponse _requests = MayorEndorsementListResponse.empty();
  MayorEndorsementListResponse _history = MayorEndorsementListResponse.empty();

  void _bumpContent() {
    _contentEpoch++;
  }

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _loadHistory();
  }

  Future<void> _refreshDashboard() async {
    setState(() {
      _dashboardFuture = _repo.fetchDashboard();
      _bumpContent();
    });
    await _dashboardFuture;
    if (mounted) setState(_bumpContent);
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loadingList = true;
      _bumpContent();
    });
    try {
      final result = await _repo.listRequests(
        search: _search,
        office: _office,
        status: _status,
        priority: _priority,
        meetingRequestStatus: _meetingRequestStatus,
        fromDate: _fromDate,
        toDate: _toDate,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _requests = result;
        _bumpContent();
      });
    } catch (e) {
      if (!mounted) return;
      _showError(
        'Failed to load endorsement requests: ${userFacingApiError(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingList = false;
          _bumpContent();
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _bumpContent();
    });
    try {
      // History is independent of Requests filters (pending/mayor_approved would
      // otherwise wipe endorsed/rejected results).
      final result = await _repo.listHistory(
        search: _historySearch,
        office: _historyOffice,
        status: _historyStatus,
        fromDate: _historyFromDate,
        toDate: _historyToDate,
        includeTest: _historyIncludeTest,
        page: _historyPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _history = result;
        _bumpContent();
      });
    } catch (e) {
      if (!mounted) return;
      _showError(
        'Failed to load endorsement history: ${userFacingApiError(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
          _bumpContent();
        });
      }
    }
  }

  void _clearHistoryFilters() {
    setState(() {
      _historySearch = '';
      _historyOffice = '';
      _historyStatus = '';
      _historyFromDate = null;
      _historyToDate = null;
      _historyIncludeTest = false;
      _historyPage = 1;
      _bumpContent();
    });
    _loadHistory();
  }

  void _applyHistoryDatePreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? from;
    DateTime? to = today;
    switch (preset) {
      case 'today':
        from = today;
        break;
      case 'week':
        // Monday week boundary (aligned with backend Asia/Manila week).
        from = today.subtract(Duration(days: (today.weekday - DateTime.monday) % 7));
        break;
      case 'month':
        from = DateTime(today.year, today.month, 1);
        break;
      default:
        from = null;
        to = null;
    }
    setState(() {
      _historyFromDate = from;
      _historyToDate = to;
      _historyPage = 1;
      _bumpContent();
    });
    _loadHistory();
  }

  Future<void> _openDashListItem(MayorDashListItem item) async {
    await _openRequest(MayorEndorsementRequest.fromJson(item.raw));
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([
      _refreshDashboard(),
      _loadRequests(),
      _loadHistory(),
    ]);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openRequest(MayorEndorsementRequest item) async {
    final details = await _repo.getRequestDetails(item.id);
    if (!mounted) return;
    final caps = _caps;

    final result = await showDialog<_ReviewActionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MayorReviewDialog(
        details: details,
        canScheduleMeetings: caps.canScheduleMeetings,
        canRecordAttendance: caps.canRecordAttendance,
        canFinalDecide: caps.canFinalDecide,
        onScheduleMeeting: caps.canScheduleMeetings
            ? () => _scheduleMayorMeeting(item)
            : null,
        onMarkNoShow: caps.canRecordAttendance
            ? () => _markMayorMeetingNoShow(item)
            : null,
        onMarkMetMayor:
            caps.canRecordAttendance ? () => _markMetMayor(item) : null,
      ),
    );

    if (!mounted || result == null) return;
    if (!caps.canFinalDecide) {
      _showError('Only the Municipal Mayor can approve or reject endorsements.');
      return;
    }

    if (result.action == _ReviewAction.approve ||
        result.action == _ReviewAction.approveForm) {
      if (item.status == 'pending' && !item.hasMetMayor) {
        _showError(
          'Attendance must be recorded after an approved meeting before endorsement.',
        );
        return;
      }
      final ok = await _confirm(
        title: 'Endorse applicant',
        message:
            'Endorse this applicant as Municipal Mayor? This is the final endorsement decision.',
      );
      if (!ok) return;
      try {
        await _repo.endorseRequest(
          item.id,
          destinationOfficeId: result.destinationOfficeId,
          destinationOfficeName: result.destinationOfficeName,
          remarks: result.remarks,
        );
        _showSuccess('Applicant endorsed by Municipal Mayor.');
        await _refreshAll();
      } catch (e) {
        _showError('Failed to endorse request: ${userFacingApiError(e)}');
      }
      return;
    }

    if (result.action == _ReviewAction.reject) {
      if (item.status == 'pending' && !item.hasMetMayor) {
        _showError(
          'Step 2 first: the applicant must meet the Mayor. '
          'If they cannot, schedule a meeting.',
        );
        return;
      }
      final reason = (result.reason ?? '').trim();
      final ok = await _confirm(
        title: 'Reject Endorsement',
        message: 'Reject this endorsement request?',
      );
      if (!ok) return;
      try {
        await _repo.rejectRequest(item.id, reason);
        _showSuccess('Endorsement rejected.');
        await _refreshAll();
      } catch (e) {
        _showError('Failed to reject request: ${userFacingApiError(e)}');
      }
    }
  }

  Future<void> _endorseFromCard(MayorEndorsementRequest item) async {
    if (item.status != 'pending' && item.status != 'mayor_approved') return;
    if (item.status == 'pending' && !item.hasMetMayor) {
      _showError(
        'Attendance must be recorded after an approved meeting before endorsement.',
      );
      return;
    }

    final picked = await showDialog<_ApproveOfficeChoice>(
      context: context,
      builder: (_) => _ApproveEndorsementDialog(
        applicantName: item.applicantName,
        initialOfficeName: item.endorseToOffice == 'Unassigned'
            ? ''
            : item.endorseToOffice,
        initialOfficeId: item.destinationOfficeId,
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await _repo.endorseRequest(
        item.id,
        destinationOfficeId: picked.officeId,
        destinationOfficeName: picked.officeName,
        remarks: item.mayorRemarks,
      );
      _showSuccess('Applicant endorsed by Municipal Mayor.');
      await _refreshAll();
    } catch (e) {
      _showError('Failed to endorse request: ${userFacingApiError(e)}');
    }
  }

  Future<void> _rejectFromCard(MayorEndorsementRequest item) async {
    if (item.status != 'pending' && item.status != 'mayor_approved') return;
    if (item.status == 'pending' && !item.hasMetMayor) {
      _showError(
        'Step 2 first: the applicant must meet the Mayor. '
        'If they cannot, schedule a meeting.',
      );
      return;
    }
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject endorsement?'),
        content: SizedBox(
          width: (MediaQuery.sizeOf(ctx).width - 80).clamp(240.0, 420.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.applicantName),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                minLines: 2,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Rejection reason (optional)',
                  hintText: 'Optional note',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(reasonCtrl.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null) return;
    try {
      await _repo.rejectRequest(item.id, reason);
      _showSuccess('Endorsement rejected.');
      await _refreshAll();
    } catch (e) {
      _showError('Failed to reject request: ${userFacingApiError(e)}');
    }
  }

  Future<void> _openIntakeForm() async {
    if (!_caps.canCreateIntake) {
      _showError(
        "Only Mayor's Office Staff can create endorsement intake records.",
      );
      return;
    }
    final result = await showDialog<MayorEndorsementIntakeSubmission>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _MayorEndorsementIntakeDialog(),
    );
    if (!mounted || result == null) return;

    setState(() {
      _submittingIntake = true;
      _bumpContent();
    });
    try {
      await _repo.submitEndorsementRequest(
        priority: result.priority,
        intakeForm: result.intakeForm.toJson(),
        staffNotes: result.staffNotes,
        requestedOfficeId: result.requestedOfficeId,
        requestedOfficeName: result.requestedOfficeName,
      );
      _showSuccess(
        'Intake form submitted and queued for Mayor / Mayor\'s Office staff review.',
      );
      await _refreshAll();
    } catch (e) {
      _showError(
        'Failed to submit endorsement intake form: ${userFacingApiError(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingIntake = false;
          _bumpContent();
        });
      }
    }
  }

  Future<bool> _scheduleMayorMeeting(MayorEndorsementRequest item) async {
    final now = DateTime.now();
    final initial = item.meetingProposedAt?.toLocal() ??
        item.appointmentAt?.toLocal() ??
        now.add(const Duration(days: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Proposed meeting date',
    );
    if (day == null || !mounted) return false;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Proposed meeting time',
    );
    if (time == null || !mounted) return false;
    final purposeCtrl = TextEditingController(
      text: (item.meetingPurpose ?? '').trim(),
    );
    final purpose = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Meeting purpose'),
        content: TextField(
          controller: purposeCtrl,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Purpose / remarks (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(purposeCtrl.text.trim()),
            child: const Text('Submit request'),
          ),
        ],
      ),
    );
    // null = Cancel; empty string is allowed (purpose optional).
    if (purpose == null || !mounted) return false;
    final dt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    try {
      await _repo.submitMeetingRequest(
        item.id,
        proposedAt: dt,
        purpose: purpose,
      );
      _showSuccess('Meeting request submitted for Mayor approval.');
      await _refreshAll();
      return true;
    } catch (e) {
      _showError('Failed to submit meeting request: ${userFacingApiError(e)}');
      return false;
    }
  }

  Future<void> _approveMeeting(MayorEndorsementRequest item) async {
    final when = item.meetingProposedAt ?? item.appointmentAt;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final secondary = AppTheme.dashTextSecondaryOf(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: AppTheme.primaryNavy,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Approve schedule?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.applicantName.trim().isEmpty
                    ? 'Applicant'
                    : item.applicantName.trim(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (when != null) ...[
                const SizedBox(height: 4),
                Text(
                  _fmtDateTime(when),
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Schedule only — not an endorsement.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await _repo.approveMeeting(item.id);
      _showSuccess('Schedule approved.');
      await _refreshAll();
    } catch (e) {
      _showError('Failed to approve meeting: ${userFacingApiError(e)}');
    }
  }

  Future<void> _rescheduleMeeting(MayorEndorsementRequest item) async {
    final remarksCtrl = TextEditingController();
    final remarks = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request reschedule'),
        content: TextField(
          controller: remarksCtrl,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Remarks for Mayor\'s Office Staff',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(remarksCtrl.text.trim()),
            child: const Text('Send to Staff'),
          ),
        ],
      ),
    );
    if (remarks == null || remarks.isEmpty || !mounted) return;
    try {
      await _repo.rescheduleMeeting(item.id, remarks: remarks);
      _showSuccess('Reschedule requested. Staff must submit a revised schedule.');
      await _refreshAll();
    } catch (e) {
      _showError('Failed to request reschedule: ${userFacingApiError(e)}');
    }
  }

  Future<void> _declineMeeting(MayorEndorsementRequest item) async {
    final remarksCtrl = TextEditingController();
    final remarks = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline meeting?'),
        content: TextField(
          controller: remarksCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Optional remarks',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(remarksCtrl.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
            ),
            child: const Text('Decline meeting'),
          ),
        ],
      ),
    );
    if (remarks == null || !mounted) return;
    try {
      await _repo.declineMeeting(item.id, remarks: remarks);
      _showSuccess(
        'Meeting declined. The endorsement request remains open.',
      );
      await _refreshAll();
    } catch (e) {
      _showError('Failed to decline meeting: ${userFacingApiError(e)}');
    }
  }

  Future<bool> _markMetMayor(MayorEndorsementRequest item) async {
    final name = item.applicantName.trim().isEmpty
        ? 'Applicant'
        : item.applicantName.trim();
    final when = item.appointmentAt ?? item.meetingProposedAt;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final secondary = AppTheme.dashTextSecondaryOf(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.handshake_outlined,
                  color: AppTheme.primaryNavy,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Met the Mayor?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (when != null) ...[
                const SizedBox(height: 4),
                Text(
                  _fmtDateTime(when),
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Unlocks endorse / reject.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    if (ok != true) return false;
    try {
      await _repo.markMetMayor(item.id);
      _showSuccess('Met the Mayor recorded.');
      await _refreshAll();
      return true;
    } catch (e) {
      _showError('Failed to record meeting: ${userFacingApiError(e)}');
      return false;
    }
  }

  Future<bool> _markMayorMeetingNoShow(MayorEndorsementRequest item) async {
    final name = item.applicantName.trim().isEmpty
        ? 'Applicant'
        : item.applicantName.trim();
    final when = item.appointmentAt ?? item.meetingProposedAt;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final secondary = AppTheme.dashTextSecondaryOf(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.event_busy_rounded,
                  color: AppTheme.primaryNavy,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Did not appear?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (when != null) ...[
                const SizedBox(height: 4),
                Text(
                  _fmtDateTime(when),
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Staff can request a new schedule.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryNavy,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    if (ok != true) return false;
    try {
      await _repo.markMayorMeetingNoShow(item.id);
      _showSuccess('Marked did not appear.');
      await _refreshAll();
      return true;
    } catch (e) {
      _showError('Failed to mark no-show: ${userFacingApiError(e)}');
      return false;
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return res == true;
  }

  void _openRequests({String status = ''}) {
    _status = status;
    _page = 1;
    final caps = _caps;
    _onMenuSelected(caps.isMayor ? _MayorMenu.decisions : _MayorMenu.requests);
  }

  bool _isRequestsWorkspace(_MayorMenu menu) =>
      menu == _MayorMenu.requests ||
      menu == _MayorMenu.meetings ||
      menu == _MayorMenu.decisions ||
      menu == _MayorMenu.scheduling;

  Widget _settingsView() => DashboardProfilePanel(onBack: _closeProfile);

  void _onMenuSelected(_MayorMenu menu) {
    if (menu == _MayorMenu.profile) {
      _openProfile();
      return;
    }
    final settingsOnTop = DashboardContentNavigator.isSettingsOnTop(
      _contentNavKey.currentState,
    );
    if (_selectedMenu == menu && !settingsOnTop) return;
    if (_selectedMenu != menu) {
      setState(() => _selectedMenu = menu);
    }
    DashboardContentNavigator.showHome(_contentNavKey);
    if (menu == _MayorMenu.history) {
      _loadHistory();
    } else if (_isRequestsWorkspace(menu)) {
      _loadRequests();
    } else if (menu == _MayorMenu.dashboard) {
      _refreshDashboard();
    }
  }

  void _onNotificationTap(NotificationTapResult? result) {
    if (result?.kind == NotificationTapKind.adminDtrLocatorManagement) {
      _onMenuSelected(_MayorMenu.locator);
    } else if(result?.kind == NotificationTapKind.adminDtrLeaveManagement) {
      _onMenuSelected(_MayorMenu.leave);
    }
  }

  void _openProfile() {
    if (DashboardContentNavigator.isSettingsOnTop(
      _contentNavKey.currentState,
    )) {
      setState(() => _selectedMenu = _MayorMenu.profile);
      return;
    }
    setState(() => _selectedMenu = _MayorMenu.profile);
    DashboardContentNavigator.openSettings(_contentNavKey);
  }

  void _closeProfile() {
    final nav = _contentNavKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
    if (!mounted) return;
    if (_selectedMenu == _MayorMenu.profile) {
      setState(() => _selectedMenu = _MayorMenu.dashboard);
      DashboardContentNavigator.showHome(_contentNavKey);
    }
  }

  Widget _buildRequestsWorkspace(_MayorPortalCapabilities caps) {
    final title = switch (_selectedMenu) {
      _MayorMenu.meetings => 'Meetings',
      _MayorMenu.decisions => 'Decisions',
      _MayorMenu.scheduling => 'Scheduling',
      _ => 'Requests',
    };
    final subtitle = switch (_selectedMenu) {
      _MayorMenu.meetings =>
        'Approve schedules, then record Met the Mayor or Did not appear anytime after approval.',
      _MayorMenu.decisions =>
        'Endorse or reject applicants after approved meeting attendance.',
      _MayorMenu.scheduling =>
        'Submit meeting requests, track Mayor decisions, and record attendance.',
      _ => caps.isStaff
          ? 'Register applicants and track endorsement requests.'
          : 'Monitor endorsement requests requiring Mayor attention.',
    };
    return _MayorRequestsTab(
      title: title,
      subtitle: subtitle,
      workspace: _selectedMenu,
      capabilities: caps,
      loading: _loadingList,
      submittingIntake: _submittingIntake,
      requests: _requests,
      search: _search,
      office: _office,
      status: _status,
      priority: _priority,
      meetingRequestStatus: _meetingRequestStatus,
      fromDate: _fromDate,
      toDate: _toDate,
      onSearchChanged: (v) => _search = v,
      onOfficeChanged: (v) => _office = v,
      onStatusChanged: (v) => _status = v,
      onPriorityChanged: (v) => _priority = v,
      onMeetingRequestStatusChanged: (v) => _meetingRequestStatus = v,
      onFromDateChanged: (v) => _fromDate = v,
      onToDateChanged: (v) => _toDate = v,
      onApplyFilters: () async {
        _page = 1;
        await _loadRequests();
      },
      page: _requests.page,
      totalPages: _requests.totalPages,
      onPreviousPage: () async {
        if (_page <= 1) return;
        _page -= 1;
        await _loadRequests();
      },
      onNextPage: () async {
        if (_page >= _requests.totalPages) return;
        _page += 1;
        await _loadRequests();
      },
      onOpenIntakeForm: _openIntakeForm,
      onOpenRequest: _openRequest,
      onApproveOfficeForm: _endorseFromCard,
      onApproveRequest: _endorseFromCard,
      onRejectRequest: _rejectFromCard,
      onScheduleMeeting: _scheduleMayorMeeting,
      onMarkNoShow: _markMayorMeetingNoShow,
      onMarkMetMayor: _markMetMayor,
      onApproveMeeting: _approveMeeting,
      onRescheduleMeeting: _rescheduleMeeting,
      onDeclineMeeting: _declineMeeting,
    );
  }

  Widget _buildContent() {
    final caps = _caps;
    switch (_selectedMenu) {
      case _MayorMenu.leave:
        return const AdminLeaveScreen(isMayor:true);
      case _MayorMenu.locator:
        return const AdminLocatorManagementScreen();
      case _MayorMenu.dashboard:
        return _MayorDashboardTab(
          dashboardFuture: _dashboardFuture,
          isMayor: caps.isMayor,
          onRefresh: _refreshDashboard,
          onOpenRequest: _openDashListItem,
          onOpenMeetings: () => _onMenuSelected(_MayorMenu.meetings),
          onOpenDecisions: () => _onMenuSelected(
            caps.isMayor ? _MayorMenu.decisions : _MayorMenu.requests,
          ),
          onOpenRequests: () => _openRequests(),
          onOpenHistory: () => _onMenuSelected(_MayorMenu.history),
        );
      case _MayorMenu.meetings:
      case _MayorMenu.decisions:
      case _MayorMenu.requests:
      case _MayorMenu.scheduling:
        return _buildRequestsWorkspace(caps);
      case _MayorMenu.history:
        return _MayorHistoryTab(
          history: _history,
          loading: _loadingHistory,
          search: _historySearch,
          office: _historyOffice,
          status: _historyStatus,
          fromDate: _historyFromDate,
          toDate: _historyToDate,
          onSearchChanged: (v) => _historySearch = v,
          onOfficeChanged: (v) => _historyOffice = v,
          onStatusChanged: (v) {
            setState(() {
              _historyStatus = v;
              _bumpContent();
            });
          },
          onFromDateChanged: (v) {
            setState(() {
              _historyFromDate = v;
              _bumpContent();
            });
          },
          onToDateChanged: (v) {
            setState(() {
              _historyToDate = v;
              _bumpContent();
            });
          },
          onApplyFilters: () async {
            _historyPage = 1;
            await _loadHistory();
          },
          onClearFilters: _clearHistoryFilters,
          onDatePreset: _applyHistoryDatePreset,
          onOpenRequest: _openRequest,
          onRefresh: _loadHistory,
          onPreviousPage: () async {
            if (_historyPage <= 1) return;
            _historyPage -= 1;
            await _loadHistory();
          },
          onNextPage: () async {
            if (_historyPage >= _history.totalPages) return;
            _historyPage += 1;
            await _loadHistory();
          },
        );
      case _MayorMenu.profile:
        return _settingsView();
    }
  }

  List<DashboardMobileNavItem> get _mobileNavItems {
    final caps = _caps;
    const approvals = <DashboardMobileNavItem>[
      DashboardMobileNavItem(
        icon: Icons.location_on_outlined,
        label: 'Locators',
      ),
      DashboardMobileNavItem(icon: Icons.event_note_outlined, label: 'Leave'),
    ];
    if (caps.isMayor) {
      return const [
        DashboardMobileNavItem(
          icon: Icons.dashboard_outlined,
          label: 'Dashboard',
        ),
        DashboardMobileNavItem(icon: Icons.event_outlined, label: 'Meetings'),
        DashboardMobileNavItem(icon: Icons.gavel_outlined, label: 'Decisions'),
        DashboardMobileNavItem(icon: Icons.history_outlined, label: 'History'),
        ...approvals,
      ];
    }
    return const [
      DashboardMobileNavItem(
        icon: Icons.dashboard_outlined,
        label: 'Dashboard',
      ),
      DashboardMobileNavItem(
        icon: Icons.assignment_outlined,
        label: 'Requests',
      ),
      DashboardMobileNavItem(
        icon: Icons.calendar_month_outlined,
        label: 'Scheduling',
      ),
      DashboardMobileNavItem(icon: Icons.history_outlined, label: 'History'),
      ...approvals,
    ];
  }

  int get _mobileNavIndex {
    final caps = _caps;
    if (caps.isMayor) {
      return switch (_selectedMenu) {
        _MayorMenu.meetings => 1,
        _MayorMenu.decisions => 2,
        _MayorMenu.history => 3,
        _MayorMenu.locator => 4,
        _MayorMenu.leave => 5,
        _MayorMenu.profile => -1,
        _ => 0,
      };
    }
    return switch (_selectedMenu) {
      _MayorMenu.requests => 1,
      _MayorMenu.scheduling => 2,
      _MayorMenu.history => 3,
      _MayorMenu.locator => 4,
      _MayorMenu.leave => 5,
      _MayorMenu.profile => -1,
      _ => 0,
    };
  }

  void _onMobileNav(int index) {
    final caps = _caps;
    if (caps.isMayor) {
      switch (index) {
        case 1:
          _onMenuSelected(_MayorMenu.meetings);
        case 2:
          _onMenuSelected(_MayorMenu.decisions);
        case 3:
          _onMenuSelected(_MayorMenu.history);
        case 4:
          _onMenuSelected(_MayorMenu.locator);
        case 5:
          _onMenuSelected(_MayorMenu.leave);
        default:
          _onMenuSelected(_MayorMenu.dashboard);
      }
      return;
    }
    switch (index) {
      case 1:
        _onMenuSelected(_MayorMenu.requests);
      case 2:
        _onMenuSelected(_MayorMenu.scheduling);
      case 3:
        _onMenuSelected(_MayorMenu.history);
      case 4:
        _onMenuSelected(_MayorMenu.locator);
      case 5:
        _onMenuSelected(_MayorMenu.leave);
      default:
        _onMenuSelected(_MayorMenu.dashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 900;
    final contentPadding = width > 900 ? 16.0 : (width > 600 ? 14.0 : 12.0);
    final displayName = context.select<AuthProvider, String>(
      (a) => a.displayName.isNotEmpty ? a.displayName : 'Mayor',
    );
    final avatarPath = context.select<AuthProvider, String?>(
      (a) => a.avatarPath,
    );

    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: _MayorSidebar(
                  selectedMenu: _selectedMenu,
                  avatarPath: avatarPath,
                  displayName: displayName,
                  onProfile: () {
                    Navigator.of(context).pop();
                    _openProfile();
                  },
                  showBrand: true,
                  onTap: (menu) {
                    _onMenuSelected(menu);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ),
      bottomNavigationBar: isWide
          ? null
          : DashboardMobileBottomNav(
              items: _mobileNavItems,
              selectedIndex: _mobileNavIndex,
              onSelected: _onMobileNav,
            ),
      body: SafeArea(
        bottom: isWide,
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MayorSidebar(
                    railMode: true,
                    collapsed: _sidebarCollapsed,
                    onToggle: () =>
                        setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                    showBrand: false,
                    selectedMenu: _selectedMenu,
                    avatarPath: avatarPath,
                    displayName: displayName,
                    onProfile: _openProfile,
                    onTap: _onMenuSelected,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        DashboardAppHeaderBar(
                          onNotificationTap: _onNotificationTap,
                          showBrand: false,
                          showSidebarToggle: true,
                          sidebarCollapsed: _sidebarCollapsed,
                          onSidebarToggle: () => setState(
                            () => _sidebarCollapsed = !_sidebarCollapsed,
                          ),
                          compactActions: width < 600,
                          trailing: DashboardAccountMenuButton(
                            avatarPath: avatarPath,
                            compact: width < 600,
                            tooltip: displayName,
                            onProfile: _openProfile,
                          ),
                        ),
                        Expanded(
                          child: ColoredBox(
                            color: AppTheme.dashCanvasOf(context),
                            child: DashboardContentNavigator(
                              navigatorKey: _contentNavKey,
                              homeCacheKey: _selectedMenu,
                              homeRefreshKey: Object.hash(
                                _selectedMenu,
                                displayName,
                                contentPadding,
                                _contentEpoch,
                              ),
                              homeBuilder: _buildContent,
                              settingsPanel: _settingsView(),
                              homeScrollPadding: EdgeInsets.all(contentPadding),
                              settingsScrollPadding:
                                  kDashboardSettingsScrollPadding,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Builder(
                    builder: (innerContext) => DashboardAppHeaderBar(
                      onNotificationTap: _onNotificationTap,
                      showBrand: true,
                      showMenuButton: true,
                      onMenuPressed: () =>
                          Scaffold.of(innerContext).openDrawer(),
                      compactActions: true,
                      trailing: DashboardAccountMenuButton(
                        avatarPath: avatarPath,
                        compact: true,
                        tooltip: displayName,
                        onProfile: _openProfile,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: AppTheme.dashCanvasOf(context),
                      child: SingleChildScrollView(
                        key: ValueKey(_selectedMenu),
                        padding: EdgeInsets.all(contentPadding),
                        child: _buildContent(),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MayorSidebar extends StatelessWidget {
  const _MayorSidebar({
    required this.selectedMenu,
    required this.avatarPath,
    required this.displayName,
    required this.onProfile,
    required this.onTap,
    this.showBrand = true,
    this.railMode = false,
    this.collapsed = false,
    this.onToggle,
  });

  final _MayorMenu selectedMenu;
  final String? avatarPath;
  final String displayName;
  final VoidCallback onProfile;
  final ValueChanged<_MayorMenu> onTap;
  final bool showBrand;
  final bool railMode;
  final bool collapsed;
  final VoidCallback? onToggle;

  Widget _buildNavList(BuildContext context) {
    final role =
        (context.watch<AuthProvider>().user?.role ?? '').trim().toLowerCase();
    final isMayor = role == 'mayor';
    final navChildren = <Widget>[
      SizedBox(height: railMode ? 8 : (showBrand ? 2 : 8)),
      DashboardSidebarNavTile(
        icon: Icons.dashboard_outlined,
        label: 'Dashboard',
        selected: selectedMenu == _MayorMenu.dashboard,
        onTap: () => onTap(_MayorMenu.dashboard),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Divider(
          height: 1,
          thickness: 1,
          color: AppTheme.dashHairlineOf(context),
        ),
      ),
      const DashboardSidebarSectionLabel('ENDORSEMENTS'),
    ];
    if (isMayor) {
      navChildren.addAll([
        DashboardSidebarNavTile(
          icon: Icons.event_outlined,
          label: 'Meetings',
          selected: selectedMenu == _MayorMenu.meetings,
          onTap: () => onTap(_MayorMenu.meetings),
        ),
        DashboardSidebarNavTile(
          icon: Icons.gavel_outlined,
          label: 'Decisions',
          selected: selectedMenu == _MayorMenu.decisions,
          onTap: () => onTap(_MayorMenu.decisions),
        ),
      ]);
    } else {
      navChildren.addAll([
        DashboardSidebarNavTile(
          icon: Icons.assignment_outlined,
          label: 'Requests',
          selected: selectedMenu == _MayorMenu.requests,
          onTap: () => onTap(_MayorMenu.requests),
        ),
        DashboardSidebarNavTile(
          icon: Icons.calendar_month_outlined,
          label: 'Scheduling',
          selected: selectedMenu == _MayorMenu.scheduling,
          onTap: () => onTap(_MayorMenu.scheduling),
        ),
      ]);
    }
    navChildren.addAll([
      DashboardSidebarNavTile(
        icon: Icons.history_outlined,
        label: 'History',
        selected: selectedMenu == _MayorMenu.history,
        onTap: () => onTap(_MayorMenu.history),
      ),
      const SizedBox(height: 12),
      DashboardSidebarNavTile(
        icon: Icons.location_on_outlined,
        label: 'Locator approvals',
        selected: selectedMenu == _MayorMenu.locator,
        onTap: () => onTap(_MayorMenu.locator),
      ),
      DashboardSidebarNavTile(
        icon: Icons.event_note_outlined,
        label: 'Leave approvals',
        selected: selectedMenu == _MayorMenu.leave,
        onTap: () => onTap(_MayorMenu.leave),
      ),
    ]);
    return Column(mainAxisSize: MainAxisSize.min, children: navChildren);
  }

  Widget _buildFooter(BuildContext context) {
    final year = DateTime.now().year;
    final t = SidebarCollapseScope.maybeOf(context) ?? 0.0;
    final fadeExpanded = (1 - t).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: fadeExpanded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: DashboardSidebarProfileCard(
            displayName: displayName,
            subtitle: context.select<AuthProvider, String>(
              (auth) => dashboardAccountPositionLabel(auth.user),
            ),
            avatarPath: avatarPath,
            onProfile: onProfile,
          ),
        ),
        Opacity(
          opacity: fadeExpanded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Text(
              "© $year HRMS · Mayor's Office",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 11,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hairline = AppTheme.dashHairlineOf(context);
    final canvas = AppTheme.dashCanvasOf(context);
    final panel = AppTheme.dashPanelOf(context);

    final content = Column(
      children: [
        if (railMode) SidebarRailHeader(onToggle: onToggle),
        if (!railMode && showBrand) const PortalSidebarBrand(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildNavList(context),
          ),
        ),
        _buildFooter(context),
      ],
    );

    if (railMode) {
      return AnimatedSidebarWidth(
        collapsed: collapsed,
        child: DashboardSidebarRailFrame(
          hairline: hairline,
          canvas: canvas,
          child: content,
        ),
      );
    }

    return Container(
      width: kDashboardSidebarExpandedWidth,
      color: panel,
      child: content,
    );
  }
}

class _MayorDashboardTab extends StatelessWidget {
  const _MayorDashboardTab({
    required this.dashboardFuture,
    required this.isMayor,
    required this.onRefresh,
    required this.onOpenRequest,
    required this.onOpenMeetings,
    required this.onOpenDecisions,
    required this.onOpenRequests,
    required this.onOpenHistory,
  });

  final Future<MayorDashboardData> dashboardFuture;
  final bool isMayor;
  final Future<void> Function() onRefresh;
  final ValueChanged<MayorDashListItem> onOpenRequest;
  final VoidCallback onOpenMeetings;
  final VoidCallback onOpenDecisions;
  final VoidCallback onOpenRequests;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final displayName = context.select<AuthProvider, String>(
      (a) => a.displayName.isNotEmpty
          ? a.displayName
          : (isMayor ? 'Mayor' : 'Staff'),
    );
    final banner = DashboardWelcomeBanner(
      portalLabel: isMayor ? 'Mayor Portal' : "Mayor's Office",
      displayName: displayName,
      description: isMayor
          ? "Here's the latest overview of endorsements and meetings for Plaridel."
          : "Here's the latest overview of Mayor's Office operations for Plaridel.",
    );

    return FutureBuilder<MayorDashboardData>(
      future: dashboardFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              banner,
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        if (snap.hasError || snap.data == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              banner,
              const SizedBox(height: 60),
              const Center(child: Text('Failed to load dashboard metrics.')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          );
        }
        final data = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            banner,
            const SizedBox(height: 16),
            MayorMonitoringDashboard(
          summary: data.toMonitoringSummary(),
          isMayor: isMayor,
          monthlyTrends: data.monthlyTrends,
          officeStatistics: data.officeStatistics
              .map(
                (o) => MayorOfficeShare(
                  officeName: o.officeName,
                  total: o.total,
                ),
              )
              .toList(),
          pendingMayorActions: data.pendingMayorActions,
          recentEndorsements: data.recentEndorsements,
          meetingQueue: data.meetingQueue,
          upcomingMeetings: data.upcomingMeetings,
          onRefresh: onRefresh,
          onOpenRequest: onOpenRequest,
          onOpenMeetings: onOpenMeetings,
          onOpenDecisions: onOpenDecisions,
          onOpenRequests: onOpenRequests,
          onOpenHistory: onOpenHistory,
            ),
          ],
        );
      },
    );
  }
}

class _MayorRequestsTab extends StatelessWidget {
  const _MayorRequestsTab({
    required this.title,
    required this.subtitle,
    required this.workspace,
    required this.capabilities,
    required this.loading,
    required this.submittingIntake,
    required this.requests,
    required this.search,
    required this.office,
    required this.status,
    required this.priority,
    required this.meetingRequestStatus,
    required this.fromDate,
    required this.toDate,
    required this.onSearchChanged,
    required this.onOfficeChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onMeetingRequestStatusChanged,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.onApplyFilters,
    required this.page,
    required this.totalPages,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onOpenIntakeForm,
    required this.onOpenRequest,
    required this.onApproveOfficeForm,
    required this.onApproveRequest,
    required this.onRejectRequest,
    required this.onScheduleMeeting,
    required this.onMarkNoShow,
    required this.onMarkMetMayor,
    required this.onApproveMeeting,
    required this.onRescheduleMeeting,
    required this.onDeclineMeeting,
  });

  final String title;
  final String subtitle;
  final _MayorMenu workspace;
  final _MayorPortalCapabilities capabilities;
  final bool loading;
  final bool submittingIntake;
  final MayorEndorsementListResponse requests;
  final String search;
  final String office;
  final String status;
  final String priority;
  final String meetingRequestStatus;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onOfficeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onPriorityChanged;
  final ValueChanged<String> onMeetingRequestStatusChanged;
  final ValueChanged<DateTime?> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final Future<void> Function() onApplyFilters;
  final int page;
  final int totalPages;
  final Future<void> Function() onPreviousPage;
  final Future<void> Function() onNextPage;
  final Future<void> Function() onOpenIntakeForm;
  final ValueChanged<MayorEndorsementRequest> onOpenRequest;
  final Future<void> Function(MayorEndorsementRequest item) onApproveOfficeForm;
  final Future<void> Function(MayorEndorsementRequest item) onApproveRequest;
  final Future<void> Function(MayorEndorsementRequest item) onRejectRequest;
  final Future<bool> Function(MayorEndorsementRequest item) onScheduleMeeting;
  final Future<bool> Function(MayorEndorsementRequest item) onMarkNoShow;
  final Future<bool> Function(MayorEndorsementRequest item) onMarkMetMayor;
  final Future<void> Function(MayorEndorsementRequest item) onApproveMeeting;
  final Future<void> Function(MayorEndorsementRequest item) onRescheduleMeeting;
  final Future<void> Function(MayorEndorsementRequest item) onDeclineMeeting;

  List<MayorEndorsementRequest> get _visibleItems {
    final items = requests.items;
    switch (workspace) {
      case _MayorMenu.meetings:
        return items
            .where(
              (i) =>
                  i.meetingRequestStatus == 'submitted' ||
                  i.meetingRequestStatus == 'approved' ||
                  i.meetingRequestStatus == 'reschedule_requested' ||
                  i.meetingRequestStatus == 'declined' ||
                  i.appointmentStatus == 'scheduled' ||
                  i.appointmentStatus == 'completed',
            )
            .toList();
      case _MayorMenu.decisions:
        return items
            .where(
              (i) =>
                  (i.status == 'pending' && i.hasMetMayor) ||
                  i.status == 'mayor_approved',
            )
            .toList();
      case _MayorMenu.scheduling:
        return items.where((i) => i.status == 'pending').toList();
      default:
        return items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final narrow = MediaQuery.sizeOf(context).width < 640;
    final showIntakeButton =
        capabilities.canCreateIntake && workspace == _MayorMenu.requests;
    final newButton = showIntakeButton
        ? FilledButton.icon(
            onPressed: submittingIntake ? null : onOpenIntakeForm,
            icon: submittingIntake
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded, size: 18),
            label: Text(submittingIntake ? 'Submitting...' : 'New Endorsement'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
          )
        : null;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: primary,
            fontSize: narrow ? 20 : 22,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: secondary, fontSize: 13.5, height: 1.35),
        ),
      ],
    );
    return Column(
      children: [
        if (narrow)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              if (newButton != null) ...[
                const SizedBox(height: 10),
                newButton,
              ],
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              if (newButton != null) ...[
                const SizedBox(width: 12),
                newButton,
              ],
            ],
          ),
        const SizedBox(height: 12),
        _FilterPanel(
          leading: workspace == _MayorMenu.meetings ||
                  workspace == _MayorMenu.scheduling
              ? _MayorMeetingStatusChips(
                  selected: meetingRequestStatus,
                  onSelected: (value) async {
                    onMeetingRequestStatusChanged(value);
                    await onApplyFilters();
                  },
                )
              : _MayorStatusChips(
                  selected: status,
                  onSelected: (value) async {
                    onStatusChanged(value);
                    await onApplyFilters();
                  },
                ),
          search: search,
          office: office,
          status: status,
          priority: priority,
          fromDate: fromDate,
          toDate: toDate,
          onSearchChanged: onSearchChanged,
          onOfficeChanged: onOfficeChanged,
          onStatusChanged: onStatusChanged,
          onPriorityChanged: onPriorityChanged,
          onFromDateChanged: onFromDateChanged,
          onToDateChanged: onToDateChanged,
          onApply: onApplyFilters,
          onResetExtras: () => onMeetingRequestStatusChanged(''),
        ),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_visibleItems.isEmpty)
          const _MayorEmptyState(
            icon: Icons.assignment_late_outlined,
            title: 'No endorsement requests found',
            subtitle: 'Try changing filters or wait for staff submissions.',
          )
        else
          _MayorSectionCard(
            title: switch (workspace) {
              _MayorMenu.meetings => 'Meeting Queue',
              _MayorMenu.decisions => 'Decision Queue',
              _MayorMenu.scheduling => 'Scheduling Queue',
              _ => 'Request Queue',
            },
            child: Column(
              children: [
                for (var i = 0; i < _visibleItems.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _MayorRequestCard(
                    item: _visibleItems[i],
                    workspace: workspace,
                    capabilities: capabilities,
                    onOpen: () => onOpenRequest(_visibleItems[i]),
                    onApproveOfficeForm: () =>
                        onApproveOfficeForm(_visibleItems[i]),
                    onApproveRequest: () =>
                        onApproveRequest(_visibleItems[i]),
                    onRejectRequest: () => onRejectRequest(_visibleItems[i]),
                    onScheduleMeeting: () =>
                        onScheduleMeeting(_visibleItems[i]),
                    onMarkNoShow: () => onMarkNoShow(_visibleItems[i]),
                    onMarkMetMayor: () => onMarkMetMayor(_visibleItems[i]),
                    onApproveMeeting: () =>
                        onApproveMeeting(_visibleItems[i]),
                    onRescheduleMeeting: () =>
                        onRescheduleMeeting(_visibleItems[i]),
                    onDeclineMeeting: () =>
                        onDeclineMeeting(_visibleItems[i]),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Page $page of $totalPages'),
            const SizedBox(width: 8),
            IconButton(
              onPressed: page > 1 ? onPreviousPage : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              onPressed: page < totalPages ? onNextPage : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _MayorRequestCard extends StatelessWidget {
  const _MayorRequestCard({
    required this.item,
    required this.workspace,
    required this.capabilities,
    required this.onOpen,
    required this.onApproveOfficeForm,
    required this.onApproveRequest,
    required this.onRejectRequest,
    required this.onScheduleMeeting,
    required this.onMarkNoShow,
    required this.onMarkMetMayor,
    required this.onApproveMeeting,
    required this.onRescheduleMeeting,
    required this.onDeclineMeeting,
  });

  final MayorEndorsementRequest item;
  final _MayorMenu workspace;
  final _MayorPortalCapabilities capabilities;
  final VoidCallback onOpen;
  final VoidCallback onApproveOfficeForm;
  final VoidCallback onApproveRequest;
  final VoidCallback onRejectRequest;
  final VoidCallback onScheduleMeeting;
  final VoidCallback onMarkNoShow;
  final VoidCallback onMarkMetMayor;
  final VoidCallback onApproveMeeting;
  final VoidCallback onRescheduleMeeting;
  final VoidCallback onDeclineMeeting;

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.dashTextPrimaryOf(context);
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final canEndorse = capabilities.canFinalDecide &&
        ((item.status == 'pending' && item.hasMetMayor) ||
            item.status == 'mayor_approved');
    final canReject = canEndorse;
    final canSubmitMeetingRequest = capabilities.canScheduleMeetings &&
        item.status == 'pending' &&
        item.canStaffSubmitMeetingRequest;
    final canAttendance = capabilities.canRecordAttendance &&
        item.status == 'pending' &&
        item.meetingRequestStatus == 'approved' &&
        (item.appointmentStatus == 'scheduled' ||
            item.appointmentStatus == 'no_show');
    final canMayorMeetingDecide = capabilities.canDecideMeetings &&
        item.meetingRequestStatus == 'submitted';
    final showDecisionActions =
        workspace == _MayorMenu.decisions || workspace == _MayorMenu.requests;
    final showMeetingDecideActions =
        workspace == _MayorMenu.meetings || workspace == _MayorMenu.requests;
    final showStaffScheduleActions =
        workspace == _MayorMenu.scheduling || workspace == _MayorMenu.requests;
    // Meetings: Mayor records attendance immediately after approve (early/sudden meet).
    final showAttendanceActions = canAttendance &&
        (workspace == _MayorMenu.scheduling ||
            workspace == _MayorMenu.requests ||
            workspace == _MayorMenu.meetings);
    final requester = (item.submittedByName ?? '').trim();
    final meeting = item.meetingProposedAt ?? item.appointmentAt;
    final noShow = item.appointmentStatus == 'no_show';
    final isScheduled = item.appointmentStatus == 'scheduled';

    return Material(
      color: AppTheme.dashPanelOf(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.dashHairlineOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.applicantName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          requester.isEmpty
                              ? 'Requested by: —'
                              : 'Requested by: $requester',
                          style: TextStyle(fontSize: 13, color: secondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.flowStepLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MayorMeetingOutcomePill(request: item),
                  const SizedBox(width: 8),
                  _MayorStatusPill(status: item.status),
                  const SizedBox(width: 8),
                  _MayorPriorityPill(priority: item.priority),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _MayorMetaChip(
                    icon: Icons.account_balance_outlined,
                    label: 'Office to enter',
                    value: item.endorseToOffice,
                  ),
                  _MayorMetaChip(
                    icon: Icons.gavel_rounded,
                    label: 'Endorsement',
                    value: item.decisionLabel,
                  ),
                  if ((item.referenceNumber ?? '').isNotEmpty)
                    _MayorMetaChip(
                      icon: Icons.tag_rounded,
                      label: 'Reference',
                      value: item.referenceNumber!,
                    ),
                  _MayorMetaChip(
                    icon: noShow
                        ? Icons.event_busy_rounded
                        : item.hasMetMayor
                        ? Icons.handshake_outlined
                        : Icons.event_available_rounded,
                    label: 'Meeting',
                    value: meeting == null
                        ? item.meetingRequestLabel
                        : '${item.meetingRequestLabel} · ${_fmtDateTime(meeting)}',
                  ),
                  if ((item.meetingPurpose ?? '').trim().isNotEmpty)
                    _MayorMetaChip(
                      icon: Icons.notes_rounded,
                      label: 'Purpose',
                      value: item.meetingPurpose!.trim(),
                    ),
                  if ((item.meetingDecisionRemarks ?? '').trim().isNotEmpty)
                    _MayorMetaChip(
                      icon: Icons.feedback_outlined,
                      label: 'Mayor remarks',
                      value: item.meetingDecisionRemarks!.trim(),
                    ),
                  if (item.noShowCount > 0)
                    _MayorMetaChip(
                      icon: Icons.warning_amber_rounded,
                      label: 'No-shows',
                      value: '${item.noShowCount}',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (showStaffScheduleActions && canSubmitMeetingRequest)
                    OutlinedButton.icon(
                      onPressed: onScheduleMeeting,
                      icon: Icon(
                        item.meetingRequestStatus == 'reschedule_requested' ||
                                noShow
                            ? Icons.event_repeat_rounded
                            : Icons.event_rounded,
                        size: 18,
                      ),
                      label: Text(
                        item.meetingRequestStatus == 'reschedule_requested'
                            ? 'Submit revised schedule'
                            : item.meetingRequestStatus == 'declined' || noShow
                            ? 'New meeting request'
                            : 'Submit meeting request',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryNavy,
                        side: const BorderSide(color: AppTheme.primaryNavy),
                      ),
                    ),
                  if (showAttendanceActions && isScheduled) ...[
                    FilledButton.icon(
                      onPressed: onMarkMetMayor,
                      icon: const Icon(Icons.handshake_outlined, size: 18),
                      label: const Text('Met the Mayor'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onMarkNoShow,
                      icon: const Icon(Icons.event_busy_rounded, size: 18),
                      label: const Text('Did not appear'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryNavy,
                      ),
                    ),
                  ],
                  if (showMeetingDecideActions && canMayorMeetingDecide) ...[
                    FilledButton.icon(
                      onPressed: onApproveMeeting,
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: const Text('Approve meeting'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onRescheduleMeeting,
                      icon: const Icon(Icons.event_repeat_rounded, size: 18),
                      label: const Text('Request reschedule'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryNavy,
                        side: const BorderSide(color: AppTheme.primaryNavy),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onDeclineMeeting,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Decline meeting'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC62828),
                        side: const BorderSide(color: Color(0xFFC62828)),
                      ),
                    ),
                  ],
                  if (showDecisionActions && canEndorse)
                    FilledButton.icon(
                      onPressed: onApproveRequest,
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Endorse'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryNavy,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (showDecisionActions && canReject)
                    OutlinedButton.icon(
                      onPressed: onRejectRequest,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC62828),
                        side: const BorderSide(color: Color(0xFFC62828)),
                      ),
                    ),
                  TextButton(
                    onPressed: onOpen,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                    ),
                    child: const Text('View details'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MayorMetaChip extends StatelessWidget {
  const _MayorMetaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryNavy),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.dashTextSecondaryOf(context),
                  ),
                ),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.dashTextPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MayorHistoryTab extends StatelessWidget {
  const _MayorHistoryTab({
    required this.history,
    required this.loading,
    required this.search,
    required this.office,
    required this.status,
    required this.fromDate,
    required this.toDate,
    required this.onSearchChanged,
    required this.onOfficeChanged,
    required this.onStatusChanged,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.onApplyFilters,
    required this.onClearFilters,
    required this.onDatePreset,
    required this.onOpenRequest,
    required this.onRefresh,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final MayorEndorsementListResponse history;
  final bool loading;
  final String search;
  final String office;
  final String status;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onOfficeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<DateTime?> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final Future<void> Function() onApplyFilters;
  final VoidCallback onClearFilters;
  final ValueChanged<String> onDatePreset;
  final ValueChanged<MayorEndorsementRequest> onOpenRequest;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onPreviousPage;
  final Future<void> Function() onNextPage;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Endorsement History',
                    style: TextStyle(
                      color: AppTheme.dashTextPrimaryOf(context),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Search and filter processed endorsements. Official letters are preserved.',
                    style: TextStyle(
                      color: AppTheme.dashTextSecondaryOf(context),
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : onRefresh,
              icon: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(loading ? 'Loading...' : 'Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _HistoryFilterBar(
          narrow: narrow,
          loading: loading,
          search: search,
          office: office,
          status: status,
          fromDate: fromDate,
          toDate: toDate,
          onSearchChanged: onSearchChanged,
          onOfficeChanged: onOfficeChanged,
          onStatusChanged: onStatusChanged,
          onFromDateChanged: onFromDateChanged,
          onToDateChanged: onToDateChanged,
          onDatePreset: onDatePreset,
          onApply: onApplyFilters,
          onClear: onClearFilters,
        ),
        const SizedBox(height: 10),
        if (loading && history.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (history.items.isEmpty)
          const _MayorEmptyState(
            icon: Icons.history_toggle_off_rounded,
            title: 'No matching endorsement history',
            subtitle:
                'Try clearing filters or adjusting the date range. Empty periods show zero results by design.',
          )
        else
          _MayorSectionCard(
            title: 'Processed Endorsements',
            child: narrow
                ? Column(
                    children: [
                      for (final item in history.items)
                        _MayorHistoryMobileCard(
                          item: item,
                          onTap: () => onOpenRequest(item),
                        ),
                    ],
                  )
                : Column(
                    children: [
                      _MayorTableHeader(
                        columns: const [
                          'Applicant / Ref',
                          'Destination Office',
                          'Status',
                          'Endorsement / Decision Date',
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (var i = 0; i < history.items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        Builder(
                          builder: (_) {
                            final item = history.items[i];
                            final processed =
                                item.rejectedAt ??
                                item.officeFormApprovedAt ??
                                item.approvedAt ??
                                item.submittedAt;
                            final ref = (item.referenceNumber ?? '').trim();
                            return InkWell(
                              onTap: () => onOpenRequest(item),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.applicantName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            ref.isNotEmpty
                                                ? ref
                                                : item.applicationId,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(item.endorseToOffice),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: _MayorStatusPill(
                                          status: item.status,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          _fmtDateTime(processed),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Page ${history.page} of ${history.totalPages}'),
            const SizedBox(width: 8),
            IconButton(
              onPressed: history.page > 1 && !loading ? onPreviousPage : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              onPressed: history.page < history.totalPages && !loading
                  ? onNextPage
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _MayorMeetingStatusChips extends StatelessWidget {
  const _MayorMeetingStatusChips({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _MayorFilterPills(
      selected: selected,
      onSelected: onSelected,
      options: const [
        ('', 'All meetings'),
        ('submitted', 'Pending Mayor'),
        ('approved', 'Approved'),
        ('reschedule_requested', 'Reschedule'),
        ('declined', 'Declined'),
      ],
    );
  }
}

class _MayorStatusChips extends StatelessWidget {
  const _MayorStatusChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _MayorFilterPills(
      selected: selected,
      onSelected: onSelected,
      options: const [
        ('', 'All'),
        ('pending', 'Needs Action'),
        ('mayor_approved', 'Awaiting Office Form'),
        ('endorsed', 'Endorsed'),
        ('rejected', 'Rejected'),
      ],
    );
  }
}

class _MayorHistoryMobileCard extends StatelessWidget {
  const _MayorHistoryMobileCard({required this.item, required this.onTap});

  final MayorEndorsementRequest item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final processed =
        item.rejectedAt ??
        item.officeFormApprovedAt ??
        item.approvedAt ??
        item.submittedAt;
    final office = item.officeName.isEmpty ? 'Unassigned' : item.officeName;
    final secondary = AppTheme.dashTextSecondaryOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.dashCanvasOf(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.applicantName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(office, style: TextStyle(fontSize: 13, color: secondary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MayorMeetingOutcomePill(request: item),
                    const SizedBox(width: 6),
                    _MayorStatusPill(status: item.status),
                    const Spacer(),
                    Text(
                      _fmtShortDate(processed.toLocal()),
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MayorFilterPills extends StatelessWidget {
  const _MayorFilterPills({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: selected == option.$1
                    ? AppTheme.primaryNavy
                    : AppTheme.dashCanvasOf(context),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () => onSelected(option.$1),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected == option.$1
                            ? AppTheme.primaryNavy
                            : AppTheme.dashHairlineOf(context),
                      ),
                    ),
                    child: Text(
                      option.$2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected == option.$1
                            ? Colors.white
                            : AppTheme.dashTextSecondaryOf(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterPanel extends StatefulWidget {
  const _FilterPanel({
    required this.search,
    required this.office,
    required this.status,
    required this.priority,
    required this.fromDate,
    required this.toDate,
    required this.onSearchChanged,
    required this.onOfficeChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.onApply,
    this.leading,
    this.onResetExtras,
  });

  final Widget? leading;
  final VoidCallback? onResetExtras;
  final String search;
  final String office;
  final String status;
  final String priority;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onOfficeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onPriorityChanged;
  final ValueChanged<DateTime?> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final Future<void> Function() onApply;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.search,
  );
  late final TextEditingController _officeController = TextEditingController(
    text: widget.office,
  );

  InputDecoration _field(BuildContext context, String hint, {Widget? icon}) {
    final radius = BorderRadius.circular(10);
    final side = BorderSide(color: AppTheme.dashHairlineOf(context));
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon,
      isDense: true,
      filled: true,
      fillColor: AppTheme.dashCanvasOf(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: radius, borderSide: side),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: side),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppTheme.primaryNavy),
      ),
    );
  }

  ButtonStyle get _dateStyle => OutlinedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    foregroundColor: AppTheme.primaryNavy,
    side: const BorderSide(color: AppTheme.primaryNavy),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  decoration: _field(
                    context,
                    'Search applicant',
                    icon: const Icon(Icons.search_rounded, size: 18),
                  ),
                  onSubmitted: (_) async {
                    widget.onSearchChanged(_searchController.text.trim());
                    widget.onOfficeChanged(_officeController.text.trim());
                    await widget.onApply();
                  },
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _officeController,
                  decoration: _field(context, 'Office'),
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  initialValue: widget.status.isEmpty ? '' : widget.status,
                  isExpanded: true,
                  decoration: _field(context, 'Status'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Status · All')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'mayor_approved',
                      child: Text('Office form'),
                    ),
                    DropdownMenuItem(value: 'endorsed', child: Text('Endorsed')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  ],
                  onChanged: (v) => widget.onStatusChanged(v ?? ''),
                ),
              ),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  initialValue: widget.priority.isEmpty ? '' : widget.priority,
                  isExpanded: true,
                  decoration: _field(context, 'Priority'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Priority · All')),
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (v) => widget.onPriorityChanged(v ?? ''),
                ),
              ),
              OutlinedButton.icon(
                style: _dateStyle,
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  widget.fromDate == null
                      ? 'From'
                      : _fmtDateOnly(widget.fromDate!),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: widget.fromDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) widget.onFromDateChanged(picked);
                },
              ),
              OutlinedButton.icon(
                style: _dateStyle,
                icon: const Icon(Icons.event_rounded, size: 16),
                label: Text(
                  widget.toDate == null ? 'To' : _fmtDateOnly(widget.toDate!),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: widget.toDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) widget.onToDateChanged(picked);
                },
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Apply'),
                onPressed: () async {
                  widget.onSearchChanged(_searchController.text.trim());
                  widget.onOfficeChanged(_officeController.text.trim());
                  await widget.onApply();
                },
              ),
              TextButton(
                onPressed: () async {
                  _searchController.clear();
                  _officeController.clear();
                  widget.onSearchChanged('');
                  widget.onOfficeChanged('');
                  widget.onStatusChanged('');
                  widget.onPriorityChanged('');
                  widget.onFromDateChanged(null);
                  widget.onToDateChanged(null);
                  widget.onResetExtras?.call();
                  await widget.onApply();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
    required this.narrow,
    required this.loading,
    required this.search,
    required this.office,
    required this.status,
    required this.fromDate,
    required this.toDate,
    required this.onSearchChanged,
    required this.onOfficeChanged,
    required this.onStatusChanged,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.onDatePreset,
    required this.onApply,
    required this.onClear,
  });

  final bool narrow;
  final bool loading;
  final String search;
  final String office;
  final String status;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onOfficeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<DateTime?> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final ValueChanged<String> onDatePreset;
  final Future<void> Function() onApply;
  final VoidCallback onClear;

  String get _preset {
    if (fromDate == null && toDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = fromDate == null
        ? null
        : DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
    final to = toDate == null
        ? null
        : DateTime(toDate!.year, toDate!.month, toDate!.day);
    if (from == today && to == today) return 'today';
    final weekStart = today.subtract(
      Duration(days: (today.weekday - DateTime.monday) % 7),
    );
    if (from == weekStart && to == today) return 'week';
    if (from == DateTime(today.year, today.month, 1) && to == today) {
      return 'month';
    }
    return 'custom';
  }

  @override
  Widget build(BuildContext context) {
    final fieldWidth = narrow ? double.infinity : 220.0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MayorFilterPills(
            selected: _preset == 'custom' ? '__none__' : _preset,
            onSelected: onDatePreset,
            options: const [
              ('', 'All dates'),
              ('today', 'Today'),
              ('week', 'This week'),
              ('month', 'This month'),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: fieldWidth,
                child: TextFormField(
                  initialValue: search,
                  decoration: _historyField(
                    context,
                    'Applicant or reference',
                    icon: const Icon(Icons.search_rounded, size: 18),
                  ),
                  onChanged: onSearchChanged,
                  onFieldSubmitted: (_) => onApply(),
                ),
              ),
              SizedBox(
                width: narrow ? double.infinity : 180,
                child: TextFormField(
                  initialValue: office,
                  decoration: _historyField(context, 'Destination office'),
                  onChanged: onOfficeChanged,
                  onFieldSubmitted: (_) => onApply(),
                ),
              ),
              SizedBox(
                width: narrow ? double.infinity : 150,
                child: DropdownButtonFormField<String>(
                  initialValue: status.isEmpty ? '' : status,
                  isExpanded: true,
                  decoration: _historyField(context, 'Status'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Status · All')),
                    DropdownMenuItem(value: 'endorsed', child: Text('Endorsed')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  ],
                  onChanged: loading ? null : (v) => onStatusChanged(v ?? ''),
                ),
              ),
              OutlinedButton.icon(
                style: _historyDateStyle,
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: fromDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) onFromDateChanged(picked);
                },
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  fromDate == null ? 'From' : _fmtDateOnly(fromDate!),
                ),
              ),
              OutlinedButton.icon(
                style: _historyDateStyle,
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: toDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) onToDateChanged(picked);
                },
                icon: const Icon(Icons.event_rounded, size: 16),
                label: Text(toDate == null ? 'To' : _fmtDateOnly(toDate!)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: loading ? null : onApply,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Apply'),
              ),
              TextButton(
                onPressed: loading ? null : onClear,
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

InputDecoration _historyField(BuildContext context, String hint, {Widget? icon}) {
  final radius = BorderRadius.circular(10);
  final side = BorderSide(color: AppTheme.dashHairlineOf(context));
  return InputDecoration(
    hintText: hint,
    prefixIcon: icon,
    isDense: true,
    filled: true,
    fillColor: AppTheme.dashCanvasOf(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: radius, borderSide: side),
    enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: side),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppTheme.primaryNavy),
    ),
  );
}

ButtonStyle get _historyDateStyle => OutlinedButton.styleFrom(
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  foregroundColor: AppTheme.primaryNavy,
  side: const BorderSide(color: AppTheme.primaryNavy),
);

class _MayorEndorsementIntakeDialog extends StatefulWidget {
  const _MayorEndorsementIntakeDialog();

  @override
  State<_MayorEndorsementIntakeDialog> createState() =>
      _MayorEndorsementIntakeDialogState();
}

class _MayorEndorsementIntakeDialogState
    extends State<_MayorEndorsementIntakeDialog> {
  String _priority = 'normal';
  String? _requestedOfficeName;
  final _lastNameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _designationCtrl = TextEditingController();
  final _agencyCtrl = TextEditingController();
  final _serviceCtrl = TextEditingController();
  final _currentWorkAddressCtrl = TextEditingController();
  final _prcCscCtrl = TextEditingController();
  final _rankCodeCtrl = TextEditingController();
  final _staffNotesCtrl = TextEditingController();

  final _homeStreetCtrl = TextEditingController();
  final _schoolStreetCtrl = TextEditingController();
  final GlobalKey<StructuredAddressFormState> _homeAddressKey =
      GlobalKey<StructuredAddressFormState>();
  final GlobalKey<StructuredAddressFormState> _schoolAddressKey =
      GlobalKey<StructuredAddressFormState>();

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    border: const OutlineInputBorder(),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  MayorIntakeFormData _buildIntakeFromInputs() {
    return MayorIntakeFormData(
      lastName: _lastNameCtrl.text,
      firstName: _firstNameCtrl.text,
      middleNameOrInitial: _middleCtrl.text,
      address: _homeAddressKey.currentState?.composeEncoded() ?? '',
      course: _courseCtrl.text,
      schoolAddress: _schoolAddressKey.currentState?.composeEncoded() ?? '',
      positionApplyingFor: _positionCtrl.text,
      currentWorkDesignation: _designationCtrl.text,
      agencyCompany: _agencyCtrl.text,
      noOfService: _serviceCtrl.text,
      currentWorkAddress: _currentWorkAddressCtrl.text,
      prcCscNo: _prcCscCtrl.text,
      rankAndCode: _rankCodeCtrl.text,
    );
  }

  Future<void> _previewSubmission() async {
    final intake = _buildIntakeFromInputs();
    final missing = intake.firstMissingLabel();
    if (missing != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please fill in: $missing')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Review Before Submit'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewRow('Last Name', intake.lastName),
                _previewRow('First Name', intake.firstName),
                _previewRow(
                  'Middle Name / Initial',
                  intake.middleNameOrInitial,
                ),
                _previewRow('Address', intake.address),
                _previewRow('Course', intake.course),
                _previewRow('School Address', intake.schoolAddress),
                _previewRow(
                  'Position Applying For',
                  intake.positionApplyingFor,
                ),
                _previewRow(
                  'Current Work / Designation',
                  intake.currentWorkDesignation,
                ),
                _previewRow('Agency / Company', intake.agencyCompany),
                _previewRow('No. of Service', intake.noOfService),
                _previewRow('Add. sa Current Work', intake.currentWorkAddress),
                _previewRow('PRC No. / CSC No.', intake.prcCscNo),
                _previewRow('Rank and Code', intake.rankAndCode),
                _previewRow('Office to endorse', _requestedOfficeName ?? ''),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value.trim().isEmpty ? '-' : value.trim()),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _lastNameCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleCtrl.dispose();
    _courseCtrl.dispose();
    _positionCtrl.dispose();
    _designationCtrl.dispose();
    _agencyCtrl.dispose();
    _serviceCtrl.dispose();
    _currentWorkAddressCtrl.dispose();
    _prcCscCtrl.dispose();
    _rankCodeCtrl.dispose();
    _staffNotesCtrl.dispose();
    _homeStreetCtrl.dispose();
    _schoolStreetCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final intake = _buildIntakeFromInputs();
    final missing = intake.firstMissingLabel();
    if (missing != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please fill in: $missing')));
      return;
    }

    if ((_requestedOfficeName ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select the office the applicant will be endorsed to.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      MayorEndorsementIntakeSubmission(
        priority: _priority,
        intakeForm: intake,
        staffNotes: _staffNotesCtrl.text.trim().isEmpty
            ? null
            : _staffNotesCtrl.text.trim(),
        requestedOfficeName: _requestedOfficeName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogW = (screen.width - 32).clamp(280.0, 1000.0);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: screen.width < 640 ? 12 : 24,
        vertical: 16,
      ),
      title: const Text('Endorsement Intake Form'),
      content: SizedBox(
        width: dialogW,
        height: screen.height * (screen.width < 640 ? 0.62 : 0.72),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Required: Last Name, First Name, Address, Course, and School Address. '
                'Middle name and work/PRC fields are optional.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Submission Details',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _requestedOfficeName,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText:
                              'Office to endorse (papasukan ng applicant)',
                          hintText: 'Select office',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: [
                          for (final office in kMayorEndorsementOffices)
                            DropdownMenuItem(
                              value: office,
                              child: Text(
                                office,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _requestedOfficeName = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Applicant Information',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      _gridTwo(
                        TextField(
                          controller: _lastNameCtrl,
                          decoration: _dec('Last Name'),
                        ),
                        TextField(
                          controller: _firstNameCtrl,
                          decoration: _dec('First Name'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _middleCtrl,
                        decoration: _dec('Middle Name / Middle Initial'),
                      ),
                      const SizedBox(height: 10),
                      _buildCourseField(),
                      const SizedBox(height: 14),
                      StructuredAddressForm(
                        key: _homeAddressKey,
                        streetController: _homeStreetCtrl,
                        initialRawAddress: null,
                        inputDecoration: _dec,
                        sectionLabel: 'Address',
                      ),
                      const SizedBox(height: 14),
                      StructuredAddressForm(
                        key: _schoolAddressKey,
                        streetController: _schoolStreetCtrl,
                        initialRawAddress: null,
                        inputDecoration: _dec,
                        sectionLabel: 'School Address',
                      ),
                      const SizedBox(height: 10),
                      _gridTwo(
                        TextField(
                          controller: _positionCtrl,
                          decoration: _dec('Position Applying for'),
                        ),
                        TextField(
                          controller: _designationCtrl,
                          decoration: _dec('Current Work / Designation'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _gridTwo(
                        TextField(
                          controller: _agencyCtrl,
                          decoration: _dec('Agency / Company'),
                        ),
                        TextField(
                          controller: _serviceCtrl,
                          decoration: _dec('No. of Service'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _gridTwo(
                        TextField(
                          controller: _currentWorkAddressCtrl,
                          decoration: _dec('Add. sa Current Work'),
                        ),
                        TextField(
                          controller: _prcCscCtrl,
                          decoration: _dec('Prc No. / CSC No.'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _rankCodeCtrl,
                        decoration: _dec('Rank and Code'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _staffNotesCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: _dec(
                  'Recommendations / Notes for Mayor (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _previewSubmission,
          icon: const Icon(Icons.preview_rounded),
          label: const Text('Preview Details'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_rounded),
          label: const Text('Submit for Review'),
        ),
      ],
    );
  }

  Widget _gridTwo(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(children: [a, const SizedBox(height: 10), b]);
        }
        return Row(
          children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  Widget _buildCourseField() {
    return SearchableDropdownField(
      options: kPhilippineCourses,
      value: _courseCtrl.text,
      allowCustom: true,
      searchText: philippineCourseSearchText,
      textCapitalization: TextCapitalization.words,
      decoration: _dec('Search or type a course'),
      onChanged: (value) {
        final next = value ?? '';
        if (_courseCtrl.text == next) return;
        _courseCtrl.text = next;
      },
    );
  }
}

class _MayorReviewDialog extends StatefulWidget {
  const _MayorReviewDialog({
    required this.details,
    required this.canScheduleMeetings,
    required this.canRecordAttendance,
    required this.canFinalDecide,
    this.onScheduleMeeting,
    this.onMarkNoShow,
    this.onMarkMetMayor,
  });

  final MayorEndorsementDetails details;
  final bool canScheduleMeetings;
  final bool canRecordAttendance;
  final bool canFinalDecide;
  final Future<bool> Function()? onScheduleMeeting;
  final Future<bool> Function()? onMarkNoShow;
  final Future<bool> Function()? onMarkMetMayor;

  @override
  State<_MayorReviewDialog> createState() => _MayorReviewDialogState();
}

class _MayorReviewDialogState extends State<_MayorReviewDialog> {
  final _destinationCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _loadingOffices = false;
  List<_MayorOfficeOption> _offices = const [];
  String? _selectedDestinationOfficeId;

  bool get _canEditDecisionFields {
    if (!widget.canFinalDecide) return false;
    final req = widget.details.request;
    return (req.status == 'pending' && req.hasMetMayor) ||
        req.status == 'mayor_approved';
  }

  bool get _awaitingMeeting {
    final req = widget.details.request;
    return req.status == 'pending' && !req.hasMetMayor;
  }

  @override
  void initState() {
    super.initState();
    final req = widget.details.request;
    final fallbackOffice = req.endorseToOffice;
    _destinationCtrl.text = (req.destinationOfficeName ?? '').trim().isNotEmpty
        ? req.destinationOfficeName!.trim()
        : (req.requestedOfficeName ?? '').trim().isNotEmpty
        ? req.requestedOfficeName!.trim()
        : (fallbackOffice == 'Unassigned' ? '' : fallbackOffice);
    _remarksCtrl.text = req.mayorRemarks ?? '';
    _reasonCtrl.text = req.rejectionReason ?? '';
    _selectedDestinationOfficeId = req.destinationOfficeId;
    _loadOffices();
  }

  Future<void> _loadOffices() async {
    setState(() => _loadingOffices = true);
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/offices',
        queryParameters: const {'status': 'Active'},
      );
      final parsed = (res.data ?? const [])
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            return _MayorOfficeOption(
              id: (m['id'] ?? '').toString(),
              name: (m['name'] ?? '').toString().trim(),
            );
          })
          .where((o) => o.id.isNotEmpty && o.name.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _offices = parsed;
        if ((_selectedDestinationOfficeId ?? '').isEmpty) {
          final typed = _destinationCtrl.text.trim().toLowerCase();
          for (final o in parsed) {
            if (o.name.toLowerCase() == typed) {
              _selectedDestinationOfficeId = o.id;
              break;
            }
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _offices = const []);
    } finally {
      if (mounted) setState(() => _loadingOffices = false);
    }
  }

  void _applyDestinationOffice(_MayorOfficeOption? office, {String? typed}) {
    if (office != null) {
      _selectedDestinationOfficeId = office.id;
      _destinationCtrl.text = office.name;
      return;
    }
    final name = (typed ?? _destinationCtrl.text).trim();
    _destinationCtrl.text = name;
    String? matchedId;
    for (final o in _offices) {
      if (o.name.toLowerCase() == name.toLowerCase()) {
        matchedId = o.id;
        break;
      }
    }
    _selectedDestinationOfficeId = matchedId;
  }

  String? _validateDecisionFields({required bool requireDestination}) {
    if (!_canEditDecisionFields) return null;
    if (requireDestination && _destinationCtrl.text.trim().isEmpty) {
      final fallback = widget.details.request.endorseToOffice;
      if (fallback.isNotEmpty && fallback != 'Unassigned') {
        _destinationCtrl.text = fallback;
        return null;
      }
      return 'Please enter the Destination Office before continuing.';
    }
    return null;
  }

  void _showFieldError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _destinationCtrl.dispose();
    _remarksCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.details.request;
    final applicant = widget.details.applicant;
    final canMayorApprove = widget.canFinalDecide &&
        req.status == 'pending' &&
        req.hasMetMayor;
    final canOfficeApproveForm =
        widget.canFinalDecide && req.status == 'mayor_approved';
    final canReject = canMayorApprove || canOfficeApproveForm;
    final statusColor = _statusColor(req.status);
    final priorityColor = _priorityColor(req.priority);
    final screen = MediaQuery.sizeOf(context);
    final insetH = screen.width < 640 ? 10.0 : 20.0;
    final insetV = screen.height < 700 ? 10.0 : 18.0;
    final dialogH = (screen.height - insetV * 2 - 8).clamp(280.0, 760.0);
    final dialogW = (screen.width - insetH * 2 - 8).clamp(260.0, 1000.0);

    InputDecoration fieldDec({
      required String label,
      String? helper,
      String? hint,
      IconData? icon,
      bool? editable,
    }) {
      final canType = editable ?? _canEditDecisionFields;
      return InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 20, color: AppTheme.primaryNavy),
        prefixIconColor: AppTheme.primaryNavy,
        filled: true,
        fillColor: canType ? Colors.white : const Color(0xFFFAFBFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: canType ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFECEFF3)),
        ),
      );
    }

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: insetH, vertical: insetV),
      backgroundColor: Colors.transparent,
      child: Material(
        color: const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        elevation: 12,
        shadowColor: Colors.black26,
        child: SizedBox(
          width: dialogW,
          height: dialogH,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primaryNavyDark, AppTheme.primaryNavy],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.gavel_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mayor Endorsement Review',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${applicant.fullName.isNotEmpty ? applicant.fullName : req.applicantName}'
                            '  ·  ${req.applicationId}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _chip(
                      req.statusLabel,
                      bg: statusColor.withValues(alpha: 0.22),
                      fg: Colors.white,
                      border: statusColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    _chip(
                      'Priority: ${_cap(req.priority)}',
                      bg: priorityColor.withValues(alpha: 0.22),
                      fg: Colors.white,
                      border: priorityColor.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
              _ReviewWorkflowStrip(request: req),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: _MayorReviewSummaryBar(
                  request: req,
                  onMarkMetMayor: _awaitingMeeting &&
                          widget.canRecordAttendance &&
                          widget.onMarkMetMayor != null &&
                          req.meetingRequestStatus == 'approved' &&
                          (req.appointmentStatus == 'scheduled' ||
                              req.appointmentStatus == 'no_show')
                      ? () async {
                          final ok = await widget.onMarkMetMayor!();
                          if (ok && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        }
                      : null,
                  onScheduleMeeting: _awaitingMeeting &&
                          widget.canScheduleMeetings &&
                          widget.onScheduleMeeting != null
                      ? () async {
                          final ok = await widget.onScheduleMeeting!();
                          if (ok && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        }
                      : null,
                  onMarkNoShow: _awaitingMeeting &&
                          widget.canRecordAttendance &&
                          widget.onMarkNoShow != null &&
                          req.meetingRequestStatus == 'approved' &&
                          req.appointmentStatus == 'scheduled'
                      ? () async {
                          final ok = await widget.onMarkNoShow!();
                          if (ok && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        }
                      : null,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  children: [
                    _sectionCard(
                      title: 'I. Personal Information',
                      icon: Icons.badge_outlined,
                      child: _detailGrid([
                        _kv('Last Name', req.intakeForm.lastName),
                        _kv('First Name', req.intakeForm.firstName),
                        _kv(
                          'Middle Name / Initial',
                          req.intakeForm.middleNameOrInitial,
                        ),
                        _kv(
                          'Home Address',
                          _formatAddressForDisplay(req.intakeForm.address),
                          wide: true,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: 'II. Education & Position Sought',
                      icon: Icons.school_outlined,
                      child: _detailGrid([
                        _kv('Course', req.intakeForm.course, wide: true),
                        _kv(
                          'School Address',
                          _formatAddressForDisplay(
                            req.intakeForm.schoolAddress,
                          ),
                          wide: true,
                        ),
                        _kv(
                          'Position Applying For',
                          req.intakeForm.positionApplyingFor,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: 'III. Employment & Credentials',
                      icon: Icons.work_outline_rounded,
                      child: _detailGrid([
                        _kv(
                          'Current Work / Designation',
                          req.intakeForm.currentWorkDesignation,
                        ),
                        _kv('Agency / Company', req.intakeForm.agencyCompany),
                        _kv('No. of Service', req.intakeForm.noOfService),
                        _kv(
                          'Current Work Address',
                          req.intakeForm.currentWorkAddress,
                          wide: true,
                        ),
                        _kv('PRC No. / CSC No.', req.intakeForm.prcCscNo),
                        _kv('Rank and Code', req.intakeForm.rankAndCode),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: 'IV. Official Review & Decision',
                      icon: Icons.rate_review_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Staff recommendations',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  req.staffNotes?.trim().isEmpty ?? true
                                      ? 'No staff recommendations or notes were provided with this submission.'
                                      : req.staffNotes!,
                                  style: TextStyle(
                                    height: 1.45,
                                    color:
                                        (req.staffNotes?.trim().isEmpty ?? true)
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF1E293B),
                                    fontStyle:
                                        (req.staffNotes?.trim().isEmpty ?? true)
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_awaitingMeeting) ...[
                            Text(
                              'Step 2: the applicant must talk to / see the Mayor first. '
                              'If they already met, tap Met the Mayor. If not, schedule a meeting. '
                              'Approve or reject is available only after the meeting.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (canMayorApprove) ...[
                            Text(
                              'Step 3: they already met the Mayor. Enter Destination Office and remarks, then approve or reject.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (canOfficeApproveForm) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFA5D6A7),
                                ),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.verified_outlined,
                                    color: Color(0xFF2E7D32),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Municipal Mayor has approved this request. '
                                      'Fill in Destination Office and endorsement remarks/instructions, '
                                      'then approve the form to finalize and generate the letter.',
                                      style: TextStyle(height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Autocomplete<_MayorOfficeOption>(
                            initialValue: TextEditingValue(
                              text: _destinationCtrl.text,
                            ),
                            displayStringForOption: (o) => o.name,
                            optionsBuilder: (textEditingValue) {
                              final q = textEditingValue.text
                                  .trim()
                                  .toLowerCase();
                              if (q.isEmpty) return _offices;
                              return _offices.where(
                                (o) => o.name.toLowerCase().contains(q),
                              );
                            },
                            onSelected: (office) {
                              setState(() => _applyDestinationOffice(office));
                            },
                            fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
                              if (textCtrl.text != _destinationCtrl.text) {
                                textCtrl.value = TextEditingValue(
                                  text: _destinationCtrl.text,
                                  selection: TextSelection.collapsed(
                                    offset: _destinationCtrl.text.length,
                                  ),
                                );
                              }
                              return TextField(
                                controller: textCtrl,
                                focusNode: focusNode,
                                enabled: _canEditDecisionFields,
                                textInputAction: TextInputAction.next,
                                onChanged: (v) {
                                  setState(
                                    () =>
                                        _applyDestinationOffice(null, typed: v),
                                  );
                                },
                                decoration: fieldDec(
                                  label: 'Destination Office',
                                  hint: _loadingOffices
                                      ? 'Loading offices…'
                                      : 'Type or select the receiving office',
                                  helper: _canEditDecisionFields
                                      ? (canOfficeApproveForm
                                            ? 'Required before Mayor\'s Office form approval'
                                            : 'Office where the endorsed applicant will be assigned')
                                      : null,
                                  icon: Icons.account_balance_outlined,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _remarksCtrl,
                            enabled: widget.canFinalDecide,
                            readOnly: !widget.canFinalDecide,
                            minLines: 3,
                            maxLines: 6,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            decoration: fieldDec(
                              label: 'Endorsement Remarks / Instructions',
                              hint: 'Type remarks or instructions',
                              helper: widget.canFinalDecide
                                  ? 'Optional. Saved when you endorse.'
                                  : null,
                              editable: widget.canFinalDecide,
                            ),
                          ),
                          if (canReject) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _reasonCtrl,
                              enabled: true,
                              minLines: 2,
                              maxLines: 4,
                              decoration: fieldDec(
                                label: 'Rejection Reason (optional)',
                                hint: 'Optional note',
                                helper: 'Optional when rejecting',
                                icon: Icons.report_gmailerrorred_outlined,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.white,
                elevation: 8,
                shadowColor: Colors.black26,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_awaitingMeeting ||
                          canMayorApprove ||
                          canOfficeApproveForm)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _awaitingMeeting
                                ? 'Step 2: record Met the Mayor, or schedule if they have not appeared yet.'
                                : canMayorApprove
                                ? 'Step 3: enter Destination Office, then approve or reject.'
                                : 'Scroll to Section IV, confirm Destination Office and remarks, then approve the form.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: Colors.blueGrey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primaryNavy,
                            ),
                            child: const Text('Close'),
                          ),
                          if (canReject)
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(
                                _ReviewActionResult(
                                  action: _ReviewAction.reject,
                                  reason: _reasonCtrl.text.trim(),
                                ),
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFC62828),
                                side: const BorderSide(
                                  color: Color(0xFFC62828),
                                ),
                              ),
                              label: const Text('Reject'),
                            ),
                          if (canMayorApprove)
                            FilledButton.icon(
                              onPressed: () {
                                final err = _validateDecisionFields(
                                  requireDestination: true,
                                );
                                if (err != null) {
                                  _showFieldError(err);
                                  return;
                                }
                                Navigator.of(context).pop(
                                  _ReviewActionResult(
                                    action: _ReviewAction.approve,
                                    destinationOfficeId:
                                        _selectedDestinationOfficeId,
                                    destinationOfficeName: _destinationCtrl.text
                                        .trim(),
                                    remarks: _remarksCtrl.text.trim(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.how_to_reg_rounded),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primaryNavy,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              label: const Text('Endorse'),
                            ),
                          if (canOfficeApproveForm)
                            FilledButton.icon(
                              onPressed: () {
                                final err = _validateDecisionFields(
                                  requireDestination: true,
                                );
                                if (err != null) {
                                  _showFieldError(err);
                                  return;
                                }
                                Navigator.of(context).pop(
                                  _ReviewActionResult(
                                    action: _ReviewAction.approveForm,
                                    destinationOfficeId:
                                        _selectedDestinationOfficeId,
                                    destinationOfficeName: _destinationCtrl.text
                                        .trim(),
                                    remarks: _remarksCtrl.text.trim(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.verified_rounded),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              label: const Text('Endorse (legacy form)'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 17, color: AppTheme.primaryNavy),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppTheme.dashTextPrimaryOf(context),
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _chip(
    String text, {
    required Color bg,
    required Color fg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'endorsed':
        return const Color(0xFF2E7D32);
      case 'mayor_approved':
        return AppTheme.primaryNavy;
      case 'rejected':
        return const Color(0xFFC62828);
      default:
        return const Color(0xFFEF6C00);
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.trim().toLowerCase()) {
      case 'urgent':
        return const Color(0xFFC62828);
      case 'high':
        return const Color(0xFFF57C00);
      case 'low':
        return AppTheme.textSecondary;
      default:
        return const Color(0xFF455A64);
    }
  }

  String _cap(String value) {
    final v = value.trim();
    if (v.isEmpty) return '-';
    return '${v[0].toUpperCase()}${v.substring(1).toLowerCase()}';
  }

  String _formatAddressForDisplay(String raw) {
    final p = parseStoredAddress(raw);
    if (!p.isStructured) {
      final v = raw.trim();
      return v.isEmpty ? '—' : v;
    }
    final parts = <String>[
      p.street,
      p.barangay,
      p.city,
      p.province,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }
}

class _MayorReviewSummaryBar extends StatelessWidget {
  const _MayorReviewSummaryBar({
    required this.request,
    this.onScheduleMeeting,
    this.onMarkNoShow,
    this.onMarkMetMayor,
  });

  final MayorEndorsementRequest request;
  final Future<void> Function()? onScheduleMeeting;
  final Future<void> Function()? onMarkNoShow;
  final Future<void> Function()? onMarkMetMayor;

  @override
  Widget build(BuildContext context) {
    final requester = (request.submittedByName ?? '').trim();
    final meeting = request.appointmentAt;
    final noShow = request.appointmentStatus == 'no_show';
    final isScheduled = request.appointmentStatus == 'scheduled';
    final secondary = AppTheme.dashTextSecondaryOf(context);
    final showMeetingActions =
        onMarkMetMayor != null || onScheduleMeeting != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _MayorMetaChip(
                icon: Icons.person_pin_rounded,
                label: 'Who requested',
                value: requester.isEmpty ? '—' : requester,
              ),
              _MayorMetaChip(
                icon: Icons.account_balance_outlined,
                label: 'Office applicant will enter',
                value: request.endorseToOffice,
              ),
              _MayorMetaChip(
                icon: Icons.gavel_rounded,
                label: 'Endorse?',
                value: request.decisionLabel,
              ),
              _MayorMetaChip(
                icon: noShow
                    ? Icons.event_busy_rounded
                    : request.hasMetMayor
                    ? Icons.handshake_outlined
                    : Icons.event_available_rounded,
                label: 'Meeting with Mayor',
                value: meeting == null
                    ? request.meetingLabel
                    : '${request.meetingLabel} · ${_fmtDateTime(meeting)}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MayorMeetingOutcomePill(request: request),
          if (showMeetingActions) ...[
            const SizedBox(height: 12),
            Text(
              request.hasMetMayor
                  ? 'They already met the Mayor. You can now approve (and set the office) or reject.'
                  : noShow
                  ? (onScheduleMeeting != null
                      ? 'They did not appear. Reschedule, or tap Met the Mayor if they already talked to the Mayor.'
                      : 'They did not appear. Tap Met the Mayor if they already talked to the Mayor.')
                  : onScheduleMeeting != null
                  ? 'If they already talked to / saw the Mayor, tap Met the Mayor. '
                        'If not, schedule a meeting. If they miss it, mark Did not appear and reschedule.'
                  : 'If they already met the Mayor (early or on schedule), tap Met the Mayor. '
                        'If they did not appear, mark Did not appear.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: secondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onMarkMetMayor != null)
                  FilledButton.icon(
                    onPressed: onMarkMetMayor,
                    icon: const Icon(Icons.handshake_outlined, size: 18),
                    label: const Text('Met the Mayor'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (onScheduleMeeting != null)
                  OutlinedButton.icon(
                    onPressed: onScheduleMeeting,
                    icon: Icon(
                      noShow
                          ? Icons.event_repeat_rounded
                          : meeting == null
                          ? Icons.event_rounded
                          : Icons.edit_calendar_rounded,
                      size: 18,
                    ),
                    label: Text(
                      noShow
                          ? 'Reschedule meeting'
                          : meeting == null
                          ? 'Schedule meeting'
                          : 'Change schedule',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                      side: const BorderSide(color: AppTheme.primaryNavy),
                    ),
                  ),
                if (isScheduled && onMarkNoShow != null)
                  TextButton.icon(
                    onPressed: onMarkNoShow,
                    icon: const Icon(Icons.event_busy_rounded, size: 18),
                    label: const Text('Did not appear'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryNavy,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewWorkflowStrip extends StatelessWidget {
  const _ReviewWorkflowStrip({required this.request});

  final MayorEndorsementRequest request;

  @override
  Widget build(BuildContext context) {
    final status = request.status.toLowerCase();
    final met =
        request.hasMetMayor ||
        status == 'mayor_approved' ||
        status == 'endorsed';
    final decided = status == 'endorsed';
    final officeForm = status == 'mayor_approved';
    final meetDone = met;
    final meetActive = !met && status != 'rejected';
    final decisionDone = decided;
    final decisionActive = met && !decided && status != 'rejected';
    final decisionLabel = officeForm
        ? 'Office form'
        : decided
        ? 'Endorsed'
        : 'Approve / Reject';

    Widget node({
      required int index,
      required String label,
      required bool active,
      required bool done,
    }) {
      final color = done || active
          ? AppTheme.primaryNavy
          : const Color(0xFF94A3B8);
      return Expanded(
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? AppTheme.primaryNavy
                    : active
                    ? AppTheme.primaryNavy
                    : const Color(0xFFE2E8F0),
              ),
              child: done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: active ? Colors.white : const Color(0xFF64748B),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active || done
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      color: Colors.white,
      child: status == 'rejected'
          ? Row(
              children: [
                Icon(
                  Icons.cancel_outlined,
                  size: 18,
                  color: Colors.red.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'This endorsement request was rejected.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                node(index: 0, label: 'Intake form', active: false, done: true),
                Container(
                  width: 28,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: AppTheme.primaryNavy,
                ),
                node(
                  index: 1,
                  label: 'Meet the Mayor',
                  active: meetActive,
                  done: meetDone,
                ),
                Container(
                  width: 28,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: meetDone
                      ? AppTheme.primaryNavy
                      : const Color(0xFFE2E8F0),
                ),
                node(
                  index: 2,
                  label: decisionLabel,
                  active: decisionActive,
                  done: decisionDone,
                ),
              ],
            ),
    );
  }
}

Widget _detailGrid(List<Widget> children) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final cols = width >= 860 ? 3 : (width >= 560 ? 2 : 1);
      final gap = 12.0;
      final itemW = (width - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: children.map((child) {
          if (child is _KvField && child.wide && cols > 1) {
            return SizedBox(
              width: cols == 3 ? itemW * 2 + gap : width,
              child: child,
            );
          }
          return SizedBox(width: itemW, child: child);
        }).toList(),
      );
    },
  );
}

Widget _kv(String label, String value, {bool wide = false}) {
  return _KvField(label: label, value: value, wide: wide);
}

class _KvField extends StatelessWidget {
  const _KvField({required this.label, required this.value, this.wide = false});

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final display = value.trim().isEmpty || value.trim().toLowerCase() == 'none'
        ? '—'
        : value.trim();
    final empty = display == '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFECEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            display,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              height: 1.35,
              color: empty
                  ? AppTheme.dashTextSecondaryOf(context)
                  : AppTheme.dashTextPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _MayorSectionCard extends StatelessWidget {
  const _MayorSectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MayorTableHeader extends StatelessWidget {
  const _MayorTableHeader({required this.columns});

  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: columns
            .map(
              (c) => Expanded(
                child: Text(
                  c,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MayorStatusPill extends StatelessWidget {
  const _MayorStatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    final (label, fg, bg) = switch (lower) {
      'endorsed' => ('Endorsed', Colors.green.shade800, Colors.green.shade50),
      'mayor_approved' => (
        'Awaiting Office Form',
        Colors.blue.shade800,
        Colors.blue.shade50,
      ),
      'rejected' => ('Rejected', Colors.red.shade800, Colors.red.shade50),
      _ => ('Pending', Colors.orange.shade900, Colors.orange.shade50),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Clear meeting-outcome badge for Mayor and Staff (met / not yet / no-show).
class _MayorMeetingOutcomePill extends StatelessWidget {
  const _MayorMeetingOutcomePill({required this.request});
  final MayorEndorsementRequest request;

  @override
  Widget build(BuildContext context) {
    final status = request.status.toLowerCase();
    final met = request.hasMetMayor ||
        status == 'endorsed' ||
        status == 'mayor_approved';
    final noShow = request.appointmentStatus.toLowerCase() == 'no_show';

    late final String label;
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    if (met) {
      label = 'Met the Mayor';
      bg = AppTheme.primaryNavy;
      fg = Colors.white;
      icon = Icons.handshake_outlined;
    } else if (noShow) {
      label = 'Did not appear';
      bg = const Color(0xFFC62828);
      fg = Colors.white;
      icon = Icons.event_busy_rounded;
    } else {
      label = 'Not yet met';
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade900;
      icon = Icons.hourglass_empty_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _MayorPriorityPill extends StatelessWidget {
  const _MayorPriorityPill({required this.priority});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final lower = priority.toLowerCase();
    final (fg, bg) = switch (lower) {
      'urgent' => (Colors.red.shade800, Colors.red.shade50),
      'high' => (Colors.deepOrange.shade800, Colors.deepOrange.shade50),
      'low' => (Colors.blueGrey.shade800, Colors.blueGrey.shade50),
      _ => (Colors.indigo.shade800, Colors.indigo.shade50),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        priority.isEmpty ? 'normal' : priority,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _MayorEmptyState extends StatelessWidget {
  const _MayorEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primaryNavy),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: AppTheme.dashTextSecondaryOf(context)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _ReviewAction { approve, approveForm, reject }

class _ReviewActionResult {
  const _ReviewActionResult({
    required this.action,
    this.destinationOfficeId,
    this.destinationOfficeName,
    this.remarks,
    this.reason,
  });

  final _ReviewAction action;
  final String? destinationOfficeId;
  final String? destinationOfficeName;
  final String? remarks;
  final String? reason;
}

class _ApproveOfficeChoice {
  const _ApproveOfficeChoice({required this.officeName, this.officeId});
  final String officeName;
  final String? officeId;
}

class _ApproveEndorsementDialog extends StatefulWidget {
  const _ApproveEndorsementDialog({
    required this.applicantName,
    required this.initialOfficeName,
    this.initialOfficeId,
  });

  final String applicantName;
  final String initialOfficeName;
  final String? initialOfficeId;

  @override
  State<_ApproveEndorsementDialog> createState() =>
      _ApproveEndorsementDialogState();
}

class _ApproveEndorsementDialogState extends State<_ApproveEndorsementDialog> {
  late final TextEditingController _officeCtrl;
  String? _officeId;
  List<_MayorOfficeOption> _offices = const [];

  @override
  void initState() {
    super.initState();
    _officeCtrl = TextEditingController(text: widget.initialOfficeName);
    _officeId = widget.initialOfficeId;
    _loadOffices();
  }

  Future<void> _loadOffices() async {
    try {
      final res = await ApiClient.instance.get<List<dynamic>>(
        '/api/offices',
        queryParameters: const {'status': 'Active'},
      );
      final parsed = (res.data ?? const [])
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            return _MayorOfficeOption(
              id: (m['id'] ?? '').toString(),
              name: (m['name'] ?? '').toString().trim(),
            );
          })
          .where((o) => o.id.isNotEmpty && o.name.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() => _offices = parsed);
    } catch (_) {}
  }

  void _applyOffice(_MayorOfficeOption? office, {String? typed}) {
    if (office != null) {
      _officeId = office.id;
      _officeCtrl.text = office.name;
      return;
    }
    final name = (typed ?? _officeCtrl.text).trim();
    _officeCtrl.text = name;
    String? matchedId;
    for (final o in _offices) {
      if (o.name.toLowerCase() == name.toLowerCase()) {
        matchedId = o.id;
        break;
      }
    }
    _officeId = matchedId;
  }

  void _submit() {
    final name = _officeCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the destination office, then tap Approve.'),
        ),
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(_ApproveOfficeChoice(officeName: name, officeId: _officeId));
  }

  @override
  void dispose() {
    _officeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Endorsement'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 80).clamp(240.0, 420.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are endorsing ${widget.applicantName} to:'),
            const SizedBox(height: 14),
            Autocomplete<_MayorOfficeOption>(
              initialValue: TextEditingValue(text: _officeCtrl.text),
              displayStringForOption: (o) => o.name,
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return _offices;
                return _offices.where((o) => o.name.toLowerCase().contains(q));
              },
              onSelected: (office) => setState(() => _applyOffice(office)),
              fieldViewBuilder: (context, textCtrl, focusNode, onSubmit) {
                if (textCtrl.text != _officeCtrl.text) {
                  textCtrl.value = TextEditingValue(
                    text: _officeCtrl.text,
                    selection: TextSelection.collapsed(
                      offset: _officeCtrl.text.length,
                    ),
                  );
                }
                return TextField(
                  controller: textCtrl,
                  focusNode: focusNode,
                  onChanged: (v) =>
                      setState(() => _applyOffice(null, typed: v)),
                  decoration: const InputDecoration(
                    labelText: 'Destination office',
                    hintText: 'Type or select the office',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirm Endorsement'),
        ),
      ],
    );
  }
}

class _MayorOfficeOption {
  const _MayorOfficeOption({required this.id, required this.name});
  final String id;
  final String name;
}

String _fmtDateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtDateTime(DateTime d) =>
    '${_fmtDateOnly(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _fmtShortDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

bool _isMayorOfficeLabel(String? value) {
  final t = (value ?? '').trim().toLowerCase();
  if (t.isEmpty) return true;
  return t.contains('mayor');
}

class MayorEndorsementRepo {
  MayorEndorsementRepo._();
  static final MayorEndorsementRepo instance = MayorEndorsementRepo._();

  Future<MayorDashboardData> fetchDashboard({bool includeTest = false}) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/mayor/endorsements/dashboard',
      queryParameters: {
        if (includeTest) 'include_test': '1',
      },
    );
    return MayorDashboardData.fromJson(res.data ?? {});
  }

  Future<Map<String, dynamic>> fetchReport({
    required String period,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeTest = false,
  }) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/mayor/endorsements/reports',
      queryParameters: {
        'period': period,
        if (fromDate != null) 'from_date': _fmtDateOnly(fromDate),
        if (toDate != null) 'to_date': _fmtDateOnly(toDate),
        if (includeTest) 'include_test': '1',
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<MayorEndorsementListResponse> listRequests({
    String? search,
    String? office,
    String? status,
    String? priority,
    String? meetingRequestStatus,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int pageSize = 20,
  }) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/mayor/endorsements',
      queryParameters: {
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        if ((office ?? '').trim().isNotEmpty) 'office': office!.trim(),
        if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
        if ((priority ?? '').trim().isNotEmpty) 'priority': priority!.trim(),
        if ((meetingRequestStatus ?? '').trim().isNotEmpty)
          'meeting_request_status': meetingRequestStatus!.trim(),
        if (fromDate != null) 'from_date': _fmtDateOnly(fromDate),
        if (toDate != null) 'to_date': _fmtDateOnly(toDate),
        'page': page,
        'page_size': pageSize,
      },
    );
    return MayorEndorsementListResponse.fromJson(res.data ?? {});
  }

  Future<MayorEndorsementListResponse> listHistory({
    String? search,
    String? office,
    String? status,
    String? priority,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeTest = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/mayor/endorsements/history',
      queryParameters: {
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        if ((office ?? '').trim().isNotEmpty) 'office': office!.trim(),
        if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
        if ((priority ?? '').trim().isNotEmpty) 'priority': priority!.trim(),
        if (fromDate != null) 'from_date': _fmtDateOnly(fromDate),
        if (toDate != null) 'to_date': _fmtDateOnly(toDate),
        if (includeTest) 'include_test': '1',
        'page': page,
        'page_size': pageSize,
      },
    );
    return MayorEndorsementListResponse.fromJson(res.data ?? {});
  }

  Future<MayorEndorsementDetails> getRequestDetails(String requestId) async {
    final res = await ApiClient.instance.get<Map<String, dynamic>>(
      '/api/mayor/endorsements/$requestId',
    );
    return MayorEndorsementDetails.fromJson(res.data ?? {});
  }

  Future<void> approveRequest(
    String requestId, {
    String? destinationOfficeId,
    String? destinationOfficeName,
    String? remarks,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/approve',
      data: {
        if ((destinationOfficeId ?? '').trim().isNotEmpty)
          'destinationOfficeId': destinationOfficeId!.trim(),
        if ((destinationOfficeName ?? '').trim().isNotEmpty)
          'destinationOfficeName': destinationOfficeName!.trim(),
        if ((remarks ?? '').trim().isNotEmpty) 'remarks': remarks!.trim(),
      },
    );
  }

  Future<void> endorseRequest(
    String requestId, {
    String? destinationOfficeId,
    String? destinationOfficeName,
    String? remarks,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/endorse',
      data: {
        if ((destinationOfficeId ?? '').trim().isNotEmpty)
          'destinationOfficeId': destinationOfficeId!.trim(),
        if ((destinationOfficeName ?? '').trim().isNotEmpty)
          'destinationOfficeName': destinationOfficeName!.trim(),
        if ((remarks ?? '').trim().isNotEmpty) 'remarks': remarks!.trim(),
      },
    );
  }

  Future<void> submitMeetingRequest(
    String requestId, {
    required DateTime proposedAt,
    required String purpose,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/meeting-request',
      data: {
        'proposedAt': proposedAt.toUtc().toIso8601String(),
        'purpose': purpose.trim(),
      },
    );
  }

  Future<void> approveMeeting(String requestId, {String? remarks}) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/meeting/approve',
      data: {
        if ((remarks ?? '').trim().isNotEmpty) 'remarks': remarks!.trim(),
      },
    );
  }

  Future<void> rescheduleMeeting(
    String requestId, {
    required String remarks,
    DateTime? alternativeAt,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/meeting/reschedule',
      data: {
        'remarks': remarks.trim(),
        if (alternativeAt != null)
          'alternativeAt': alternativeAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> declineMeeting(String requestId, {String? remarks}) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/meeting/decline',
      data: {
        if ((remarks ?? '').trim().isNotEmpty) 'remarks': remarks!.trim(),
      },
    );
  }

  Future<void> approveEndorsementForm(
    String requestId, {
    String? destinationOfficeId,
    String? destinationOfficeName,
    String? remarks,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/approve-form',
      data: {
        if ((destinationOfficeId ?? '').trim().isNotEmpty)
          'destinationOfficeId': destinationOfficeId!.trim(),
        if ((destinationOfficeName ?? '').trim().isNotEmpty)
          'destinationOfficeName': destinationOfficeName!.trim(),
        if ((remarks ?? '').trim().isNotEmpty) 'remarks': remarks!.trim(),
      },
    );
  }

  Future<void> rejectRequest(String requestId, [String reason = '']) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/reject',
      data: {'reason': reason.trim()},
    );
  }

  Future<void> submitEndorsementRequest({
    required String priority,
    required Map<String, dynamic> intakeForm,
    String? staffNotes,
    String? requestedOfficeId,
    String? requestedOfficeName,
  }) async {
    await ApiClient.instance.post<Map<String, dynamic>>(
      '/api/mayor/endorsements/requests',
      data: {
        'priority': priority,
        'intakeForm': intakeForm,
        if ((staffNotes ?? '').trim().isNotEmpty)
          'staffNotes': staffNotes!.trim(),
        if ((requestedOfficeId ?? '').trim().isNotEmpty)
          'requestedOfficeId': requestedOfficeId!.trim(),
        if ((requestedOfficeName ?? '').trim().isNotEmpty)
          'requestedOfficeName': requestedOfficeName!.trim(),
      },
    );
  }

  Future<void> scheduleMayorMeeting(
    String requestId, {
    required DateTime appointmentAt,
    String? notes,
  }) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/schedule',
      data: {
        'appointmentAt': appointmentAt.toUtc().toIso8601String(),
        if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
      },
    );
  }

  Future<void> markMayorMeetingNoShow(String requestId, {String? notes}) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/no-show',
      data: {if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim()},
    );
  }

  Future<void> markMetMayor(String requestId, {String? notes}) async {
    await ApiClient.instance.post<void>(
      '/api/mayor/endorsements/$requestId/met',
      data: {if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim()},
    );
  }
}

class MayorDashboardData {
  const MayorDashboardData({
    required this.pendingCount,
    required this.mayorApprovedCount,
    required this.endorsedCount,
    required this.rejectedCount,
    required this.totalRequests,
    required this.endorsedToday,
    required this.endorsedThisWeek,
    required this.endorsedThisMonth,
    required this.pendingMeetingApprovals,
    required this.pendingFinalDecisions,
    required this.pendingAttendance,
    required this.rescheduleRequestedCount,
    required this.approvedMeetingsCount,
    required this.completedMeetingsCount,
    required this.meetingsToday,
    required this.upcomingMeetingsCount,
    required this.legacyScheduledWithoutMeetingApproval,
    this.requestsToday = 0,
    this.requestsThisWeek = 0,
    this.requestsThisMonth = 0,
    this.rejectedToday = 0,
    this.rejectedThisWeek = 0,
    this.rejectedThisMonth = 0,
    this.meetingsOnToday = 0,
    this.meetingsThisWeek = 0,
    this.meetingsThisMonth = 0,
    required this.recentRequests,
    required this.officeStatistics,
    required this.monthlyTrends,
    required this.recentEndorsements,
    required this.pendingMayorActions,
    required this.meetingQueue,
    required this.upcomingMeetings,
  });

  final int pendingCount;
  final int mayorApprovedCount;
  final int endorsedCount;
  final int rejectedCount;
  final int totalRequests;
  final int endorsedToday;
  final int endorsedThisWeek;
  final int endorsedThisMonth;
  final int pendingMeetingApprovals;
  final int pendingFinalDecisions;
  final int pendingAttendance;
  final int rescheduleRequestedCount;
  final int approvedMeetingsCount;
  final int completedMeetingsCount;
  final int meetingsToday;
  final int upcomingMeetingsCount;
  final int legacyScheduledWithoutMeetingApproval;
  final int requestsToday;
  final int requestsThisWeek;
  final int requestsThisMonth;
  final int rejectedToday;
  final int rejectedThisWeek;
  final int rejectedThisMonth;
  final int meetingsOnToday;
  final int meetingsThisWeek;
  final int meetingsThisMonth;
  final List<MayorEndorsementRequest> recentRequests;
  final List<MayorOfficeStat> officeStatistics;
  final List<MayorMonthTrend> monthlyTrends;
  final List<MayorDashListItem> recentEndorsements;
  final List<MayorDashListItem> pendingMayorActions;
  final List<MayorDashListItem> meetingQueue;
  final List<MayorDashListItem> upcomingMeetings;

  MayorMonitoringSummary toMonitoringSummary() => MayorMonitoringSummary(
        totalRequests: totalRequests,
        pendingCount: pendingCount,
        endorsedCount: endorsedCount,
        rejectedCount: rejectedCount,
        endorsedToday: endorsedToday,
        endorsedThisWeek: endorsedThisWeek,
        endorsedThisMonth: endorsedThisMonth,
        pendingMeetingApprovals: pendingMeetingApprovals,
        pendingFinalDecisions: pendingFinalDecisions,
        pendingAttendance: pendingAttendance,
        rescheduleRequestedCount: rescheduleRequestedCount,
        approvedMeetingsCount: approvedMeetingsCount,
        completedMeetingsCount: completedMeetingsCount,
        meetingsToday: meetingsToday,
        upcomingMeetingsCount: upcomingMeetingsCount,
        legacyScheduledWithoutMeetingApproval:
            legacyScheduledWithoutMeetingApproval,
        requestsToday: requestsToday,
        requestsThisWeek: requestsThisWeek,
        requestsThisMonth: requestsThisMonth,
        rejectedToday: rejectedToday,
        rejectedThisWeek: rejectedThisWeek,
        rejectedThisMonth: rejectedThisMonth,
        meetingsOnToday: meetingsOnToday,
        meetingsThisWeek: meetingsThisWeek,
        meetingsThisMonth: meetingsThisMonth,
      );

  static MayorDashListItem _listItemFromJson(Map<String, dynamic> json) {
    final status = (json['status'] ?? 'pending').toString();
    String statusLabel;
    switch (status.toLowerCase()) {
      case 'endorsed':
        statusLabel = 'Endorsed';
        break;
      case 'rejected':
        statusLabel = 'Rejected';
        break;
      case 'mayor_approved':
        statusLabel = 'Awaiting Office Form';
        break;
      default:
        statusLabel = 'Pending';
    }
    final office = (json['office_name'] ??
            json['destination_office'] ??
            'Unassigned')
        .toString();
    final ref = json['reference_number']?.toString();
    return MayorDashListItem(
      id: (json['id'] ?? '').toString(),
      applicantName: (json['applicant_name'] ?? '').toString(),
      subtitle: office,
      statusLabel: statusLabel,
      referenceNumber: ref,
      meetingRequestStatus:
          (json['meeting_request_status'] ?? 'none').toString(),
      raw: json,
    );
  }

  factory MayorDashboardData.fromJson(Map<String, dynamic> json) {
    final summary = Map<String, dynamic>.from((json['summary'] as Map?) ?? {});
    final recentRaw = (json['recent_requests'] as List?) ?? const [];
    final officeRaw = (json['office_statistics'] as List?) ?? const [];
    final trendRaw = (json['monthly_trends'] as List?) ?? const [];
    final recentEndorsedRaw =
        (json['recent_endorsements'] as List?) ?? const [];
    final pendingActionsRaw =
        (json['pending_mayor_actions'] as List?) ?? recentRaw;
    final meetingQueueRaw = (json['meeting_queue'] as List?) ?? const [];
    final upcomingRaw = (json['upcoming_meetings'] as List?) ?? const [];

    List<MayorDashListItem> mapItems(List raw) => raw
        .whereType<Map>()
        .map((e) => _listItemFromJson(Map<String, dynamic>.from(e)))
        .toList();

    return MayorDashboardData(
      pendingCount: _toInt(summary['pending_count']),
      mayorApprovedCount: _toInt(summary['mayor_approved_count']),
      endorsedCount: _toInt(summary['endorsed_count']),
      rejectedCount: _toInt(summary['rejected_count']),
      totalRequests: _toInt(summary['total_requests']),
      endorsedToday: _toInt(summary['endorsed_today']),
      endorsedThisWeek: _toInt(summary['endorsed_this_week']),
      endorsedThisMonth: _toInt(summary['endorsed_this_month']),
      pendingMeetingApprovals: _toInt(summary['pending_meeting_approvals']),
      pendingFinalDecisions: _toInt(summary['pending_final_decisions']),
      pendingAttendance: _toInt(summary['pending_attendance']),
      rescheduleRequestedCount: _toInt(summary['reschedule_requested_count']),
      approvedMeetingsCount: _toInt(summary['approved_meetings_count']),
      completedMeetingsCount: _toInt(summary['completed_meetings_count']),
      meetingsToday: _toInt(summary['meetings_today']),
      upcomingMeetingsCount: _toInt(summary['upcoming_meetings']),
      legacyScheduledWithoutMeetingApproval:
          _toInt(summary['legacy_scheduled_without_meeting_approval']),
      requestsToday: _toInt(summary['requests_today']),
      requestsThisWeek: _toInt(summary['requests_this_week']),
      requestsThisMonth: _toInt(summary['requests_this_month']),
      rejectedToday: _toInt(summary['rejected_today']),
      rejectedThisWeek: _toInt(summary['rejected_this_week']),
      rejectedThisMonth: _toInt(summary['rejected_this_month']),
      meetingsOnToday: _toInt(summary['meetings_on_today']),
      meetingsThisWeek: _toInt(summary['meetings_this_week']),
      meetingsThisMonth: _toInt(summary['meetings_this_month']),
      recentRequests: recentRaw
          .whereType<Map>()
          .map(
            (e) =>
                MayorEndorsementRequest.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
      officeStatistics: officeRaw
          .whereType<Map>()
          .map((e) => MayorOfficeStat.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      monthlyTrends: trendRaw
          .whereType<Map>()
          .map(
            (e) => MayorMonthTrend(
              month: (e['month'] ?? '').toString(),
              endorsedCount: _toInt(e['endorsed_count']),
            ),
          )
          .toList(),
      recentEndorsements: mapItems(recentEndorsedRaw),
      pendingMayorActions: mapItems(pendingActionsRaw),
      meetingQueue: mapItems(meetingQueueRaw),
      upcomingMeetings: mapItems(upcomingRaw),
    );
  }
}

class MayorOfficeStat {
  const MayorOfficeStat({required this.officeName, required this.total});
  final String officeName;
  final int total;

  factory MayorOfficeStat.fromJson(Map<String, dynamic> json) =>
      MayorOfficeStat(
        officeName: (json['office_name'] ?? 'Unassigned').toString(),
        total: _toInt(json['total']),
      );
}

class MayorEndorsementListResponse {
  const MayorEndorsementListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final List<MayorEndorsementRequest> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  factory MayorEndorsementListResponse.empty() =>
      const MayorEndorsementListResponse(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      );

  factory MayorEndorsementListResponse.fromJson(Map<String, dynamic> json) {
    final itemsRaw = (json['items'] as List?) ?? const [];
    final pagination = Map<String, dynamic>.from(
      (json['pagination'] as Map?) ?? {},
    );
    return MayorEndorsementListResponse(
      items: itemsRaw
          .whereType<Map>()
          .map(
            (e) =>
                MayorEndorsementRequest.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
      total: _toInt(pagination['total']),
      page: _toInt(pagination['page'], fallback: 1),
      pageSize: _toInt(pagination['page_size'], fallback: 20),
      totalPages: _toInt(pagination['total_pages'], fallback: 1),
    );
  }
}

class MayorEndorsementRequest {
  const MayorEndorsementRequest({
    required this.id,
    required this.applicationId,
    required this.applicantName,
    required this.officeName,
    required this.submittedAt,
    required this.status,
    required this.priority,
    this.destinationOfficeId,
    this.destinationOfficeName,
    this.requestedOfficeName,
    this.submittedByName,
    this.appointmentAt,
    this.appointmentStatus = 'none',
    this.appointmentNotes,
    this.noShowCount = 0,
    this.staffNotes,
    this.mayorRemarks,
    this.rejectionReason,
    this.approvedAt,
    this.rejectedAt,
    this.officeFormApprovedAt,
    this.referenceNumber,
    this.meetingRequestStatus = 'none',
    this.meetingProposedAt,
    this.meetingPurpose,
    this.meetingDecision,
    this.meetingDecidedAt,
    this.meetingDecisionRemarks,
    this.meetingRescheduleProposedAt,
    this.intakeForm = const MayorIntakeFormData(),
  });

  final String id;
  final String applicationId;
  final String applicantName;
  final String officeName;
  final DateTime submittedAt;
  final String status;
  final String priority;
  final String? destinationOfficeId;
  final String? destinationOfficeName;
  final String? requestedOfficeName;
  final String? submittedByName;
  final DateTime? appointmentAt;
  final String appointmentStatus;
  final String? appointmentNotes;
  final int noShowCount;
  final String? staffNotes;
  final String? mayorRemarks;
  final String? rejectionReason;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? officeFormApprovedAt;
  final String? referenceNumber;
  final String meetingRequestStatus;
  final DateTime? meetingProposedAt;
  final String? meetingPurpose;
  final String? meetingDecision;
  final DateTime? meetingDecidedAt;
  final String? meetingDecisionRemarks;
  final DateTime? meetingRescheduleProposedAt;
  final MayorIntakeFormData intakeForm;

  String get endorseToOffice {
    final dest = (destinationOfficeName ?? '').trim();
    if (dest.isNotEmpty) return dest;
    final requested = (requestedOfficeName ?? '').trim();
    if (requested.isNotEmpty) return requested;
    return officeName.trim().isEmpty ? 'Unassigned' : officeName.trim();
  }

  String get decisionLabel {
    switch (status.toLowerCase()) {
      case 'endorsed':
        return 'Endorse';
      case 'rejected':
        return 'Do not endorse';
      case 'mayor_approved':
        return 'Mayor approved — form pending';
      default:
        return hasMetMayor ? 'Awaiting decision' : 'Awaiting meeting';
    }
  }

  String get meetingLabel {
    switch (appointmentStatus.toLowerCase()) {
      case 'scheduled':
        return 'Scheduled';
      case 'no_show':
        return 'Did not appear';
      case 'completed':
        return 'Met the Mayor';
      default:
        return appointmentAt == null ? 'Not scheduled' : 'Scheduled';
    }
  }

  String get meetingRequestLabel {
    switch (meetingRequestStatus.toLowerCase()) {
      case 'submitted':
        return 'Awaiting Mayor approval';
      case 'approved':
        return appointmentStatus == 'completed'
            ? 'Met the Mayor'
            : appointmentStatus == 'no_show'
            ? 'Approved — no-show'
            : 'Meeting approved';
      case 'reschedule_requested':
        return 'Reschedule required';
      case 'declined':
        return 'Meeting declined';
      default:
        return meetingLabel;
    }
  }

  bool get hasMetMayor => appointmentStatus.toLowerCase() == 'completed';

  bool get canStaffSubmitMeetingRequest {
    if (status != 'pending') return false;
    final mrs = meetingRequestStatus.toLowerCase();
    if (mrs == 'submitted') return false;
    if (mrs == 'approved' && appointmentStatus != 'no_show') return false;
    return true;
  }

  bool get isOpenRequest => status == 'pending' || status == 'mayor_approved';

  /// 1 = intake done, 2 = meeting workflow, 3 = decide endorse/reject.
  int get flowStep {
    if (status == 'endorsed' ||
        status == 'rejected' ||
        status == 'mayor_approved') {
      return 3;
    }
    if (hasMetMayor) return 3;
    return 2;
  }

  String get flowStepLabel {
    switch (flowStep) {
      case 3:
        if (status == 'endorsed') return 'Step 3: Endorsed';
        if (status == 'rejected') return 'Step 3: Rejected';
        if (status == 'mayor_approved') {
          return 'Step 3: Legacy — finalize endorse';
        }
        return 'Step 3: Endorse or reject';
      case 2:
        if (meetingRequestStatus == 'submitted') {
          return 'Step 2: Meeting request awaiting Mayor';
        }
        if (meetingRequestStatus == 'approved' &&
            appointmentStatus == 'scheduled') {
          return 'Step 2: Meeting approved — record attendance';
        }
        if (appointmentStatus == 'no_show') {
          return 'Step 2: No-show — submit new meeting request';
        }
        if (meetingRequestStatus == 'reschedule_requested') {
          return 'Step 2: Mayor asked to reschedule';
        }
        if (meetingRequestStatus == 'declined') {
          return 'Step 2: Meeting declined — optional new request';
        }
        return 'Step 2: Submit meeting request';
      default:
        return 'Step 1: Intake form submitted';
    }
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'endorsed':
        return 'Endorsed';
      case 'mayor_approved':
        return 'Awaiting Office Form';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  factory MayorEndorsementRequest.fromJson(Map<String, dynamic> json) {
    final submitted =
        DateTime.tryParse((json['submitted_at'] ?? '').toString()) ??
        DateTime.now();
    DateTime? parseOpt(dynamic v) {
      final s = (v ?? '').toString();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return MayorEndorsementRequest(
      id: (json['id'] ?? '').toString(),
      applicationId: (json['application_id'] ?? '').toString(),
      applicantName: (json['applicant_name'] ?? '').toString(),
      officeName: (json['office_name'] ?? '').toString(),
      submittedAt: submitted,
      status: (json['status'] ?? 'pending').toString(),
      priority: (json['priority'] ?? 'normal').toString(),
      destinationOfficeId: json['destination_office_id']?.toString(),
      destinationOfficeName:
          (json['destination_office_name'] ?? json['destination_office_label'])
              ?.toString(),
      requestedOfficeName:
          (json['requested_office_name'] ?? json['requested_office_label'])
              ?.toString(),
      submittedByName: (json['submitted_by_name'] ?? json['submitted_by_label'])
          ?.toString(),
      appointmentAt: parseOpt(json['appointment_at']),
      appointmentStatus: (json['appointment_status'] ?? 'none').toString(),
      appointmentNotes: json['appointment_notes']?.toString(),
      noShowCount: _toInt(json['no_show_count']),
      staffNotes: json['staff_notes']?.toString(),
      mayorRemarks: json['mayor_remarks']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      approvedAt: parseOpt(json['approved_at']),
      rejectedAt: parseOpt(json['rejected_at']),
      officeFormApprovedAt: parseOpt(json['office_form_approved_at']),
      referenceNumber: json['reference_number']?.toString(),
      meetingRequestStatus:
          (json['meeting_request_status'] ?? 'none').toString(),
      meetingProposedAt: parseOpt(json['meeting_proposed_at']),
      meetingPurpose: json['meeting_purpose']?.toString(),
      meetingDecision: json['meeting_decision']?.toString(),
      meetingDecidedAt: parseOpt(json['meeting_decided_at']),
      meetingDecisionRemarks: json['meeting_decision_remarks']?.toString(),
      meetingRescheduleProposedAt:
          parseOpt(json['meeting_reschedule_proposed_at']),
      intakeForm: MayorIntakeFormData.fromJson(
        Map<String, dynamic>.from((json['intake_form'] as Map?) ?? {}),
      ),
    );
  }
}

class MayorApplicant {
  const MayorApplicant({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.positionAppliedFor,
    required this.status,
  });

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String positionAppliedFor;
  final String status;

  factory MayorApplicant.fromJson(Map<String, dynamic> json) => MayorApplicant(
    id: (json['id'] ?? '').toString(),
    fullName: (json['full_name'] ?? '').toString(),
    email: (json['email'] ?? '').toString(),
    phone: (json['phone'] ?? '').toString(),
    positionAppliedFor: (json['position_applied_for'] ?? '').toString(),
    status: (json['status'] ?? '').toString(),
  );
}

class MayorDocument {
  const MayorDocument({
    required this.kind,
    required this.label,
    required this.path,
    this.fileName,
  });
  final String kind;
  final String label;
  final String? path;
  final String? fileName;

  factory MayorDocument.fromJson(Map<String, dynamic> json) => MayorDocument(
    kind: (json['kind'] ?? '').toString(),
    label: (json['label'] ?? '').toString(),
    path: json['path']?.toString(),
    fileName: json['file_name']?.toString(),
  );
}

class MayorHistoryEntry {
  const MayorHistoryEntry({
    required this.action,
    required this.createdAt,
    this.actorName,
    this.remarks,
  });

  final String action;
  final DateTime createdAt;
  final String? actorName;
  final String? remarks;

  factory MayorHistoryEntry.fromJson(Map<String, dynamic> json) =>
      MayorHistoryEntry(
        action: (json['action'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((json['created_at'] ?? '').toString()) ??
            DateTime.now(),
        actorName: json['actor_name']?.toString(),
        remarks: json['remarks']?.toString(),
      );
}

class MayorEndorsementDetails {
  const MayorEndorsementDetails({
    required this.request,
    required this.applicant,
    required this.documents,
    required this.applicationHistory,
    required this.previousEndorsements,
  });

  final MayorEndorsementRequest request;
  final MayorApplicant applicant;
  final List<MayorDocument> documents;
  final List<MayorHistoryEntry> applicationHistory;
  final List<MayorEndorsementRequest> previousEndorsements;

  factory MayorEndorsementDetails.fromJson(Map<String, dynamic> json) {
    final request = MayorEndorsementRequest.fromJson(
      Map<String, dynamic>.from((json['request'] as Map?) ?? {}),
    );
    final applicant = MayorApplicant.fromJson(
      Map<String, dynamic>.from((json['applicant'] as Map?) ?? {}),
    );
    final docs = (json['documents'] as List?) ?? const [];
    final history = (json['application_history'] as List?) ?? const [];
    final previous = (json['previous_endorsements'] as List?) ?? const [];
    return MayorEndorsementDetails(
      request: request,
      applicant: applicant,
      documents: docs
          .whereType<Map>()
          .map((e) => MayorDocument.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      applicationHistory: history
          .whereType<Map>()
          .map((e) => MayorHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      previousEndorsements: previous
          .whereType<Map>()
          .map(
            (e) =>
                MayorEndorsementRequest.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
    );
  }
}

class MayorIntakeFormData {
  const MayorIntakeFormData({
    this.lastName = '',
    this.firstName = '',
    this.middleNameOrInitial = '',
    this.address = '',
    this.course = '',
    this.schoolAddress = '',
    this.positionApplyingFor = '',
    this.currentWorkDesignation = '',
    this.agencyCompany = '',
    this.noOfService = '',
    this.currentWorkAddress = '',
    this.prcCscNo = '',
    this.rankAndCode = '',
  });

  final String lastName;
  final String firstName;
  final String middleNameOrInitial;
  final String address;
  final String course;
  final String schoolAddress;
  final String positionApplyingFor;
  final String currentWorkDesignation;
  final String agencyCompany;
  final String noOfService;
  final String currentWorkAddress;
  final String prcCscNo;
  final String rankAndCode;

  factory MayorIntakeFormData.fromJson(Map<String, dynamic> json) =>
      MayorIntakeFormData(
        lastName: (json['last_name'] ?? '').toString(),
        firstName: (json['first_name'] ?? '').toString(),
        middleNameOrInitial: (json['middle_name_or_initial'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        course: (json['course'] ?? '').toString(),
        schoolAddress: (json['school_address'] ?? '').toString(),
        positionApplyingFor: (json['position_applying_for'] ?? '').toString(),
        currentWorkDesignation: (json['current_work_designation'] ?? '')
            .toString(),
        agencyCompany: (json['agency_company'] ?? '').toString(),
        noOfService: (json['no_of_service'] ?? '').toString(),
        currentWorkAddress: (json['current_work_address'] ?? '').toString(),
        prcCscNo: (json['prc_csc_no'] ?? '').toString(),
        rankAndCode: (json['rank_and_code'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
    'last_name': lastName.trim(),
    'first_name': firstName.trim(),
    'middle_name_or_initial': middleNameOrInitial.trim(),
    'address': address.trim(),
    'course': course.trim(),
    'school_address': schoolAddress.trim(),
    'position_applying_for': positionApplyingFor.trim(),
    'current_work_designation': currentWorkDesignation.trim(),
    'agency_company': agencyCompany.trim(),
    'no_of_service': noOfService.trim(),
    'current_work_address': currentWorkAddress.trim(),
    'prc_csc_no': prcCscNo.trim(),
    'rank_and_code': rankAndCode.trim(),
  };

  /// Required: name + address + education. Middle name and work/PRC fields are optional.
  String? firstMissingLabel() {
    final pairs = <MapEntry<String, String>>[
      MapEntry(lastName, 'Last Name'),
      MapEntry(firstName, 'First Name'),
      MapEntry(address, 'Address'),
      MapEntry(course, 'Course'),
      MapEntry(schoolAddress, 'School Address'),
    ];
    for (final p in pairs) {
      if (p.key.trim().isEmpty) return p.value;
    }
    return null;
  }
}

class MayorEndorsementIntakeSubmission {
  const MayorEndorsementIntakeSubmission({
    required this.priority,
    required this.intakeForm,
    this.staffNotes,
    this.requestedOfficeId,
    this.requestedOfficeName,
  });

  final String priority;
  final MayorIntakeFormData intakeForm;
  final String? staffNotes;
  final String? requestedOfficeId;
  final String? requestedOfficeName;
}

int _toInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}
