import 'package:flutter/material.dart';
import '../../data/job_vacancy_announcement.dart';
import '../../login/screens/login_page.dart';
import '../constants/app_theme.dart';
import '../sections/header_section.dart';
import '../sections/hero_section.dart';
import '../sections/recruitment_process_section.dart';
import '../sections/job_vacancies_section.dart';
import '../sections/contact_section.dart';
import '../sections/footer_section.dart';

/// Landing page for the Government HRMS (Municipality of Plaridel).
/// All related UI lives under the [landingpage] folder. No public registration on this page;
/// registration is only available after passing the screening exam.
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _heroKey = GlobalKey();
  final GlobalKey _jobVacanciesKey = GlobalKey();
  final GlobalKey _recruitmentProcessKey = GlobalKey();
  final GlobalKey _contactKey = GlobalKey();

  late final Future<JobVacancyAnnouncement> _announcementFuture =
      JobVacancyAnnouncementRepo.instance.fetch();

  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onApplyForJob() {
    // Redirect to pre-application form (no registration; exam first)
    _scrollTo(_recruitmentProcessKey);
  }

  void _onTrackApplication() {
    // Track application status - ready for backend
  }

  void _onViewJobVacancies() {
    _scrollTo(_jobVacanciesKey);
  }

  void _onStartApplication() {
    // Start application (pre-application / screening flow) - ready for backend
  }

  void _onLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.offWhite,
      body: Column(
        children: [
          HeaderSection(
            key: _headerKey,
            onHomeTap: () => _scrollTo(_heroKey),
            onJobVacanciesTap: () => _scrollTo(_jobVacanciesKey),
            onRecruitmentProcessTap: () => _scrollTo(_recruitmentProcessKey),
            onContactTap: () => _scrollTo(_contactKey),
            onLoginTap: _onLogin,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HeroSection(
                    key: _heroKey,
                    onApplyForJobTap: _onApplyForJob,
                    onTrackApplicationTap: _onTrackApplication,
                    onViewJobVacanciesTap: _onViewJobVacancies,
                  ),
                  FutureBuilder<JobVacancyAnnouncement>(
                    future: _announcementFuture,
                    builder: (context, snapshot) {
                      final a = snapshot.data ??
                          const JobVacancyAnnouncement(hasVacancies: true);
                      return JobVacanciesSection(
                        key: _jobVacanciesKey,
                        hasVacancies: a.hasVacancies,
                        headline: a.headline,
                        body: a.body,
                        onGoToRecruitmentTap: () =>
                            _scrollTo(_recruitmentProcessKey),
                      );
                    },
                  ),
                  RecruitmentProcessSection(
                    key: _recruitmentProcessKey,
                    onStartApplicationTap: _onStartApplication,
                  ),
                  ContactSection(key: _contactKey),
                  const FooterSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
