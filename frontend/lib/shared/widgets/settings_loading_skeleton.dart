import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'skeleton_bone.dart';

class SettingsDetailsSkeleton extends StatelessWidget {
  const SettingsDetailsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading settings details',
    child: const ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBone(width: 200, height: 36),
          SizedBox(height: 24),
          SkeletonBone(width: 120, height: 14),
          SizedBox(height: 10),
          SkeletonBone(width: 180, height: 20),
          SizedBox(height: 28),
          SkeletonBone(width: 150, height: 14),
          SizedBox(height: 16),
          SkeletonBone(height: 40, width: double.infinity),
          SizedBox(height: 16),
          SkeletonBone(height: 48, width: double.infinity),
          SizedBox(height: 16),
          SkeletonBone(width: 140, height: 36),
        ],
      ),
    ),
  );
}

/// Matches the responsive list/detail layout while its data is loading.
class SettingsMasterDetailSkeleton extends StatelessWidget {
  const SettingsMasterDetailSkeleton({super.key});

  Widget _panel(BuildContext context, Widget child) => Container(
    decoration: BoxDecoration(
      color: AppTheme.dashPanelOf(context),
      border: Border.all(color: AppTheme.dashHairlineOf(context)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: SingleChildScrollView(
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading settings',
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final list = _panel(
            context,
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBone(height: 48, width: double.infinity),
                SizedBox(height: 32),
                SkeletonBone(height: 16, width: 110),
                SizedBox(height: 20),
                SkeletonBone(height: 52, width: double.infinity),
                SizedBox(height: 16),
                SkeletonBone(height: 52, width: double.infinity),
                SizedBox(height: 16),
                SkeletonBone(height: 52, width: double.infinity),
              ],
            ),
          );
          if (constraints.maxWidth < 760) {
            return SizedBox.expand(child: list);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: constraints.maxWidth < 1000 ? 260 : 310,
                child: list,
              ),
              const SizedBox(width: 24),
              Expanded(child: _panel(context, const SettingsDetailsSkeleton())),
            ],
          );
        },
      ),
    ),
  );
}
