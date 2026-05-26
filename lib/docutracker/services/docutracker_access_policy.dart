import 'package:flutter/material.dart';

import '../models/document.dart';

/// Centralized access rules for DocuTracker UI and data restrictions.
abstract final class DocuTrackerAccessPolicy {
  DocuTrackerAccessPolicy._();

  static const double mobileBreakpoint = 600;

  static const Set<String> mobileRestrictedRoutes = <String>{
    '/admin-settings',
    '/docutracker/admin',
    '/docutracker/workflow-editor',
    '/docutracker/permissions',
  };

  static bool isMobileWidth(double width) => width < mobileBreakpoint;

  static bool isMobileContext(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return isMobileWidth(width);
  }

  static bool isRouteRestrictedOnMobile(String? routeName) {
    if (routeName == null || routeName.isEmpty) return false;
    return mobileRestrictedRoutes.contains(routeName);
  }

  static bool canAccessAdminSurface({
    required bool isMobile,
    required bool isAdmin,
  }) {
    return !isMobile && isAdmin;
  }

  static bool canAccessDocumentInMobile({
    required DocuTrackerDocument document,
    required String userId,
  }) {
    final uid = userId.trim();
    if (uid.isEmpty) return false;
    return document.createdBy == uid;
  }

  static List<DocuTrackerDocument> filterDocumentsForMobileUser(
    List<DocuTrackerDocument> documents, {
    required String userId,
  }) {
    return documents
        .where((d) => canAccessDocumentInMobile(document: d, userId: userId))
        .toList();
  }
}
