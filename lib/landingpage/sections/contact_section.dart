import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../constants/app_theme.dart';
import '../widgets/section_container.dart';

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Contact Us',
                style: TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: isWide ? 30 : 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 56,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryNavy,
                      AppTheme.primaryNavy.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Get in touch with the Human Resource Management and Development Office',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: isWide ? 17 : 15,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(height: isWide ? 40 : 32),
              isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: _ContactDetailsCard(
                            child: Column(
                              children: [
                                _ContactItem(
                                  icon: Icons.location_on_outlined,
                                  label: 'Office Address',
                                  value: _officeAddress,
                                ),
                                _contactDivider(),
                                _ContactItem(
                                  icon: Icons.phone_outlined,
                                  label: 'Contact Number',
                                  value: '(088) 3448-200',
                                ),
                                _contactDivider(),
                                _ContactItem(
                                  icon: Icons.email_outlined,
                                  label: 'Official Email',
                                  value: _officialEmails,
                                ),
                                _contactDivider(),
                                _ContactItem(
                                  icon: Icons.access_time_outlined,
                                  label: 'Office Hours',
                                  value: 'Monday - Friday, 8:00 AM - 5:00 PM',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 28),
                        const Expanded(flex: 1, child: _OfficeMap()),
                      ],
                    )
                  : Column(
                      children: [
                        _ContactDetailsCard(
                          child: Column(
                            children: [
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
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Divider(
      height: 1,
      thickness: 1,
      color: AppTheme.lightGray.withValues(alpha: 0.85),
    ),
  );
}

/// White panel wrapping contact rows for clearer grouping.
class _ContactDetailsCard extends StatelessWidget {
  const _ContactDetailsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E6EA)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: child,
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryNavy.withValues(alpha: 0.14),
                  AppTheme.primaryNavy.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(
                color: AppTheme.primaryNavy.withValues(alpha: 0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.07),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: AppTheme.primaryNavy, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.15,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: AppTheme.bodySize,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
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
    return Ink(
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
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.white,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(
                Icons.location_on_rounded,
                size: 48,
                color: AppTheme.primaryNavy,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Municipal Hall of Plaridel',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: isWide ? 17 : 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Misamis Occidental',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
    final mapHeight = isWide ? 248.0 : 212.0;
    final showWebView =
        _officeMapEmbedSupported() && !_embedFailed && _controller != null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E6EA)),
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.09),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.065),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: mapHeight,
            child: showWebView
                ? ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        WebViewWidget(controller: _controller!),
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
                                    Colors.black.withValues(alpha: 0.62),
                                  ],
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  28,
                                  16,
                                  12,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Municipal Hall of Plaridel',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isWide ? 17 : 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
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
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        shadows: const [
                                          Shadow(
                                            color: Color(0x80000000),
                                            blurRadius: 4,
                                            offset: Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : _OfficeMapStaticFallback(isWide: isWide),
          ),
          Divider(height: 1, thickness: 1, color: AppTheme.lightGray),
          Material(
            color: AppTheme.white,
            child: InkWell(
              onTap: _openPlaridelMunicipalHallMaps,
              hoverColor: AppTheme.primaryNavy.withValues(alpha: 0.06),
              splashColor: AppTheme.primaryNavy.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 20,
                      color: AppTheme.primaryNavy,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Open in Google Maps',
                      style: TextStyle(
                        color: AppTheme.primaryNavy,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: AppTheme.primaryNavy.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
