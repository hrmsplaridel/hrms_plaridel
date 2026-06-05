import 'package:flutter/material.dart';
import 'package:hrms_plaridel/shared/widgets/dashboard_mobile_bottom_nav.dart';

const employeeDashboardMobileNavItems = [
  DashboardMobileNavItem(icon: Icons.home_outlined, label: 'Dashboard'),
  DashboardMobileNavItem(
    icon: Icons.event_available_outlined,
    label: 'My Attendance',
    shortLabel: 'Attendance',
  ),
  DashboardMobileNavItem(
    icon: Icons.event_busy_outlined,
    label: 'My Leave',
    shortLabel: 'Leave',
  ),
  DashboardMobileNavItem(
    icon: Icons.pin_drop_outlined,
    label: 'Locator Slip',
    shortLabel: 'Locator',
  ),
  DashboardMobileNavItem(
    icon: Icons.assignment_outlined,
    label: 'Training Reports',
    shortLabel: 'Training',
  ),
  DashboardMobileNavItem(
    icon: Icons.fact_check_outlined,
    label: 'Training Requirements',
    shortLabel: 'Requirements',
  ),
  DashboardMobileNavItem(
    icon: Icons.description_outlined,
    label: 'DocuTracker',
  ),
];
