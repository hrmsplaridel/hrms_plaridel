import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';
import 'package:hrms_plaridel/features/landing/presentation/widgets/section_container.dart';

/// Footer: branding, legal links, copyright.
class FooterSection extends StatelessWidget {
  const FooterSection({super.key});

  static const _logoAsset = 'assets/images/Plaridel Logo.jpg';

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 800;
    final isCompact = width < 480;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryNavyDark,
            AppTheme.primaryNavy,
            Color(0xFFD84315),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.35),
                    Colors.white.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            top: -40,
            right: -30,
            child: _FooterOrb(size: 160, opacity: 0.07),
          ),
          const Positioned(
            bottom: -50,
            left: -40,
            child: _FooterOrb(size: 200, opacity: 0.06),
          ),
          SectionContainer(
            backgroundColor: Colors.transparent,
            withShadow: false,
            padding: EdgeInsets.fromLTRB(
              isWide ? 80 : 24,
              isWide ? 44 : 32,
              isWide ? 80 : 24,
              isWide ? 28 : 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isWide)
                  const _FooterWideBody()
                else
                  const _FooterNarrowBody(),
                const SizedBox(height: 28),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                const SizedBox(height: 18),
                _FooterCopyrightBar(isCompact: isCompact),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _onDataPrivacy(BuildContext context) {
    // Ready for backend / policy page
  }

  static void _onTermsOfService(BuildContext context) {
    // Ready for backend / terms page
  }
}

class _FooterWideBody extends StatelessWidget {
  const _FooterWideBody();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: _FooterBrandBlock()),
        const SizedBox(width: 32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const _FooterSectionLabel('Legal & policies'),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _FooterLink(
                    label: 'Data Privacy Notice',
                    icon: Icons.privacy_tip_outlined,
                    onTap: () => FooterSection._onDataPrivacy(context),
                  ),
                  _FooterLink(
                    label: 'Terms of Service',
                    icon: Icons.gavel_outlined,
                    onTap: () => FooterSection._onTermsOfService(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FooterNarrowBody extends StatelessWidget {
  const _FooterNarrowBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _FooterBrandBlock(centered: true),
        const SizedBox(height: 24),
        const _FooterSectionLabel('Legal & policies', centered: true),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            _FooterLink(
              label: 'Data Privacy Notice',
              icon: Icons.privacy_tip_outlined,
              onTap: () => FooterSection._onDataPrivacy(context),
            ),
            _FooterLink(
              label: 'Terms of Service',
              icon: Icons.gavel_outlined,
              onTap: () => FooterSection._onTermsOfService(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _FooterBrandBlock extends StatelessWidget {
  const _FooterBrandBlock({this.centered = false});

  final bool centered;

  @override
  Widget build(BuildContext context) {
    final align = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        Row(
          mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
          children: [
            const _FooterLogo(size: 56),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                crossAxisAlignment: align,
                children: [
                  Text(
                    'Municipality of Plaridel',
                    textAlign: textAlign,
                    style: const TextStyle(
                      color: AppTheme.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Human Resource Management System',
                    textAlign: textAlign,
                    style: TextStyle(
                      color: AppTheme.white.withValues(alpha: 0.88),
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
        SizedBox(height: centered ? 14 : 16),
        Wrap(
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: const [
            _FooterChip(
              icon: Icons.verified_outlined,
              label: 'Official website',
            ),
            _FooterChip(
              icon: Icons.account_balance_outlined,
              label: 'CSC-aligned HR',
            ),
          ],
        ),
      ],
    );
  }
}

class _FooterCopyrightBar extends StatelessWidget {
  const _FooterCopyrightBar({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;

    if (isCompact) {
      return Column(
        children: [
          Text(
            '© $year Municipality of Plaridel',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.white.withValues(alpha: 0.78),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.white.withValues(alpha: 0.65),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          _FooterAsensoMark(),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            '© $year Municipality of Plaridel. All rights reserved.',
            style: TextStyle(
              color: AppTheme.white.withValues(alpha: 0.75),
              fontSize: 12.5,
            ),
          ),
        ),
        const _FooterAsensoMark(),
      ],
    );
  }
}

class _FooterAsensoMark extends StatelessWidget {
  const _FooterAsensoMark();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.white.withValues(alpha: 0.9),
        ),
        children: [
          TextSpan(
            text: 'Asenso ',
            style: TextStyle(color: AppTheme.white.withValues(alpha: 0.95)),
          ),
          TextSpan(
            text: 'PLARIDEL',
            style: TextStyle(
              color: AppTheme.primaryNavyLight.withValues(alpha: 0.95),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLogo extends StatelessWidget {
  const _FooterLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          FooterSection._logoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: Colors.white.withValues(alpha: 0.12),
            child: Icon(
              Icons.account_balance,
              color: Colors.white.withValues(alpha: 0.9),
              size: size * 0.45,
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterSectionLabel extends StatelessWidget {
  const _FooterSectionLabel(this.text, {this.centered = false});

  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        color: AppTheme.white.withValues(alpha: 0.55),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _FooterChip extends StatelessWidget {
  const _FooterChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.white.withValues(alpha: 0.92),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatefulWidget {
  const _FooterLink({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: kIsWeb ? (_) => setState(() => _hovering = true) : null,
      onExit: kIsWeb ? (_) => setState(() => _hovering = false) : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _hovering ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: _hovering ? 0.45 : 0.28),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: AppTheme.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: _hovering ? 0.95 : 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterOrb extends StatelessWidget {
  const _FooterOrb({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
      ),
    );
  }
}
