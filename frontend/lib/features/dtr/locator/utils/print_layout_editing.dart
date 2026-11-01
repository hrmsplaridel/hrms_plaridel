import 'dart:math' as math;
import '../models/locator_print_layout.dart';

/// Pure editor operations: array order is the saved back-to-front print order.
class PrintLayoutEditing {
  static Set<String> selection(LocatorPrintLayout layout, Set<String> ids) {
    final groups = layout.elements
        .where((e) => ids.contains(e.id) && e.groupId != null)
        .map((e) => e.groupId)
        .toSet();
    return layout.elements
        .where(
          (e) =>
              ids.contains(e.id) ||
              (e.groupId != null && groups.contains(e.groupId)),
        )
        .map((e) => e.id)
        .toSet();
  }

  static bool editable(LocatorPrintLayout layout, Set<String> ids) =>
      ids.isNotEmpty &&
      !layout.elements.any((e) => ids.contains(e.id) && e.locked);
  static LocatorPrintLayout _map(
    LocatorPrintLayout layout,
    Set<String> ids,
    LocatorPrintElement Function(LocatorPrintElement) change,
  ) => layout.copyWith(
    elements: [
      for (final e in layout.elements) ids.contains(e.id) ? change(e) : e,
    ],
  );
  static LocatorPrintLayout group(
    LocatorPrintLayout layout,
    Set<String> ids,
    String groupId,
  ) {
    ids = selection(layout, ids);
    if (ids.length < 2 || !editable(layout, ids)) return layout;
    return _map(layout, ids, (e) => e.copyWith(groupId: groupId));
  }

  static LocatorPrintLayout ungroup(
    LocatorPrintLayout layout,
    Set<String> ids,
  ) {
    ids = selection(layout, ids);
    if (!editable(layout, ids)) return layout;
    return _map(layout, ids, (e) => e.copyWith(clearGroup: true));
  }

  static LocatorPrintLayout lock(
    LocatorPrintLayout layout,
    Set<String> ids,
    bool locked,
  ) => _map(layout, selection(layout, ids), (e) => e.copyWith(locked: locked));

  static List<List<LocatorPrintElement>> _units(
    LocatorPrintLayout layout,
    Set<String> ids,
  ) {
    final units = <String, List<LocatorPrintElement>>{};
    for (final e in layout.elements.where((e) => ids.contains(e.id))) {
      units
          .putIfAbsent(
            e.groupId == null ? 'item:${e.id}' : 'group:${e.groupId}',
            () => [],
          )
          .add(e);
    }
    return units.values.toList();
  }

  static (double, double, double, double) _bounds(
    List<LocatorPrintElement> items,
  ) => (
    items.map((e) => e.x).reduce(math.min),
    items.map((e) => e.y).reduce(math.min),
    items.map((e) => e.x + e.width).reduce(math.max),
    items.map((e) => e.y + e.height).reduce(math.max),
  );
  static LocatorPrintLayout translate(
    LocatorPrintLayout layout,
    Set<String> ids,
    double dx,
    double dy,
  ) {
    ids = selection(layout, ids);
    if (!editable(layout, ids)) return layout;
    final (left, top, right, bottom) = _bounds(
      layout.elements.where((e) => ids.contains(e.id)).toList(),
    );
    dx = dx.clamp(
      layout.margins.left - left,
      layout.pageWidth - layout.margins.right - right,
    );
    dy = dy.clamp(
      layout.margins.top - top,
      layout.pageHeight - layout.margins.bottom - bottom,
    );
    return _map(layout, ids, (e) => e.copyWith(x: e.x + dx, y: e.y + dy));
  }

  static LocatorPrintLayout align(
    LocatorPrintLayout layout,
    Set<String> ids,
    String alignment,
  ) {
    ids = selection(layout, ids);
    if (!editable(layout, ids)) return layout;
    final units = _units(layout, ids);
    final bounds = units.length == 1
        ? (
            layout.margins.left,
            layout.margins.top,
            layout.pageWidth - layout.margins.right,
            layout.pageHeight - layout.margins.bottom,
          )
        : _bounds(layout.elements.where((e) => ids.contains(e.id)).toList());
    var result = layout;
    for (final unit in units) {
      final b = _bounds(unit);
      final dx = switch (alignment) {
        'left' => bounds.$1 - b.$1,
        'center' => (bounds.$1 + bounds.$3 - b.$1 - b.$3) / 2,
        'right' => bounds.$3 - b.$3,
        _ => 0.0,
      };
      final dy = switch (alignment) {
        'top' => bounds.$2 - b.$2,
        'middle' => (bounds.$2 + bounds.$4 - b.$2 - b.$4) / 2,
        'bottom' => bounds.$4 - b.$4,
        _ => 0.0,
      };
      result = translate(result, unit.map((e) => e.id).toSet(), dx, dy);
    }
    return result;
  }

  static LocatorPrintLayout distribute(
    LocatorPrintLayout layout,
    Set<String> ids, {
    required bool horizontal,
  }) {
    ids = selection(layout, ids);
    if (!editable(layout, ids)) return layout;
    final units = _units(layout, ids)
      ..sort(
        (a, b) => (horizontal ? _bounds(a).$1 : _bounds(a).$2).compareTo(
          horizontal ? _bounds(b).$1 : _bounds(b).$2,
        ),
      );
    if (units.length < 3) return layout;
    final first = _bounds(units.first), last = _bounds(units.last);
    final start = horizontal ? first.$1 : first.$2,
        end = horizontal ? last.$3 : last.$4;
    double extent(List<LocatorPrintElement> unit) {
      final b = _bounds(unit);
      return horizontal ? b.$3 - b.$1 : b.$4 - b.$2;
    }

    final gap =
        (end - start - units.fold(0.0, (n, u) => n + extent(u))) /
        (units.length - 1);
    if (gap < 0) {
      return layout; // Keep overlapping blocks from being pushed outside their bounds.
    }
    var position = start, result = layout;
    for (final unit in units) {
      final b = _bounds(unit), delta = position - (horizontal ? b.$1 : b.$2);
      result = translate(
        result,
        unit.map((e) => e.id).toSet(),
        horizontal ? delta : 0,
        horizontal ? 0 : delta,
      );
      position += extent(unit) + gap;
    }
    return result;
  }

  static LocatorPrintLayout reorder(
    LocatorPrintLayout layout,
    Set<String> ids,
    String direction,
  ) {
    ids = selection(layout, ids);
    if (!editable(layout, ids)) return layout;
    final items = List<LocatorPrintElement>.of(layout.elements);
    if (direction == 'front' || direction == 'back') {
      final selected = items.where((e) => ids.contains(e.id)).toList();
      items.removeWhere((e) => ids.contains(e.id));
      items.insertAll(direction == 'front' ? items.length : 0, selected);
    } else if (direction == 'forward') {
      for (var i = items.length - 2; i >= 0; i--) {
        if (ids.contains(items[i].id) && !ids.contains(items[i + 1].id)) {
          final next = items[i];
          items[i] = items[i + 1];
          items[i + 1] = next;
        }
      }
    } else if (direction == 'backward') {
      for (var i = 1; i < items.length; i++) {
        if (ids.contains(items[i].id) && !ids.contains(items[i - 1].id)) {
          final next = items[i];
          items[i] = items[i - 1];
          items[i - 1] = next;
        }
      }
    }
    return layout.copyWith(elements: items);
  }
}
