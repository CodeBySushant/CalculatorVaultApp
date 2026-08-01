import 'package:calculator_vault/core/services/secure_storage_service.dart';
import 'package:calculator_vault/features/authentication/domain/pin_attempt_guard.dart';
import 'package:calculator_vault/features/authentication/domain/pin_verifier.dart';
import 'package:calculator_vault/features/calculator/data/history_repository.dart';
import 'package:calculator_vault/features/calculator/domain/history_entry.dart';
import 'package:calculator_vault/features/calculator/presentation/calculator_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryHistory implements CalcHistoryRepository {
  final List<HistoryEntry> entries = <HistoryEntry>[];

  @override
  Future<void> add(HistoryEntry entry) async => entries.add(entry);

  @override
  List<HistoryEntry> all() => entries.reversed.toList();

  @override
  Future<void> clear() async => entries.clear();
}

class _FakePinVerifier extends PinVerifier {
  _FakePinVerifier(this.acceptedPin) : super(SecureStorageService());

  final String? acceptedPin;

  @override
  Future<bool> isPinSet() async => acceptedPin != null;

  @override
  Future<bool> verify(String candidate) async => candidate == acceptedPin;
}

/// In-memory mirror of [PinAttemptGuard]'s policy — no platform storage.
class _FakeAttemptGuard extends PinAttemptGuard {
  _FakeAttemptGuard() : super(SecureStorageService());

  int failures = 0;
  bool lockedOut = false;

  @override
  Future<Duration> remainingLockout() async =>
      lockedOut ? const Duration(seconds: 30) : Duration.zero;

  @override
  Future<bool> canAttempt() async => !lockedOut;

  @override
  Future<Duration> recordFailure() async {
    failures++;
    if (failures >= PinAttemptGuard.maxAttempts) {
      lockedOut = true;
      return PinAttemptGuard.baseCooldown;
    }
    return Duration.zero;
  }

  @override
  Future<void> reset() async {
    failures = 0;
    lockedOut = false;
  }
}

void main() {
  late ProviderContainer container;
  late _InMemoryHistory history;
  late _FakeAttemptGuard guard;

  CalculatorController controller() =>
      container.read(calculatorControllerProvider.notifier);
  CalculatorState state() => container.read(calculatorControllerProvider);

  void setUpContainer({String? acceptedPin}) {
    history = _InMemoryHistory();
    guard = _FakeAttemptGuard();
    container = ProviderContainer(
      overrides: <Override>[
        calcHistoryRepositoryProvider.overrideWithValue(history),
        pinVerifierProvider.overrideWithValue(_FakePinVerifier(acceptedPin)),
        pinAttemptGuardProvider.overrideWithValue(guard),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> typeAndEquals(String digits) async {
    for (final String d in digits.split('')) {
      controller().appendDigit(d);
    }
    await controller().onEquals();
  }

  group('input rules', () {
    setUp(setUpContainer);

    test('digits append in order', () {
      controller()
        ..appendDigit('1')
        ..appendDigit('2')
        ..appendDigit('3');
      expect(state().expression, '123');
    });

    test('a trailing operator is replaced, not stacked', () {
      controller()
        ..appendDigit('5')
        ..appendOperator('+')
        ..appendOperator('×');
      expect(state().expression, '5×');
    });

    test('only one decimal point per number segment', () {
      controller()
        ..appendDigit('1')
        ..appendDecimal()
        ..appendDigit('5')
        ..appendDecimal();
      expect(state().expression, '1.5');
    });

    test('decimal after operator inserts a leading zero', () {
      controller()
        ..appendDigit('2')
        ..appendOperator('+')
        ..appendDecimal();
      expect(state().expression, '2+0.');
    });

    test('bracket key opens, closes, and inserts implicit multiply', () {
      controller().toggleBracket();
      expect(state().expression, '(');

      controller()
        ..appendDigit('2')
        ..toggleBracket();
      expect(state().expression, '(2)');

      controller().toggleBracket();
      expect(state().expression, '(2)×(');
    });

    test('percent only follows a value', () {
      controller().appendPercent();
      expect(state().expression, '');
      controller()
        ..appendDigit('5')
        ..appendPercent();
      expect(state().expression, '5%');
    });

    test('live preview appears for computable expressions', () {
      controller()
        ..appendDigit('2')
        ..appendOperator('+')
        ..appendDigit('3');
      expect(state().preview, '5');
    });

    test('paste accepts plain numbers and rejects junk', () {
      expect(controller().pasteNumber(' 1,234.5 '), isTrue);
      expect(state().expression, '1234.5');
      expect(controller().pasteNumber('hello'), isFalse);
    });
  });

  group('equals', () {
    setUp(setUpContainer);

    test('evaluates and stores history', () async {
      controller()
        ..appendDigit('6')
        ..appendOperator('×')
        ..appendDigit('7');
      final EqualsOutcome outcome = await controller().onEquals();

      expect(outcome, EqualsOutcome.evaluated);
      expect(state().expression, '42');
      expect(state().justEvaluated, isTrue);
      expect(history.entries.single.expression, '6×7');
      expect(history.entries.single.result, '42');
    });

    test('digit after equals starts a fresh calculation', () async {
      controller()
        ..appendDigit('2')
        ..appendOperator('+')
        ..appendDigit('2');
      await controller().onEquals();
      controller().appendDigit('9');
      expect(state().expression, '9');
    });

    test('operator after equals continues from the result', () async {
      controller()
        ..appendDigit('2')
        ..appendOperator('+')
        ..appendDigit('2');
      await controller().onEquals();
      controller().appendOperator('×');
      expect(state().expression, '4×');
    });

    test('error state is set and cleared by the next input', () async {
      controller()
        ..appendDigit('5')
        ..appendOperator('÷')
        ..appendDigit('0');
      final EqualsOutcome outcome = await controller().onEquals();
      expect(outcome, EqualsOutcome.error);
      expect(state().error, 'Cannot divide by zero');

      controller().appendDigit('1');
      expect(state().error, isNull);
    });

    test('pure digit entries do not pollute history', () async {
      controller()
        ..appendDigit('1')
        ..appendDigit('2')
        ..appendDigit('3')
        ..appendDigit('4');
      await controller().onEquals();
      expect(history.entries, isEmpty);
    });
  });

  group('secret PIN detection', () {
    test('matching PIN returns vaultPinMatched and wipes the display',
        () async {
      setUpContainer(acceptedPin: '4821');
      controller()
        ..appendDigit('4')
        ..appendDigit('8')
        ..appendDigit('2')
        ..appendDigit('1');
      final EqualsOutcome outcome = await controller().onEquals();

      expect(outcome, EqualsOutcome.vaultPinMatched);
      expect(state().expression, '');
      expect(history.entries, isEmpty);
    });

    test('non-matching digits behave like a normal calculator', () async {
      setUpContainer(acceptedPin: '4821');
      controller()
        ..appendDigit('9')
        ..appendDigit('9')
        ..appendDigit('9')
        ..appendDigit('9');
      final EqualsOutcome outcome = await controller().onEquals();

      expect(outcome, EqualsOutcome.evaluated);
      expect(state().expression, '9999');
    });

    test('expressions with operators are never PIN-checked', () async {
      setUpContainer(acceptedPin: '4821');
      controller()
        ..appendDigit('4')
        ..appendDigit('8')
        ..appendDigit('2')
        ..appendDigit('1')
        ..appendOperator('+')
        ..appendDigit('0');
      final EqualsOutcome outcome = await controller().onEquals();
      expect(outcome, EqualsOutcome.evaluated);
      expect(state().expression, '4821');
    });
  });

  group('brute-force guard', () {
    test('wrong digit entries count as failed attempts when a PIN exists',
        () async {
      setUpContainer(acceptedPin: '4821');
      await typeAndEquals('1111');
      expect(guard.failures, 1);
    });

    test('digit entries never count when no PIN is configured', () async {
      setUpContainer();
      await typeAndEquals('1111');
      expect(guard.failures, 0);
    });

    test('after lockout even the correct PIN evaluates as a number',
        () async {
      setUpContainer(acceptedPin: '4821');
      for (int i = 0; i < PinAttemptGuard.maxAttempts; i++) {
        await typeAndEquals('1111');
      }
      expect(guard.lockedOut, isTrue);

      controller().clear();
      controller()
        ..appendDigit('4')
        ..appendDigit('8')
        ..appendDigit('2')
        ..appendDigit('1');
      final EqualsOutcome outcome = await controller().onEquals();
      // Disguise preserved: no unlock, no error, just a number.
      expect(outcome, EqualsOutcome.evaluated);
      expect(state().expression, '4821');
    });

    test('a correct PIN resets the failure counter', () async {
      setUpContainer(acceptedPin: '4821');
      await typeAndEquals('1111');
      expect(guard.failures, 1);
      controller().clear();
      await typeAndEquals('4821');
      expect(guard.failures, 0);
      expect(guard.lockedOut, isFalse);
    });
  });
}
