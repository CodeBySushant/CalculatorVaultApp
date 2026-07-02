import 'package:calculator_vault/features/authentication/presentation/widgets/pin_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: Center(child: child))),
  );
}

void main() {
  testWidgets('PinPad emits digits and backspace', (tester) async {
    final List<String> digits = <String>[];
    int backspaces = 0;

    await tester.pumpWidget(
      _wrap(
        PinPad(
          onDigit: digits.add,
          onBackspace: () => backspaces++,
        ),
      ),
    );

    await tester.tap(find.text('4'));
    await tester.tap(find.text('8'));
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pumpAndSettle();

    expect(digits, <String>['4', '8']);
    expect(backspaces, 1);
  });

  testWidgets('PinPad hides biometric key when no callback given',
      (tester) async {
    await tester.pumpWidget(
      _wrap(PinPad(onDigit: (_) {}, onBackspace: () {})),
    );
    expect(find.bySemanticsLabel('Unlock with biometrics'), findsNothing);
  });

  testWidgets('PinEntryPanel enables submit only at 4+ digits', (tester) async {
    int submits = 0;
    String entry = '';

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return PinEntryPanel(
              title: 'Enter PIN',
              entry: entry,
              onDigit: (String d) => setState(() => entry += d),
              onBackspace: () {},
              onSubmit: () => submits++,
              submitLabel: 'Unlock',
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Unlock'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(submits, 0, reason: 'submit must be disabled with 0 digits');

    for (final String d in <String>['1', '2', '3', '4']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(submits, 1);
  });

  testWidgets('PinEntryPanel shows the error message', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PinEntryPanel(
          title: 'Enter PIN',
          entry: '',
          error: 'Wrong PIN.',
          errorNonce: 1,
          onDigit: (_) {},
          onBackspace: () {},
          onSubmit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN.'), findsOneWidget);
  });
}
