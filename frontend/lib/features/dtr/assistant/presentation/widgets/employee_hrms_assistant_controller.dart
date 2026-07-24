import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:hrms_plaridel/features/dtr/assistant/presentation/pages/employee_dtr_assistant_page.dart';
import 'package:hrms_plaridel/features/dtr/assistant/presentation/widgets/hrms_assistant_floating_frame.dart';

class EmployeeHrmsAssistantController {
  EmployeeHrmsAssistantController._();

  static final EmployeeHrmsAssistantController instance =
      EmployeeHrmsAssistantController._();

  OverlayEntry? _floatingEntry;
  final ValueNotifier<bool> _floatingVisible = ValueNotifier<bool>(false);

  bool get isFloatingVisible => _floatingEntry != null;
  ValueListenable<bool> get floatingVisible => _floatingVisible;

  void showFloating(BuildContext context) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _showInOverlay(overlay);
  }

  void hideFloating() {
    _floatingEntry?.remove();
    _floatingEntry = null;
    _floatingVisible.value = false;
  }

  Future<void> openFullPage(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    hideFloating();
    await _pushFullPage(navigator);
  }

  void _showInOverlay(OverlayState overlay) {
    if (_floatingEntry != null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return HrmsAssistantFloatingFrame(
          child: EmployeeDtrAssistantPage(
            floating: true,
            onClose: hideFloating,
            onExpand: () => _expandFromFloating(context),
          ),
        );
      },
    );
    _floatingEntry = entry;
    overlay.insert(entry);
    _floatingVisible.value = true;
  }

  void _expandFromFloating(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    hideFloating();
    unawaited(_pushFullPage(navigator));
  }

  Future<void> _pushFullPage(NavigatorState navigator) {
    return navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (pageContext) => EmployeeDtrAssistantPage(
          onMinimize: () {
            final overlay = Overlay.of(pageContext, rootOverlay: true);
            Navigator.of(pageContext, rootNavigator: true).pop();
            _showInOverlay(overlay);
          },
        ),
      ),
    );
  }
}
