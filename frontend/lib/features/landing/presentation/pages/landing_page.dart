import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hrms_plaridel/features/recruitment/models/job_vacancy_announcement.dart';
import 'package:hrms_plaridel/main.dart' as app;
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/pages/application_flow_page.dart';
import 'package:hrms_plaridel/features/landing/presentation/sections/header_section.dart';
import 'package:hrms_plaridel/features/landing/presentation/sections/hero_section.dart';
import 'package:hrms_plaridel/features/landing/presentation/sections/job_vacancies_section.dart';
import 'package:hrms_plaridel/features/landing/presentation/sections/contact_section.dart';
import 'package:hrms_plaridel/features/landing/presentation/sections/footer_section.dart';

/// Landing page for the Government HRMS (Municipality of Plaridel).
/// All related UI lives under the [landingpage] folder. No public registration on this page;
/// registration is only available after passing the screening exam.
/// Polls job vacancy data so admin toggle/save/delete changes show without a manual refresh.
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with RouteAware, WidgetsBindingObserver {
  static const _vacancyPollInterval = Duration(seconds: 5);

  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _heroKey = GlobalKey();
  final GlobalKey _jobVacanciesKey = GlobalKey();
  final GlobalKey _contactKey = GlobalKey();

  JobVacancyAnnouncement _announcement = const JobVacancyAnnouncement(
    hasVacancies: false,
  );
  bool _loadingAnnouncement = true;
  Timer? _vacancyPollTimer;
  bool _vacancyReloadInFlight = false;
  final ScrollController _scrollController = ScrollController();
  bool _didInitialScrollReset = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reloadVacancies();
    _vacancyPollTimer = Timer.periodic(
      _vacancyPollInterval,
      (_) => _reloadVacancies(silent: true),
    );

    // Ensure the landing page always opens at the hero (not scrolled down).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didInitialScrollReset) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
        _didInitialScrollReset = true;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      app.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _vacancyPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    app.routeObserver.unsubscribe(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadVacancies(silent: true);
    }
  }

  @override
  void didPopNext() {
    _reloadVacancies(silent: true);

    // Some platforms/browsers preserve scroll position when navigating back.
    // Always reset to the top so the hero shows consistently.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  Future<void> _reloadVacancies({bool silent = false}) async {
    if (_vacancyReloadInFlight) return;
    _vacancyReloadInFlight = true;
    try {
      final next = await JobVacancyAnnouncementRepo.instance.fetchIfAvailable();
      if (!mounted) return;
      if (next == null) {
        // Keep the last successful listing. Do not fake "closed" on a network blip.
        if (!silent && _loadingAnnouncement) {
          setState(() => _loadingAnnouncement = false);
        }
        return;
      }
      final sameListing =
          !_loadingAnnouncement &&
          next.publicListingFingerprint ==
              _announcement.publicListingFingerprint;
      if (sameListing) return;
      setState(() {
        _announcement = next;
        _loadingAnnouncement = false;
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() => _loadingAnnouncement = false);
    } finally {
      _vacancyReloadInFlight = false;
    }
  }

  void _scrollTo(GlobalKey key, {double alignment = 0.0}) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: alignment,
      );
    }
  }

  void _onApplyForVacancy(JobVacancyItem vacancy) {
    if (!_announcement.isAcceptingApplications) return;
    final selected = vacancy.headline?.trim();
    if (selected == null || selected.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ApplicationFlowPage(selectedPositionHeadline: selected),
      ),
    );
  }

  void _onTrackApplication() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ApplicationFlowPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          HeaderSection(
            key: _headerKey,
            onHomeTap: () => _scrollTo(_heroKey),
            onJobVacanciesTap: () => _scrollTo(_jobVacanciesKey),
            onRecruitmentProcessTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const ApplicationFlowPage(),
              ),
            ),
            onContactTap: () => _scrollTo(_contactKey),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HeroSection(
                        key: _heroKey,
                        height: constraints.maxHeight,
                        onViewVacanciesTap: () => _scrollTo(_jobVacanciesKey),
                        onScrollToVacancies: () => _scrollTo(_jobVacanciesKey),
                        onTrackApplicationTap: _onTrackApplication,
                      ),
                      const SizedBox(height: 8),
                      KeyedSubtree(
                        key: _jobVacanciesKey,
                        child: _loadingAnnouncement
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 48),
                                child: Center(
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                ),
                              )
                            : JobVacanciesSection(
                                hasVacancies: _announcement.hasVacancies,
                                headline: _announcement.headline,
                                body: _announcement.body,
                                vacancies: _announcement.listedVacancies.isEmpty
                                    ? null
                                    : _announcement.listedVacancies,
                                onGoToRecruitmentTap: null,
                                onApplyForVacancyTap:
                                    _announcement.isAcceptingApplications
                                    ? _onApplyForVacancy
                                    : null,
                              ),
                      ),
                      ContactSection(key: _contactKey),
                      const FooterSection(),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
