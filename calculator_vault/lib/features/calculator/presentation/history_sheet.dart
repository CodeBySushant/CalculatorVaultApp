import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../shared/shared.dart';
import '../data/history_repository.dart';
import '../domain/history_entry.dart';
import 'calculator_controller.dart';

/// Opens the calculation history sheet. Tapping an entry loads its result
/// back into the display.
Future<void> showHistorySheet(BuildContext context, WidgetRef ref) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => const _HistorySheetBody(),
  );
}

class _HistorySheetBody extends ConsumerStatefulWidget {
  const _HistorySheetBody();

  @override
  ConsumerState<_HistorySheetBody> createState() => _HistorySheetBodyState();
}

class _HistorySheetBodyState extends ConsumerState<_HistorySheetBody> {
  late List<HistoryEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = ref.read(calcHistoryRepositoryProvider).all();
  }

  Future<void> _clearAll() async {
    await ref.read(calcHistoryRepositoryProvider).clear();
    if (mounted) setState(() => _entries = <HistoryEntry>[]);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (_entries.isEmpty) {
      return const EmptyState(
        icon: Symbols.history,
        title: 'No history yet',
        message: 'Your calculations will appear here.',
      );
    }

    final DateFormat timeFormat = DateFormat.MMMd().add_jm();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('History', style: theme.textTheme.titleLarge),
            AppButton(
              label: 'Clear all',
              variant: AppButtonVariant.ghost,
              onPressed: _clearAll,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final HistoryEntry entry in _entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              onTap: () {
                ref
                    .read(calculatorControllerProvider.notifier)
                    .setExpression(entry.result);
                Navigator.of(context).pop();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    entry.expression,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '= ${entry.result}',
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    timeFormat.format(entry.timestamp),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
