import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

/// Month/Year picker powered by bottom_picker.
/// We still return a DateTime normalized to the last day of the selected month.
class MonthYearPickerSheet {
  static DateTime _endOfMonth(int year, int month) => DateTime(year, month + 1, 0);

  /// Shows a themed bottom sheet that lets the user pick only month and year.
  /// Returns a DateTime normalized to the last day of that month at 00:00.
  static Future<DateTime?> show(BuildContext context, {DateTime? initialDate, int minYear = 2000, int maxYear = 2100}) async {
    final init = initialDate ?? DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final years = List<int>.generate(maxYear - minYear + 1, (i) => minYear + i);
    int initMonthIndex = (init.month - 1).clamp(0, 11);
    int initYearIndex = years.indexOf(init.year).clamp(0, years.length - 1);

    final monthCtrl = FixedExtentScrollController(initialItem: initMonthIndex);
    final yearCtrl = FixedExtentScrollController(initialItem: initYearIndex);

    String monthLabel(BuildContext ctx, int month) {
      try {
        final locale = Localizations.localeOf(ctx).toString();
        return toBeginningOfSentenceCase(DateFormat.MMMM(locale).format(DateTime(2000, month))) ?? '$month';
      } catch (_) {
        const names = [
          'January','February','March','April','May','June','July','August','September','October','November','December'
        ];
        return names[(month - 1).clamp(0, 11)];
      }
    }

    final completer = Completer<DateTime?>();

    // Build the content once here so we can easily control styling
    Widget buildContent(BuildContext ctx) {
      final onSurfaceVar = scheme.onSurfaceVariant;
      final dialColor = scheme.primary;
      final selectedStyle = textTheme.titleLarge?.copyWith(color: scheme.onSurface);
      final unselectedStyle = textTheme.titleMedium?.copyWith(color: onSurfaceVar);

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rely on showModalBottomSheet's built-in drag handle to avoid duplicates.
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: monthCtrl,
                              itemExtent: 44,
                              magnification: 1.05,
                              squeeze: 1.1,
                              selectionOverlay: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: dialColor.withValues(alpha: 0.25), width: 1),
                                    bottom: BorderSide(color: dialColor.withValues(alpha: 0.25), width: 1),
                                  ),
                                ),
                              ),
                              children: List.generate(12, (i) {
                                final m = i + 1;
                                return Center(
                                  child: Text(monthLabel(ctx, m), style: unselectedStyle),
                                );
                              }),
                              onSelectedItemChanged: (_) {},
                            ),
                          ),
                          Container(width: 1, color: scheme.outline.withValues(alpha: 0.1)),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: yearCtrl,
                              itemExtent: 44,
                              magnification: 1.05,
                              squeeze: 1.1,
                              selectionOverlay: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: dialColor.withValues(alpha: 0.25), width: 1),
                                    bottom: BorderSide(color: dialColor.withValues(alpha: 0.25), width: 1),
                                  ),
                                ),
                              ),
                              children: years
                                  .map((y) => Center(child: Text('$y', style: unselectedStyle)))
                                  .toList(),
                              onSelectedItemChanged: (_) {},
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (!completer.isCompleted) completer.complete(null);
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final selMonth = (monthCtrl.selectedItem + 1).clamp(1, 12);
                      final selYear = years[yearCtrl.selectedItem.clamp(0, years.length - 1)];
                      final normalized = _endOfMonth(selYear, selMonth);
                      if (!completer.isCompleted) completer.complete(normalized);
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Valider'),
                  ),
                ),
              ])
            ],
          ),
        ),
      );
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: false,
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
        builder: (ctx) => buildContent(ctx),
      );
    } catch (e) {
      debugPrint('Failed to open MonthYearPickerSheet: $e');
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future;
  }
}
