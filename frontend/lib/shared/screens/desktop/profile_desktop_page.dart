import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/shared/screens/profile_page.dart';

class ProfileDesktopPage extends StatelessWidget {
  const ProfileDesktopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.dashCanvasOf(context),
      appBar: AppBar(
        backgroundColor: AppTheme.dashPanelOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          color: AppTheme.dashTextPrimaryOf(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: SizedBox(width: double.infinity, child: ProfileContent()),
      ),
    );
  }
}
