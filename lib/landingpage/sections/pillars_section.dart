import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

class PillarsSection extends StatelessWidget {
  const PillarsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return SectionContainer(
      backgroundColor: AppTheme.white,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Action button in upper right
          Positioned(
            top: 0,
            right: 0,
            child: TextButton.icon(
              onPressed: () => _handleViewAllServices(context),
              icon: const Icon(Icons.apps_outlined, size: 18),
              label: const Text('View All Services'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prime HRM Pillars',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: AppTheme.sectionTitleSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 32),
              isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Expanded(child: _PillarCard(type: _PillarType.rsp)),
                        SizedBox(width: 24),
                        Expanded(child: _PillarCard(type: _PillarType.lnd)),
                      ],
                    )
                  : Column(
                      children: const [
                        _PillarCard(type: _PillarType.rsp),
                        SizedBox(height: 24),
                        _PillarCard(type: _PillarType.lnd),
                      ],
                    ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleViewAllServices(BuildContext context) {
    // Ready for backend integration
  }
}

enum _PillarType { rsp, lnd }

class _PillarCard extends StatefulWidget {
  const _PillarCard({required this.type});

  final _PillarType type;

  @override
  State<_PillarCard> createState() => _PillarCardState();
}

class _PillarCardState extends State<_PillarCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isRsp = widget.type == _PillarType.rsp;
    final title = isRsp
        ? 'Recruitment, Selection & Placement (RSP)'
        : 'Learning & Development (L&D)';
    final icon = isRsp ? Icons.person_search : Icons.school_outlined;
    final features = isRsp
        ? const [
            'Online Job Posting',
            'Online Application Submission',
            'Applicant Tracking',
            'Qualification Screening',
            'Interview & Evaluation Monitoring',
            'Appointment Processing',
          ]
        : const [
            'Training Needs Analysis',
            'Training Program Calendar',
            'Online Training Requests',
            'Attendance Monitoring',
            'Training Evaluation',
            'Employee Development Records',
          ];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _isHovered
                ? AppTheme.primaryNavy.withOpacity(0.5)
                : AppTheme.lightGray,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryNavy.withOpacity(
                _isHovered ? 0.12 : 0.08,
              ),
              blurRadius: _isHovered ? 16 : 12,
              offset: Offset(0, _isHovered ? 4 : 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    icon,
                    color: AppTheme.primaryNavy,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.primaryNavy,
                      fontSize: AppTheme.cardTitleSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '•',
                      style: TextStyle(
                        color: AppTheme.primaryNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: AppTheme.bodySize,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            if (isRsp) ...[
              FilledButton.icon(
                onPressed: () => _handleSubmitApplication(context),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Submit Job Application'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: AppTheme.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _handleTrackStatus(context),
                icon: const Icon(Icons.track_changes_outlined, size: 18),
                label: const Text('Track Application Status'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                  side: const BorderSide(color: AppTheme.primaryNavy, width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: () => _handleViewSchedule(context),
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: const Text('View Training Schedule'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: AppTheme.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _handleSubmitTrainingRequest(context),
                icon: const Icon(Icons.request_quote_outlined, size: 18),
                label: const Text('Submit Training Request'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryNavy,
                  side: const BorderSide(color: AppTheme.primaryNavy, width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleSubmitApplication(BuildContext context) {
    // Ready for backend integration
  }

  void _handleTrackStatus(BuildContext context) {
    // Ready for backend integration
  }

  void _handleViewSchedule(BuildContext context) {
    // Ready for backend integration
  }

  void _handleSubmitTrainingRequest(BuildContext context) {
    // Ready for backend integration
  }
}
