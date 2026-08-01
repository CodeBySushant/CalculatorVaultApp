import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../authentication/domain/pin_attempt_guard.dart';
import '../../authentication/domain/pin_verifier.dart';
import '../data/history_repository.dart';
import '../domain/expression_engine.dart';
import '../domain/history_entry.dart';

/// Outcome of pressing `=`.
enum EqualsOutcome {
  /// Nothing to evaluate (empty expression).
  none,

  /// Normal evaluation succeeded; result is now the expression.
  evaluated,

  /// Expression was invalid; error message is in state.
  error,

  /// The entered digits matched the vault PIN. The screen navigates to the
  /// vault (wired in Phase 4/6). The display resets so no trace remains.
  vaultPinMatched,
}

/// Immutable calculator UI state.
class CalculatorState {
  const CalculatorState({
    this.expression = '',
    this.preview = '',
    this.error,
    this.justEvaluated = false,
  });

  /// The expression as typed, using display glyphs (× ÷ −).
  final String expression;

  /// Live result preview shown under the expression while typing.
  final String preview;

  /// User-facing error ('Cannot divide by zero', 'Invalid expression').
  final String? error;

  /// True right after `=` so the next digit starts a fresh calculation.
  final bool justEvaluated;

  CalculatorState copyWith({
    String? expression,
    String? preview,
    String? error,
    bool clearError = false,
    bool? justEvaluated,
  }) {
    return CalculatorState(
      expression: expression ?? this.expression,
      preview: preview ?? this.preview,
      error: clearError ? null : (error ?? this.error),
      justEvaluated: justEvaluated ?? this.justEvaluated,
    );
  }
}

final calculatorControllerProvider =
    NotifierProvider<CalculatorController, CalculatorState>(
  CalculatorController.new,
);

/// Owns all calculator behavior: input validation, smart brackets, live
/// preview, history, and the secret-PIN check on `=`.
class CalculatorController extends Notifier<CalculatorState> {
  static const int _maxLength = 100;
  static const String _operators = '+−×÷';
  static final RegExp _pinPattern = RegExp(r'^\d{4,8}$');

  @override
  CalculatorState build() => const CalculatorState();

  CalcHistoryRepository get _history => ref.read(calcHistoryRepositoryProvider);

  PinVerifier get _pinVerifier => ref.read(pinVerifierProvider);

  PinAttemptGuard get _attemptGuard => ref.read(pinAttemptGuardProvider);

  // -------------------------------------------------------------------------
  // Input
  // -------------------------------------------------------------------------

  void appendDigit(String digit) {
    assert(digit.length == 1 && '0123456789'.contains(digit));
    final String base = state.justEvaluated ? '' : state.expression;
    _setExpression(base + digit);
  }

  void appendDecimal() {
    final String base = state.justEvaluated ? '' : state.expression;
    if (_currentNumberSegment(base).contains('.')) return;
    final String prefix =
        base.isEmpty || _endsWithAny(base, '$_operators(') ? '${base}0' : base;
    _setExpression('$prefix.');
  }

  void appendOperator(String op) {
    assert(op.length == 1 && _operators.contains(op));
    String base = state.expression;
    if (base.isEmpty) {
      // Only a leading minus makes sense on an empty display.
      if (op == '−') _setExpression('−');
      return;
    }
    // Replace a trailing operator instead of stacking them.
    if (_endsWithAny(base, _operators)) {
      base = base.substring(0, base.length - 1);
      if (base.isEmpty && op != '−') return;
    }
    if (base.endsWith('(') && op != '−') return;
    _setExpression(base + op);
  }

  void appendPercent() {
    final String base = state.expression;
    if (base.isEmpty || !_endsWithAny(base, '0123456789)%')) return;
    _setExpression('$base%');
  }

  /// Smart bracket key: opens or closes based on balance and context, and
  /// inserts an implicit × when opening right after a number.
  void toggleBracket() {
    final String base = state.justEvaluated ? '' : state.expression;
    final int balance = _bracketBalance(base);
    final bool canClose = balance > 0 && _endsWithAny(base, '0123456789)%');
    if (canClose) {
      _setExpression('$base)');
    } else {
      final bool implicitMultiply = _endsWithAny(base, '0123456789)%');
      _setExpression(implicitMultiply ? '$base×(' : '$base(');
    }
  }

  void backspace() {
    if (state.expression.isEmpty) return;
    _setExpression(
      state.expression.substring(0, state.expression.length - 1),
    );
  }

  void clear() {
    state = const CalculatorState();
  }

  /// Inserts a number from the clipboard. Returns false when the clipboard
  /// text is not a plain number.
  bool pasteNumber(String raw) {
    final String candidate = raw.trim().replaceAll(',', '');
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(candidate)) return false;
    final String display = candidate.replaceFirst('-', '−');
    final String base = state.justEvaluated ? '' : state.expression;
    final bool implicitMultiply = _endsWithAny(base, '0123456789)%');
    _setExpression(implicitMultiply ? '$base×$display' : base + display);
    return true;
  }

  /// Replaces the expression (used when tapping a history entry).
  void setExpression(String expression) {
    _setExpression(expression);
  }

  /// The value to copy: the settled result, the live preview, or the raw
  /// expression as a last resort.
  String get copyValue {
    if (state.justEvaluated || state.preview.isEmpty) return state.expression;
    return state.preview;
  }

  // -------------------------------------------------------------------------
  // Equals
  // -------------------------------------------------------------------------

  Future<EqualsOutcome> onEquals() async {
    final String expr = state.expression;
    if (expr.isEmpty) return EqualsOutcome.none;

    // Secret vault check: pure 4–8 digit entries are tested against the
    // stored PIN hash. On mismatch (or when no PIN exists) the calculator
    // continues completely normally — digits simply evaluate to themselves.
    //
    // Brute-force protection: the check shares a persisted attempt guard
    // with the lock screen. During a lockout NO verification runs at all —
    // the entry just evaluates as a number, so the disguise is preserved
    // and the lockout cannot be probed from the calculator. Failed digit
    // entries only count while a PIN actually exists.
    if (_pinPattern.hasMatch(expr)) {
      try {
        final bool pinExists = await _pinVerifier.isPinSet();
        if (pinExists && await _attemptGuard.canAttempt()) {
          if (await _pinVerifier.verify(expr)) {
            await _attemptGuard.reset();
            state = const CalculatorState();
            return EqualsOutcome.vaultPinMatched;
          }
          // Wrong digits with a PIN configured: count it silently.
          await _attemptGuard.recordFailure();
        }
      } on AppException catch (e) {
        // Any storage/guard failure: the calculator must keep behaving
        // like a plain calculator, so fall through to evaluation.
        AppLogger.error('Calculator', 'secret PIN check failed', e);
      }
    }

    try {
      final String result = ExpressionEngine.evaluate(expr);
      if (result != expr) {
        await _addHistory(expr, result);
      }
      state = CalculatorState(expression: result, justEvaluated: true);
      return EqualsOutcome.evaluated;
    } on EvaluationException catch (e) {
      state = state.copyWith(error: e.message, preview: '');
      return EqualsOutcome.error;
    }
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  void _setExpression(String expression) {
    if (expression.length > _maxLength) return;
    state = CalculatorState(
      expression: expression,
      preview: _previewFor(expression),
    );
  }

  String _previewFor(String expression) {
    // Only preview when there is actually something to compute.
    if (expression.isEmpty ||
        !expression.contains(RegExp('[$_operators%]')) ||
        !_endsWithAny(expression, '0123456789)%')) {
      return '';
    }
    try {
      final String result = ExpressionEngine.evaluate(expression);
      return result == expression ? '' : result;
    } on EvaluationException {
      return '';
    }
  }

  Future<void> _addHistory(String expression, String result) async {
    try {
      await _history.add(
        HistoryEntry(
          expression: expression,
          result: result,
          timestamp: DateTime.now(),
        ),
      );
    } on AppException catch (e) {
      // History is a convenience — never block a calculation on it.
      AppLogger.error('Calculator', 'failed to save history', e);
    }
  }

  static bool _endsWithAny(String s, String chars) =>
      s.isNotEmpty && chars.contains(s[s.length - 1]);

  static int _bracketBalance(String s) {
    int balance = 0;
    for (final int code in s.codeUnits) {
      if (code == 0x28) balance++;
      if (code == 0x29) balance--;
    }
    return balance;
  }

  static String _currentNumberSegment(String s) {
    final int idx = s.lastIndexOf(RegExp('[$_operators()%]'));
    return idx == -1 ? s : s.substring(idx + 1);
  }
}
