import 'package:flutter/material.dart';

/// Stacked account cards below this width (tablet / mobile).
const double kProfileAccountTwoColumnBreakpoint = 1024;

/// Full 4/8 split on large desktops.
const double kProfileAccountLargeDesktopBreakpoint = 1440;

/// Desktop: employment+contact | personal+address. Mobile: specified stack order.
class ProfileAccountResponsiveLayout extends StatelessWidget {
  const ProfileAccountResponsiveLayout({
    super.key,
    required this.isWide,
    required this.employment,
    required this.contact,
    required this.personal,
    required this.address,
    required this.actions,
  });

  final bool isWide;
  final Widget employment;
  final Widget contact;
  final Widget personal;
  final Widget address;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = MediaQuery.sizeOf(context).width;
        final twoColumn =
            isWide && pageWidth >= kProfileAccountTwoColumnBreakpoint;
        final width = constraints.maxWidth;

        if (!twoColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              employment,
              const SizedBox(height: 16),
              personal,
              const SizedBox(height: 16),
              contact,
              const SizedBox(height: 16),
              address,
              const SizedBox(height: 16),
              actions,
            ],
          );
        }

        const gap = 16.0;
        final available = (width - gap).clamp(0.0, double.infinity);
        final leftFr =
            pageWidth >= kProfileAccountLargeDesktopBreakpoint ? 4 : 5;
        final rightFr =
            pageWidth >= kProfileAccountLargeDesktopBreakpoint ? 8 : 7;
        final totalFr = leftFr + rightFr;
        var leftWidth = available * (leftFr / totalFr);
        if (leftWidth < 320 && available > 320) {
          leftWidth = 320;
        }
        final rightWidth = (available - leftWidth).clamp(0.0, double.infinity);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: leftWidth,
                  child: Column(
                    children: [
                      employment,
                      const SizedBox(height: 16),
                      contact,
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: rightWidth,
                  child: Column(
                    children: [
                      personal,
                      const SizedBox(height: 16),
                      address,
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            actions,
          ],
        );
      },
    );
  }
}

class ProfileShellBodyPadding extends StatelessWidget {
  const ProfileShellBodyPadding({
    super.key,
    required this.isWide,
    required this.child,
  });

  final bool isWide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isWide ? 20 : 16,
        8,
        isWide ? 20 : 16,
        isWide ? 20 : 16,
      ),
      child: child,
    );
  }
}
