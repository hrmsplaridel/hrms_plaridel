import '../widgets/approval_workflows_panel.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_official_signatories_screen.dart';

class ApprovalsSignatoriesPage extends StatefulWidget {
  const ApprovalsSignatoriesPage({super.key});

  @override
  State<ApprovalsSignatoriesPage> createState() =>
      _ApprovalsSignatoriesPageState();
}

class _ApprovalsSignatoriesPageState extends State<ApprovalsSignatoriesPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: SizedBox(
      height: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Approvals & Signatories',
            style: TextStyle(
              color: AppTheme.dashTextPrimaryOf(context),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.dashPanelOf(context),
              border: Border.all(color: AppTheme.dashHairlineOf(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TabBar(
              key: const PageStorageKey('dtr-approvals-tabs'),
              onTap: (index) => setState(() => _tab = index),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: const BoxDecoration(color: AppTheme.primaryNavy),
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.dashTextSecondaryOf(context),
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(
                  height: 46,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Workflows'),
                    ],
                  ),
                ),
                Tab(
                  height: 46,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.draw_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Report Signatories'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                const ApprovalWorkflowsPanel(useSidePanel: true),
                const DocuTrackerOfficialSignatoriesScreen(dtrOnly: true),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
