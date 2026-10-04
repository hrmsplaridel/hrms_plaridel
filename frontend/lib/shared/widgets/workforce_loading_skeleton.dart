import 'package:flutter/material.dart';
import 'skeleton_bone.dart';

/// Row placeholders that fit the surrounding workforce table's columns.
class WorkforceRowsSkeleton extends StatelessWidget {
  const WorkforceRowsSkeleton({
    super.key,
    this.columns = const [1, 2, 3],
    this.rows = 5,
    this.cellHeight = 16,
    this.label = 'Loading records',
  });

  final List<int> columns;
  final int rows;
  final double cellHeight;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: Column(
        children: List.generate(
          rows,
          (row) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Row(
              children: [
                for (var column = 0; column < columns.length; column++) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: columns[column],
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: cellHeight > 20
                            ? 1
                            : (row.isEven ? 0.8 : 0.65),
                        child: SkeletonBone(height: cellHeight),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class WeeklyScheduleSkeleton extends StatelessWidget {
  const WeeklyScheduleSkeleton({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    primary: false,
    child: SizedBox(
      width: 1000,
      child: WorkforceRowsSkeleton(
        columns: const [2, 1, 1, 1, 1, 1, 1, 1],
        cellHeight: 48,
        rows: 5,
        label: 'Loading weekly schedule',
      ),
    ),
  );
}
