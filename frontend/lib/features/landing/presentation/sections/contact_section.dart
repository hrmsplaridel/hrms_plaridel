import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/landing/presentation/widgets/section_container.dart';

/// Same place string for the embedded map and the external Google Maps link.
const String _plaridelMunicipalHallMapsQuery =
    'Plaridel Municipal Hall, Plaridel, Misamis Occidental, Philippines';

/// Opens **Plaridel, Misamis Occidental** municipal hall area (not the highway alone).
/// Uses explicit place name so Google does not drop the pin on
/// "Dipolog - Oroquieta National Rd" generic segment.
final Uri _plaridelMunicipalHallMapsUri = Uri(
  scheme: 'https',
  host: 'www.google.com',
  path: '/maps/search/',
  queryParameters: {'api': '1', 'query': _plaridelMunicipalHallMapsQuery},
);

/// In-app preview: same query as [_plaridelMunicipalHallMapsUri], embed output.
final Uri _plaridelMunicipalHallMapEmbedUri = Uri.https(
  'maps.google.com',
  '/maps',
  {'q': _plaridelMunicipalHallMapsQuery, 'output': 'embed', 'z': '17'},
);

const _officeAddress = 'Municipal Hall of Plaridel, Misamis Occidental';
const _officialEmails = 'plaridel_misocc@yahoo.com / asensoplaridel@gmail.com';

Future<void> _openPlaridelMunicipalHallMaps() {
  return launchUrl(
    _plaridelMunicipalHallMapsUri,
    mode: LaunchMode.externalApplication,
  );
}

class ContactSection extends StatelessWidget {
  const ContactSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return SectionContainer(
      backgroundColor: AppTheme.offWhite,
      borderRadius: 20,
      withShadow: true,
      margin: const EdgeInsets.symmetric(vertical: 18),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -30,
            right: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryNavy.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryNavy.withValues(alpha: 0.04),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primaryNavy.withValues(alpha: 0.18),
                          AppTheme.primaryNavy.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.15),
                      ),
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      color: AppTheme.primaryNavy,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contact Us',
                        style: TextStyle(
                          color: AppTheme.primaryNavy,
                          fontSize: isWide ? 28 : 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.35,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 72,
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primaryNavy,
                              AppTheme.primaryNavyLight.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Get in touch with the Human Resource Management and Development Office',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: isWide ? 16 : 15,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(height: isWide ? 36 : 28),
              isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _ContactDetailsCard(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _ContactCardHeader(),
                                const SizedBox(height: 4),
                                const _ContactItem(
                                  icon: Icons.location_on_outlined,
                                  label: 'Office Address',
                                  value: _officeAddress,
                                ),
                                _contactDivider(),
                                const _ContactItem(
                                  icon: Icons.phone_outlined,
                                  label: 'Contact Number',
                                  value: '(088) 3448-200',
                                ),
                                _contactDivider(),
                                const _ContactItem(
                                  icon: Icons.email_outlined,
                                  label: 'Official Email',
                                  value: _officialEmails,
                                ),
                                _contactDivider(),
                                const _ContactItem(
                                  icon: Icons.access_time_outlined,
                                  label: 'Office Hours',
                                  value: 'Monday - Friday, 8:00 AM - 5:00 PM',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        const Expanded(child: _OfficeMap()),
                      ],
                    )
                  : Column(
                      children: [
                        _ContactDetailsCard(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _ContactCardHeader(),
                              const SizedBox(height: 4),
                              const _ContactItem(
                                icon: Icons.location_on_outlined,
                                label: 'Office Address',
                                value: _officeAddress,
                              ),
                              _contactDivider(),
                              const _ContactItem(
                                icon: Icons.phone_outlined,
                                label: 'Contact Number',
                                value: '(088) 3448-200',
                              ),
                              _contactDivider(),
                              const _ContactItem(
                                icon: Icons.email_outlined,
                                label: 'Official Email',
                                value: _officialEmails,
                              ),
                              _contactDivider(),
                              const _ContactItem(
                                icon: Icons.access_time_outlined,
                                label: 'Office Hours',
                                value: 'Monday - Friday, 8:00 AM - 5:00 PM',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _OfficeMap(),
                      ],
                    ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _contactDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Divider(
      height: 1,
      thickness: 1,
      indent: 52,
      color: AppTheme.primaryNavy.withValues(alpha: 0.08),
    ),
  );
}

class _ContactCardHeader extends StatelessWidget {
  const _ContactCardHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HRMD OFFICE',
                  style: TextStyle(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Reach us directly',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.15,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.14),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: AppTheme.primaryNavy,
                ),
                SizedBox(width: 5),
                Text(
                  'Mon–Fri',
                  style: TextStyle(
                    color: AppTheme.primaryNavy,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared card chrome for contact list and map panel.
class _ContactPanelCard extends StatelessWidget {
  const _ContactPanelCard({required this.child});

  final Widget child;

  static const _radius = 18.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryNavy, AppTheme.primaryNavyLight],
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// White panel wrapping contact rows for clearer grouping.
class _ContactDetailsCard extends StatelessWidget {
  const _ContactDetailsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _ContactPanelCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: child,
      ),
    );
  }
}

class _MapCardHeader extends StatelessWidget {
  const _MapCardHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VISIT US',
                  style: TextStyle(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Office location',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.15,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.14),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: AppTheme.primaryNavy,
                ),
                SizedBox(width: 5),
                Text(
                  'Municipal Hall',
                  style: TextStyle(
                    color: AppTheme.primaryNavy,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenInMapsChip extends StatelessWidget {
  const _OpenInMapsChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_in_new_rounded,
                size: 15,
                color: AppTheme.primaryNavy,
              ),
              const SizedBox(width: 6),
              Text(
                'Open in Maps',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  const _ContactItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryNavy.withValues(alpha: 0.16),
                  AppTheme.primaryNavy.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.14),
              ),
            ),
            child: Icon(icon, color: AppTheme.primaryNavy, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.65),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Map embed (keep WebView init/load logic intact). ─────────────────────────

/// WebView embed is used on web (iframe-only API) and on mobile/desktop with a
/// full native WebView. Windows/Linux use the static fallback.
bool _officeMapEmbedSupported() {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

/// Pin + title when WebView is unavailable (e.g. Windows/Linux) or embed fails.
class _OfficeMapStaticFallback extends StatelessWidget {
  const _OfficeMapStaticFallback({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openPlaridelMunicipalHallMaps,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.offWhite,
                AppTheme.lightGray.withValues(alpha: 0.65),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.white,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 40,
                    color: AppTheme.primaryNavy,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Municipal Hall of Plaridel',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: isWide ? 16 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Misamis Occidental',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tap to open in Google Maps',
                  style: TextStyle(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Location card with embedded map preview (same place as Google Maps link).
class _OfficeMap extends StatefulWidget {
  const _OfficeMap();

  @override
  State<_OfficeMap> createState() => _OfficeMapState();
}

class _OfficeMapState extends State<_OfficeMap> {
  WebViewController? _controller;
  bool _embedFailed = false;

  @override
  void initState() {
    super.initState();
    if (!_officeMapEmbedSupported()) return;

    // webview_flutter_web only implements loadRequest — not setJavaScriptMode,
    // setBackgroundColor, or setNavigationDelegate (those throw UnimplementedError).
    if (kIsWeb) {
      final c = WebViewController();
      _controller = c;
      c.loadRequest(_plaridelMunicipalHallMapEmbedUri);
      return;
    }

    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFE8EAED));
    _controller = c;
    c
        .setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (WebResourceError error) {
              if (mounted) setState(() => _embedFailed = true);
            },
          ),
        )
        .then((_) => c.loadRequest(_plaridelMunicipalHallMapEmbedUri));
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    final mapHeight = isWide ? 280.0 : 240.0;
    final showWebView =
        _officeMapEmbedSupported() && !_embedFailed && _controller != null;

    return _ContactPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MapCardHeader(),
          SizedBox(
            width: double.infinity,
            height: mapHeight,
            child: showWebView
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      WebViewWidget(controller: _controller!),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: _OpenInMapsChip(
                          onTap: _openPlaridelMunicipalHallMaps,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.55),
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                24,
                                16,
                                10,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Municipal Hall of Plaridel',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: isWide ? 16 : 15,
                                      fontWeight: FontWeight.w700,
                                      shadows: const [
                                        Shadow(
                                          color: Color(0x80000000),
                                          blurRadius: 6,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Misamis Occidental',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.92,
                                      ),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : _OfficeMapStaticFallback(isWide: isWide),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openPlaridelMunicipalHallMaps,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Open in Google Maps'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
