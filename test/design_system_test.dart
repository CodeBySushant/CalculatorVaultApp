import 'package:calculator_vault/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: Center(child: child)));
}

void main() {
  group('AppButton', () {
    testWidgets('renders label and fires onPressed', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(AppButton(label: 'Continue', onPressed: () => taps++)),
      );

      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('loading state shows spinner and blocks taps', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(
          AppButton(label: 'Save', loading: true, onPressed: () => taps++),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, 0);
    });

    testWidgets('null onPressed renders disabled', (tester) async {
      await tester.pumpWidget(
        _wrap(const AppButton(label: 'Disabled', onPressed: null)),
      );
      final Semantics semantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.text('Disabled'),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.enabled, isFalse);
    });
  });

  group('EmptyState', () {
    testWidgets('renders icon, texts and action', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(
          EmptyState(
            icon: Symbols.photo_library,
            title: 'No photos yet',
            message: 'Import photos to keep them safe.',
            actionLabel: 'Import',
            onAction: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Import photos to keep them safe.'), findsOneWidget);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('AppTextField', () {
    testWidgets('obscure toggle switches visibility', (tester) async {
      await tester.pumpWidget(
        _wrap(const AppTextField(label: 'Password', obscurable: true)),
      );

      TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);

      await tester.tap(find.byTooltip('Show'));
      await tester.pump();

      field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isFalse);
    });
  });
}
