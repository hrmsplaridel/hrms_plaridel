import 'package:flutter/material.dart';

/// Owns editor-exit handlers for one Forms hub session (RSP or L&D).
///
/// Back order:
/// 1. Exit the open record editor → form records list
/// 2. Leave the form → Forms picker
/// 3. Leave Forms → RSP / L&D hub
class RspLdFormNavController {
  RspLdFormNavController({required this.onChanged});

  final VoidCallback onChanged;
  final Map<Object, bool Function()> _exits = {};

  bool get hasActiveEditor => _exits.isNotEmpty;

  void register(Object owner, bool Function() tryExitEditor) {
    final wasActive = hasActiveEditor;
    _exits[owner] = tryExitEditor;
    if (!wasActive) onChanged();
  }

  void unregister(Object owner) {
    final wasActive = hasActiveEditor;
    if (_exits.remove(owner) != null && wasActive && !hasActiveEditor) {
      onChanged();
    }
  }

  /// Returns true when an open editor handled Back (records list is showing).
  bool tryExitEditor() {
    if (_exits.isEmpty) return false;
    final handlers = _exits.values.toList(growable: false);
    for (var i = handlers.length - 1; i >= 0; i--) {
      if (handlers[i]()) return true;
    }
    return false;
  }
}

/// Provides [RspLdFormNavController] to form sections under the Forms hub.
class RspLdFormNavScope extends InheritedWidget {
  const RspLdFormNavScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final RspLdFormNavController controller;

  static RspLdFormNavController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RspLdFormNavScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(covariant RspLdFormNavScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

/// Registers editor exit with the nearest [RspLdFormNavScope] while mounted.
mixin RspLdFormEditorNavMixin<T extends StatefulWidget> on State<T> {
  RspLdFormNavController? _formNav;

  /// True while Add/Edit form UI is open (not the records list).
  bool get isFormEditorOpen;

  /// Close the editor and show this form's records list.
  void exitFormEditor();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = RspLdFormNavScope.maybeOf(context);
    if (identical(_formNav, nav)) {
      _syncRegistration();
      return;
    }
    _formNav?.unregister(this);
    _formNav = nav;
    _syncRegistration();
  }

  void _syncRegistration() {
    final nav = _formNav;
    if (nav == null) return;
    if (isFormEditorOpen) {
      nav.register(this, () {
        if (!isFormEditorOpen) return false;
        exitFormEditor();
        return true;
      });
    } else {
      nav.unregister(this);
    }
  }

  /// Call after setState changes that open/close the editor.
  void notifyFormEditorNav() => _syncRegistration();

  @override
  void dispose() {
    _formNav?.unregister(this);
    _formNav = null;
    super.dispose();
  }
}
