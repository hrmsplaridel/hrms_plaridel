import 'package:flutter/material.dart';

import '../landingpage/constants/app_theme.dart';

/// Letterhead colors for government header (navy + orange).
const Color _letterheadNavy = Color(0xFF1A237E);

/// Standard header for RSP forms (Municipality of Plaridel HRMD letterhead design).
class RspFormHeader extends StatelessWidget {
  const RspFormHeader({
    super.key,
    required this.formTitle,
    this.subtitle,
  });

  final String formTitle;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Decorative angular shapes (dark blue top-left, orange bottom-left)
        Positioned(
          left: 0,
          top: 0,
          child: CustomPaint(
            size: const Size(48, 48),
            painter: _AngleShapePainter(color: _letterheadNavy, topLeft: true),
          ),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          child: CustomPaint(
            size: const Size(48, 48),
            painter: _AngleShapePainter(color: AppTheme.letterheadOrange, topLeft: false),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 56, right: 8, top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Circular seal (Municipality of Plaridel)
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _letterheadNavy, width: 2),
                      color: Colors.white,
                    ),
                    child: Icon(
                      Icons.account_balance_rounded,
                      color: _letterheadNavy,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Republic of the Philippines',
                        style: TextStyle(color: _letterheadNavy, fontSize: 11),
                      ),
                      Text(
                        'PROVINCE OF MISAMIS OCCIDENTAL',
                        style: TextStyle(
                          color: _letterheadNavy,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'MUNICIPALITY OF PLARIDEL',
                        style: TextStyle(
                          color: _letterheadNavy,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 3,
                        width: 220,
                        color: Colors.black,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE',
                        style: TextStyle(
                          color: AppTheme.letterheadOrange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                formTitle,
                style: TextStyle(
                  color: AppTheme.letterheadOrange,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }
}

/// Paints an angular shape for letterhead decoration (top-left or bottom-left).
class _AngleShapePainter extends CustomPainter {
  _AngleShapePainter({required this.color, required this.topLeft});

  final Color color;
  final bool topLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (topLeft) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(0, size.height);
      path.close();
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(0, 0);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Header variant for Merit Promotion Board forms (e.g. Comparative Assessment, Turn-Around Time).
class RspFormHeaderBoard extends StatelessWidget {
  const RspFormHeaderBoard({
    super.key,
    required this.formTitle,
    this.officeName = 'MGO-Plaridel, Misamis Occidental',
  });

  final String formTitle;
  final String? officeName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Republic of the Philippines',
          style: TextStyle(color: _letterheadNavy, fontSize: 12),
        ),
        Text(
          'PROVINCE OF MISAMIS OCCIDENTAL',
          style: TextStyle(
            color: _letterheadNavy,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'MUNICIPALITY OF PLARIDEL',
          style: TextStyle(
            color: _letterheadNavy,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 2,
          width: 200,
          color: Colors.black,
        ),
        const SizedBox(height: 8),
        Text(
          'HUMAN RESOURCE MERIT PROMOTION AND SELECTION BOARD',
          style: TextStyle(
            color: AppTheme.letterheadOrange,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (officeName != null && officeName!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            officeName!,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          formTitle,
          style: TextStyle(
            color: AppTheme.letterheadOrange,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Standard footer for RSP forms (contact info, Asenso PLARIDEL branding).
class RspFormFooter extends StatelessWidget {
  const RspFormFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _FooterIcon(icon: Icons.phone_rounded),
                  const SizedBox(width: 6),
                  Text(
                    '(088) 3448-200',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                  _FooterIcon(icon: Icons.phone_android_rounded),
                  const SizedBox(width: 6),
                  Text(
                    '(088) 3448-358',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _FooterIcon(icon: Icons.email_rounded),
                  const SizedBox(width: 6),
                  Text(
                    'plaridel_misocc@yahoo.com',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Asenso',
                style: TextStyle(
                  color: _letterheadNavy,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'PLARIDEL',
                style: TextStyle(
                  color: AppTheme.letterheadOrange,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dark blue circular icon for footer contact (matches letterhead design).
class _FooterIcon extends StatelessWidget {
  const _FooterIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: _letterheadNavy,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }
}

/// Underlined-style decoration for form fields (like the physical form's blank lines).
InputDecoration rspUnderlinedField(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
    border: const UnderlineInputBorder(),
    contentPadding: const EdgeInsets.only(bottom: 4),
    isDense: true,
  );
}
