/// Expression engine for the calculator.
///
/// Supports: + − × ÷, decimals, brackets with precedence, unary minus, and
/// calculator-style percentage:
///   `50%`      → 0.5
///   `200+10%`  → 220   (percent is relative to the left operand for + / −)
///   `200−10%`  → 180
///   `50%×4`    → 2     (plain /100 for × and ÷)
///
/// Unbalanced open brackets are auto-closed on evaluation, matching the
/// behavior of Google's calculator.
library;

/// Thrown when an expression cannot be evaluated. [message] is safe to show
/// directly in the UI.
class EvaluationException implements Exception {
  const EvaluationException(this.message);

  final String message;

  @override
  String toString() => 'EvaluationException: $message';
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

sealed class _Node {
  const _Node();
}

class _Num extends _Node {
  const _Num(this.value);
  final double value;
}

class _Neg extends _Node {
  const _Neg(this.child);
  final _Node child;
}

class _Percent extends _Node {
  const _Percent(this.child);
  final _Node child;
}

class _Bin extends _Node {
  const _Bin(this.op, this.left, this.right);
  final String op; // '+', '-', '*', '/'
  final _Node left;
  final _Node right;
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

sealed class _Token {
  const _Token();
}

class _NumTok extends _Token {
  const _NumTok(this.value);
  final double value;
}

class _OpTok extends _Token {
  const _OpTok(this.op); // one of + - * / ( ) %
  final String op;
}

/// Static entry point: `ExpressionEngine.evaluate('2×(3+4)')` → `'14'`.
abstract final class ExpressionEngine {
  static const String _invalid = 'Invalid expression';

  /// Evaluates [rawExpression] and returns the formatted result string.
  ///
  /// Throws [EvaluationException] for malformed input or division by zero.
  static String evaluate(String rawExpression) {
    final String normalized = _normalize(rawExpression);
    if (normalized.isEmpty) {
      throw const EvaluationException(_invalid);
    }
    final List<_Token> tokens = _tokenize(_autoClose(normalized));
    if (tokens.isEmpty) {
      throw const EvaluationException(_invalid);
    }
    final _Parser parser = _Parser(tokens);
    final _Node ast = parser.parseExpression();
    if (!parser.isAtEnd) {
      throw const EvaluationException(_invalid);
    }
    return format(_eval(ast));
  }

  /// Maps display glyphs to ASCII operators and strips whitespace/grouping.
  static String _normalize(String input) => input
      .replaceAll('−', '-')
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll(',', '')
      .replaceAll(' ', '');

  /// Appends missing closing brackets.
  static String _autoClose(String input) {
    int balance = 0;
    for (final int code in input.codeUnits) {
      if (code == 0x28) balance++; // (
      if (code == 0x29) balance--; // )
    }
    if (balance < 0) {
      throw const EvaluationException(_invalid);
    }
    return input + (')' * balance);
  }

  static List<_Token> _tokenize(String input) {
    final List<_Token> tokens = <_Token>[];
    int i = 0;
    while (i < input.length) {
      final String c = input[i];
      if (_isDigit(c) || c == '.') {
        final int start = i;
        bool seenDot = false;
        while (i < input.length &&
            (_isDigit(input[i]) || (input[i] == '.' && !seenDot))) {
          if (input[i] == '.') seenDot = true;
          i++;
        }
        final double? value = double.tryParse(input.substring(start, i));
        if (value == null) {
          throw const EvaluationException(_invalid);
        }
        tokens.add(_NumTok(value));
      } else if (const <String>{'+', '-', '*', '/', '(', ')', '%'}
          .contains(c)) {
        tokens.add(_OpTok(c));
        i++;
      } else {
        throw const EvaluationException(_invalid);
      }
    }
    return tokens;
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  static double _eval(_Node node) {
    return switch (node) {
      _Num(:final double value) => value,
      _Neg(:final _Node child) => -_eval(child),
      _Percent(:final _Node child) => _eval(child) / 100,
      final _Bin bin => _evalBin(bin),
    };
  }

  static double _evalBin(_Bin node) {
    final double left = _eval(node.left);
    switch (node.op) {
      case '+':
      case '-':
        // Calculator-style relative percent: 200+10% == 200 + 200*0.10.
        final _Node rightNode = node.right;
        final double right = rightNode is _Percent
            ? left * (_eval(rightNode.child) / 100)
            : _eval(rightNode);
        return node.op == '+' ? left + right : left - right;
      case '*':
        return left * _eval(node.right);
      case '/':
        final double right = _eval(node.right);
        if (right == 0) {
          throw const EvaluationException('Cannot divide by zero');
        }
        return left / right;
      default:
        throw const EvaluationException(_invalid);
    }
  }

  /// Formats a raw double into a clean display string.
  ///
  /// Removes binary floating point noise (0.1 + 0.2 → `0.3`), drops trailing
  /// zeros, renders integers without a decimal point, and switches to
  /// scientific notation for very large or very small magnitudes.
  static String format(double value) {
    if (value.isNaN || value.isInfinite) {
      throw const EvaluationException(_invalid);
    }
    final double cleaned = double.parse(value.toStringAsPrecision(12));
    if (cleaned == 0) return '0';
    final double magnitude = cleaned.abs();
    if (magnitude >= 1e12 || magnitude < 1e-9) {
      return cleaned
          .toStringAsExponential(6)
          .replaceFirst(RegExp(r'0+e'), 'e')
          .replaceFirst('.e', 'e');
    }
    if (cleaned == cleaned.truncateToDouble()) {
      return cleaned.truncate().toString();
    }
    return cleaned
        .toStringAsFixed(10)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _Parser {
  _Parser(this._tokens);

  final List<_Token> _tokens;
  int _pos = 0;

  bool get isAtEnd => _pos >= _tokens.length;

  _Token? get _peek => isAtEnd ? null : _tokens[_pos];

  bool _matchOp(Set<String> ops) {
    final _Token? t = _peek;
    return t is _OpTok && ops.contains(t.op);
  }

  String _consumeOp() {
    final _OpTok t = _tokens[_pos] as _OpTok;
    _pos++;
    return t.op;
  }

  _Node parseExpression() {
    _Node node = _parseTerm();
    while (_matchOp(const <String>{'+', '-'})) {
      final String op = _consumeOp();
      node = _Bin(op, node, _parseTerm());
    }
    return node;
  }

  _Node _parseTerm() {
    _Node node = _parseUnary();
    while (_matchOp(const <String>{'*', '/'})) {
      final String op = _consumeOp();
      node = _Bin(op, node, _parseUnary());
    }
    return node;
  }

  _Node _parseUnary() {
    if (_matchOp(const <String>{'-'})) {
      _consumeOp();
      return _Neg(_parseUnary());
    }
    return _parsePostfix();
  }

  _Node _parsePostfix() {
    _Node node = _parsePrimary();
    while (_matchOp(const <String>{'%'})) {
      _consumeOp();
      node = _Percent(node);
    }
    return node;
  }

  _Node _parsePrimary() {
    final _Token? t = _peek;
    if (t is _NumTok) {
      _pos++;
      return _Num(t.value);
    }
    if (t is _OpTok && t.op == '(') {
      _pos++;
      final _Node inner = parseExpression();
      if (!_matchOp(const <String>{')'})) {
        throw const EvaluationException(ExpressionEngine._invalid);
      }
      _consumeOp();
      return inner;
    }
    throw const EvaluationException(ExpressionEngine._invalid);
  }
}
