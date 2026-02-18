import 'package:flutter/material.dart';
import '../sections/hero_section.dart';
import '../sections/about_section.dart';
import '../sections/pillars_section.dart';
import '../sections/online_services_section.dart';
import '../sections/transparency_section.dart';
import '../sections/contact_section.dart';
import '../sections/footer_section.dart';

/// Government HRMS Landing Page.
/// Modular structure ready for backend integration.
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: const [
            HeroSection(),
            AboutSection(),
            PillarsSection(),
            OnlineServicesSection(),
            TransparencySection(),
            ContactSection(),
            FooterSection(),
          ],
        ),
      ),
    );
  }
}
