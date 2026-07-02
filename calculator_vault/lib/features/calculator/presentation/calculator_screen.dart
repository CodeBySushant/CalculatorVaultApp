import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../shared/shared.dart';
import '../../authentication/application/vault_session.dart';
import 'calculator_controller.dart';
import 'history_sheet.dart';

/// The public face of the app: a premium, fully functional calculator.
///
/// `=` on a pure 4–8 digit entry is silently tested against the vault PIN.
/// On mismatch nothing special happens — the digits just evaluate to
/// themselves like any calculator.
class CalculatorScreen extends ConsumerWidget {
  const CalculatorScreen({super.key});

  static const List<List<String>> _keys = <List<String>>[
    <String>['C', '( )', '%', '÷'],
    <String>['7', '8', '9', '×'],
    <String>['4', '5', '6', '−'],
    <String>['1', '2', '3', '+'],
    <String>['0', '.', '⌫', '='],
  ];

  Future<void> _onKey(BuildContext context, WidgetRef ref, String key) async {
    AppHaptics.light();
    final CalculatorController controller =
        ref.read(calculatorControllerProvider.notifier);
    switch (key) {
      case 'C':
        controller.clear();
      case '⌫':
        controller.backspace();
      case '( )':
        controller.toggleBracket();
      case '%':
        controller.appendPercent();
      case '.':
        controller.appendDecimal();
      case '+':
      case '−':
      case '×':
      case '÷':
        controller.appendOperator(key);
      case '=':
        final EqualsOutcome outcome = await controller.onEquals();
        if (!context.mounted) return;
        switch (outcome) {
          case EqualsOutcome.error:
            AppHaptics.heavy();
          case EqualsOutcome.evaluated:
            AppHaptics.medium();
          case EqualsOutcome.vaultPinMatched:
            AppHaptics.medium();
            ref.read(vaultSessionProvider.notifier).unlock();
            context.go(AppRoutes.vault);
          case EqualsOutcome.none:
            break;
        }
      default:
        controller.appendDigit(key);
    }
  }

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final String value =
        ref.read(calculatorControllerProvider.notifier).copyValue;
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    AppHaptics.selection();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Copied $value'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
    }
  }

  Future<void> _paste(BuildContext context, WidgetRef ref) async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text;
    if (text == null || text.isEmpty) return;
    final bool ok =
        ref.read(calculatorControllerProvider.notifier).pasteNumber(text);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Clipboard does not contain a number'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool landscape = context.isLandscape && context.isCompactHeight;

    return Scaffold(
      body: SafeArea(
        child: landscape
            ? Row(
                children: <Widget>[
                  Expanded(
                    flex: 4,
                    child: _DisplayPane(
                      onCopy: () => _copy(context, ref),
                      onPaste: () => _paste(context, ref),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: _Keypad(
                      keys: _keys,
                      keyHeight: 44,
                      onKey: (String key) => _onKey(context, ref, key),
                    ),
                  ),
                ],
              )
            : Column(
                children: <Widget>[
                  Expanded(
                    child: _DisplayPane(
                      onCopy: () => _copy(context, ref),
                      onPaste: () => _paste(context, ref),
                    ),
                  ),
                  _Keypad(
                    keys: _keys,
                    keyHeight: context.responsive<double>(
                      compact: 64,
                      medium: 72,
                    ),
                    onKey: (String key) => _onKey(context, ref, key),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Expression + live preview + error + action icons.
class _DisplayPane extends ConsumerWidget {
  const _DisplayPane({required this.onCopy, required this.onPaste});

  final VoidCallback onCopy;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CalculatorState state = ref.watch(calculatorControllerProvider);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            onLongPress: onCopy,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              alignment: Alignment.bottomRight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      state.expression.isEmpty ? '0' : state.expression,
                      style: theme.textTheme.displayMedium,
                      maxLines: 1,
                      semanticsLabel: state.expression.isEmpty
                          ? 'Display shows zero'
                          : 'Display shows ${state.expression}',
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: state.error != null
                        ? Text(
                            state.error!,
                            key: ValueKey<String>(state.error!),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: scheme.error),
                          )
                        : state.preview.isNotEmpty
                            ? Text(
                                '= ${state.preview}',
                                key: ValueKey<String>(state.preview),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                              )
                            : const SizedBox(height: 28),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              IconButton(
                onPressed: onPaste,
                tooltip: 'Paste',
                icon: Icon(
                  Symbols.content_paste,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                onPressed: onCopy,
                tooltip: 'Copy result',
                icon: Icon(
                  Symbols.content_copy,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Consumer(
                builder: (BuildContext context, WidgetRef ref, _) {
                  return IconButton(
                    onPressed: () => showHistorySheet(context, ref),
                    tooltip: 'History',
                    icon: Icon(
                      Symbols.history,
                      size: 22,
                      color: scheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.keys,
    required this.keyHeight,
    required this.onKey,
  });

  final List<List<String>> keys;
  final double keyHeight;
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          for (final List<String> row in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
              child: Row(
                children: <Widget>[
                  for (final String key in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs + 2,
                        ),
                        child: _CalculatorKey(
                          label: key,
                          height: keyHeight,
                          onTap: () => onKey(key),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A single calculator key with ripple, press animation and semantics.
class _CalculatorKey extends StatelessWidget {
  const _CalculatorKey({
    required this.label,
    required this.height,
    required this.onTap,
  });

  final String label;
  final double height;
  final VoidCallback onTap;

  bool get _isOperator =>
      const <String>{'÷', '×', '−', '+', '%', '( )'}.contains(label);

  bool get _isDestructive => label == 'C' || label == '⌫';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Color background;
    final Color foreground;
    if (label == '=') {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else if (_isDestructive) {
      background = scheme.errorContainer.withValues(alpha: 0.6);
      foreground = scheme.onErrorContainer;
    } else if (_isOperator) {
      background = scheme.secondaryContainer.withValues(alpha: 0.7);
      foreground = scheme.onSecondaryContainer;
    } else {
      background = scheme.surface;
      foreground = scheme.onSurface;
    }

    return AnimatedPress(
      child: Semantics(
        button: true,
        label: 'Calculator key $label',
        child: Material(
          color: background,
          borderRadius: AppRadius.lgAll,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.lgAll,
            child: SizedBox(
              height: height,
              child: Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
