import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final _preparations = Expando<PdfPreviewPreparation>();

/// Prepares a preview under a cancellable barrier covering the caller's work
/// area. Cancellation discards pending results; it does not undo server work.
Future<T?> preparePdfPreview<T extends Object>({
  required BuildContext context,
  required Future<T> Function(PdfPreviewPreparation task) prepare,
}) async {
  if (!context.mounted) return null;
  var navigator = Navigator.of(context);
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  Route<dynamic>? rootRoute;
  // Desktop panels are root popup routes even when their action callback
  // retains a context from the nested dashboard navigator underneath.
  rootNavigator.popUntil((candidate) {
    rootRoute = candidate;
    return true;
  });
  if (rootRoute is PopupRoute<dynamic>) navigator = rootNavigator;
  final previous = _preparations[navigator];
  if (previous != null) {
    if (previous.isActive) return null;
    previous._cancel();
  }
  Route<dynamic>? route;
  // An always-true predicate inspects the top route without popping it. The
  // action's context may belong to the page beneath an open details panel.
  navigator.popUntil((candidate) {
    route = candidate;
    return true;
  });
  final ownerRoute = route;
  final ownerContext =
      ownerRoute is ModalRoute<dynamic> && ownerRoute != ModalRoute.of(context)
      ? ownerRoute.subtreeContext ?? context
      : context;
  final task = PdfPreviewPreparation._(ownerContext, navigator, route);
  _preparations[navigator] = task;
  task._show();
  if (!task.isActive) return null;
  try {
    final work = Future<T>.sync(() => prepare(task)).then<T?>(
      (value) => task.isActive ? value : null,
      onError: (Object error, StackTrace stack) {
        if (!task.isActive) return null;
        Error.throwWithStackTrace(error, stack);
      },
    );
    return await Future.any<T?>([
      work,
      task._cancelled.future.then((_) => null),
    ]);
  } finally {
    task._finish();
  }
}

class PdfPreviewPreparation {
  PdfPreviewPreparation._(this._context, this._navigator, this._route);

  final BuildContext _context;
  final NavigatorState _navigator;
  final Route<dynamic>? _route;
  final _cancelled = Completer<void>();
  OverlayEntry? _entry;
  LocalHistoryEntry? _history;
  Timer? _watch;
  bool _finished = false;
  Rect _bounds = Rect.zero;

  bool get isActive {
    if (_finished ||
        _cancelled.isCompleted ||
        !_context.mounted ||
        _route?.isCurrent == false) {
      return false;
    }
    var offstage = false;
    _context.visitAncestorElements((element) {
      if (element.widget is Offstage && (element.widget as Offstage).offstage) {
        offstage = true;
        return false;
      }
      return true;
    });
    return !offstage;
  }

  /// Stop before starting another expensive preparation stage after Cancel.
  void checkActive() {
    if (isActive) return;
    _cancel();
    throw const _PreparationCancelled();
  }

  Rect _measure() {
    if (!_context.mounted) return Rect.zero;
    var box = _context.findRenderObject();
    // Button callbacks can supply a small context; find the containing work
    // area so the progress card and Cancel remain usable.
    if (box is RenderBox &&
        box.hasSize &&
        (box.size.width < 280 || box.size.height < 260)) {
      _context.visitAncestorElements((element) {
        final candidate = element.findRenderObject();
        if (candidate is RenderBox &&
            candidate.hasSize &&
            candidate.size.width >= 280 &&
            candidate.size.height >= 260) {
          box = candidate;
          return false;
        }
        return true;
      });
    }
    final overlay = _navigator.overlay?.context.findRenderObject();
    final area = box;
    if (area is! RenderBox ||
        overlay is! RenderBox ||
        !area.attached ||
        !area.hasSize ||
        !overlay.hasSize) {
      return Rect.zero;
    }
    return (area.localToGlobal(Offset.zero, ancestor: overlay) & area.size)
        .intersect(Offset.zero & overlay.size);
  }

  void _show() {
    _bounds = _measure();
    if (_bounds.isEmpty || !isActive) {
      _cancel();
      return;
    }
    _entry = OverlayEntry(
      builder: (_) => Positioned.fromRect(
        rect: _bounds,
        child: _PreparationBarrier(onCancel: _cancel),
      ),
    );
    _navigator.overlay!.insert(_entry!);
    final route = _route;
    if (route is ModalRoute<dynamic>) {
      _history = LocalHistoryEntry(
        onRemove: _cancel,
        impliesAppBarDismissal: false,
      );
      route.addLocalHistoryEntry(_history!);
    }
    _watch = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!isActive) {
        _cancel();
        return;
      }
      final bounds = _measure();
      if (bounds.isEmpty) {
        _cancel();
      } else if (bounds != _bounds) {
        _bounds = bounds;
        _entry?.markNeedsBuild();
      }
    });
  }

  void _cancel() {
    if (_finished) return;
    if (!_cancelled.isCompleted) _cancelled.complete();
    _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _watch?.cancel();
    _entry?.remove();
    _entry?.dispose();
    _history?.remove();
    if (identical(_preparations[_navigator], this)) {
      _preparations[_navigator] = null;
    }
  }
}

class _PreparationCancelled implements Exception {
  const _PreparationCancelled();
}

class _PreparationBarrier extends StatelessWidget {
  const _PreparationBarrier({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => FocusScope(
    autofocus: true,
    child: Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        return [
              LogicalKeyboardKey.tab,
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.space,
            ].contains(event.logicalKey)
            ? KeyEventResult.ignored
            : KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ColoredBox(
          color: Colors.black.withValues(alpha: .25),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.description_outlined, size: 30),
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: const Text(
                            'Preparing preview…',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        TextButton(
                          autofocus: true,
                          onPressed: onCancel,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
