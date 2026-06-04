import 'package:flutter/material.dart';

class ProfileAccountResponsiveLayout extends StatelessWidget {
  const ProfileAccountResponsiveLayout({
    super.key,
    required this.isWide,
    required this.about,
    required this.personal,
  });

  final bool isWide;
  final Widget about;
  final Widget personal;

  @override
  Widget build(BuildContext context) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 34, child: about),
          const SizedBox(width: 24),
          Expanded(flex: 66, child: personal),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [about, const SizedBox(height: 16), personal],
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
        isWide ? 28 : 16,
        0,
        isWide ? 28 : 16,
        isWide ? 28 : 20,
      ),
      child: child,
    );
  }
}
