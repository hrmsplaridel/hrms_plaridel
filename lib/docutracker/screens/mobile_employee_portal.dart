import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../docutracker_document_navigation.dart';
import '../docutracker_provider.dart';
import '../models/document.dart';
import '../models/document_status.dart';
import '../services/docutracker_access_policy.dart';
import '../theme/docutracker_tokens.dart';
import '../widgets/docutracker_error_banner.dart';
import '../widgets/docutracker_status_badge.dart';

/// Restricted DocuTracker mobile portal.
///
/// Mobile behavior:
/// - no admin surfaces
/// - no heavy data tables
/// - only current user's own documents
class MobileEmployeePortal extends StatefulWidget {
  const MobileEmployeePortal({super.key});

  @override
  State<MobileEmployeePortal> createState() => _MobileEmployeePortalState();
}

class _MobileEmployeePortalState extends State<MobileEmployeePortal> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMyDocuments());
  }

  Future<void> _loadMyDocuments() async {
    final auth = context.read<AuthProvider>();
    final provider = context.read<DocuTrackerProvider>();
    final userId = auth.user?.id ?? '';
    if (userId.isEmpty) return;

    await provider.loadDocumentsForUser(
      userId: userId,
      roleId: auth.user?.role,
      isAdmin: false,
      mobileRestricted: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<DocuTrackerProvider>();
    final user = auth.user;
    final userId = user?.id ?? '';
    final myDocuments =
        DocuTrackerAccessPolicy.filterDocumentsForMobileUser(
          provider.documents,
          userId: userId,
        )..sort((a, b) {
          final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

    final body = switch (_currentIndex) {
      0 => _MobileMyFilesTab(
        loading: provider.loading,
        docs: myDocuments,
        userId: userId,
        onRefresh: _loadMyDocuments,
      ),
      1 => _MobileTrackingTab(docs: myDocuments, onRefresh: _loadMyDocuments),
      _ => _MobileProfileTab(
        displayName: auth.displayName,
        email: auth.email,
        role: user?.role ?? 'employee',
      ),
    };

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = (viewportHeight * 0.72).clamp(460.0, 760.0);

    return ColoredBox(
      color: DocuTrackerTokens.canvasOf(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Container(
          decoration: DocuTrackerTokens.cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    const Icon(Icons.phone_iphone_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Mobile employee portal',
                      style: TextStyle(
                        color: DocuTrackerTokens.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (provider.error != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DocuTrackerErrorBanner(message: provider.error!),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: panelHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: body,
                ),
              ),
              BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (next) => setState(() => _currentIndex = next),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.folder_copy_outlined),
                    activeIcon: Icon(Icons.folder_copy),
                    label: 'My Files',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.track_changes_outlined),
                    activeIcon: Icon(Icons.track_changes),
                    label: 'Tracking',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline_rounded),
                    activeIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
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

class _MobileMyFilesTab extends StatelessWidget {
  const _MobileMyFilesTab({
    required this.loading,
    required this.docs,
    required this.userId,
    required this.onRefresh,
  });

  final bool loading;
  final List<DocuTrackerDocument> docs;
  final String userId;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading && docs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (docs.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'No personal documents yet.',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final doc = docs[index];
          return InkWell(
            borderRadius: BorderRadius.circular(DocuTrackerTokens.radiusMd),
            onTap: () async {
              await openDocuTrackerDocumentDetail(
                context,
                document: doc,
                isAdmin: false,
                userId: userId,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: DocuTrackerTokens.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DocuTrackerStatusBadge(status: doc.status, compact: true),
                      Text(
                        doc.documentType.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MobileTrackingTab extends StatelessWidget {
  const _MobileTrackingTab({required this.docs, required this.onRefresh});

  final List<DocuTrackerDocument> docs;
  final Future<void> Function() onRefresh;

  int _count(List<DocuTrackerDocument> list, Set<DocumentStatus> statuses) {
    return list.where((d) => statuses.contains(d.status)).length;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _count(docs, {
      DocumentStatus.pending,
      DocumentStatus.inReview,
      DocumentStatus.overdue,
      DocumentStatus.escalated,
      DocumentStatus.returned,
    });
    final done = _count(docs, {
      DocumentStatus.approved,
      DocumentStatus.rejected,
      DocumentStatus.cancelled,
    });

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        children: [
          _MetricCard(label: 'Total files', value: '${docs.length}'),
          const SizedBox(height: 10),
          _MetricCard(label: 'In progress', value: '$pending'),
          const SizedBox(height: 10),
          _MetricCard(label: 'Completed', value: '$done'),
          const SizedBox(height: 14),
          const Text(
            'Mobile access is restricted to personal file tracking only.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _MobileProfileTab extends StatelessWidget {
  const _MobileProfileTab({
    required this.displayName,
    required this.email,
    required this.role,
  });

  final String displayName;
  final String email;
  final String role;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: DocuTrackerTokens.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName.isEmpty ? 'Employee' : displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                email,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 12),
              Text(
                'Role: ${role.toUpperCase()}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
              ),
              const SizedBox(height: 10),
              const Text(
                'Admin settings and workflow configuration are disabled on mobile.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: DocuTrackerTokens.cardDecoration(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
