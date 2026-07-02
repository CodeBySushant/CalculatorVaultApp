import 'package:calculator_vault/features/calculator/domain/expression_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpressionEngine basic arithmetic', () {
    test('addition', () => expect(ExpressionEngine.evaluate('2+3'), '5'));
    test('subtraction', () => expect(ExpressionEngine.evaluate('10−4'), '6'));
    test(
        'multiplication', () => expect(ExpressionEngine.evaluate('6×7'), '42'));
    test('division', () => expect(ExpressionEngine.evaluate('7÷2'), '3.5'));

    test('operator precedence', () {
      expect(ExpressionEngine.evaluate('10−4×2'), '2');
      expect(ExpressionEngine.evaluate('2+3×4−1'), '13');
      expect(ExpressionEngine.evaluate('20÷4÷5'), '1');
    });

    test('unary minus', () {
      expect(ExpressionEngine.evaluate('−5+3'), '-2');
      expect(ExpressionEngine.evaluate('−5×−2'), '10');
    });

    test('decimals', () {
      expect(ExpressionEngine.evaluate('1.5+2.25'), '3.75');
      expect(ExpressionEngine.evaluate('.5×4'), '2');
    });

    test('floating point noise is cleaned', () {
      expect(ExpressionEngine.evaluate('0.1+0.2'), '0.3');
      expect(ExpressionEngine.evaluate('0.3−0.1'), '0.2');
    });
  });

  group('ExpressionEngine brackets', () {
    test('grouping changes precedence', () {
      expect(ExpressionEngine.evaluate('(2+3)×4'), '20');
      expect(ExpressionEngine.evaluate('((1+2)×(3+4))'), '21');
    });

    test('unclosed brackets are auto-closed', () {
      expect(ExpressionEngine.evaluate('2×(3+4'), '14');
      expect(ExpressionEngine.evaluate('((5+5'), '10');
    });

    test('extra closing bracket throws', () {
      expect(
        () => ExpressionEngine.evaluate('2+3)'),
        throwsA(isA<EvaluationException>()),
      );
    });
  });

  group('ExpressionEngine percentage', () {
    test('standalone percent divides by 100', () {
      expect(ExpressionEngine.evaluate('50%'), '0.5');
      expect(ExpressionEngine.evaluate('10%%'), '0.001');
    });

    test('relative percent for addition and subtraction', () {
      expect(ExpressionEngine.evaluate('200+10%'), '220');
      expect(ExpressionEngine.evaluate('200−10%'), '180');
    });

    test('plain percent for multiplication and division', () {
      expect(ExpressionEngine.evaluate('50%×4'), '2');
      expect(ExpressionEngine.evaluate('8÷50%'), '16');
    });
  });

  group('ExpressionEngine errors', () {
    test('division by zero', () {
      expect(
        () => ExpressionEngine.evaluate('5÷0'),
        throwsA(
          predicate(
            (Object? e) =>
                e is EvaluationException &&
                e.message == 'Cannot divide by zero',
          ),
        ),
      );
    });

    test('malformed expressions throw', () {
      for (final String expr in <String>[
        '',
        '+',
        '2++3',
        '×5',
        '2.3.4',
        'abc'
      ]) {
        expect(
          () => ExpressionEngine.evaluate(expr),
          throwsA(isA<EvaluationException>()),
          reason: 'expected "$expr" to throw',
        );
      }
    });
  });

  group('ExpressionEngine formatting', () {
    test('integers render without decimal point', () {
      expect(ExpressionEngine.evaluate('4×25'), '100');
    });

    test('digits evaluate to themselves', () {
      expect(ExpressionEngine.evaluate('1234'), '1234');
    });

    test('very large results use scientific notation', () {
      expect(ExpressionEngine.evaluate('1000000×10000000'), contains('e+'));
    });

    test('negative zero normalizes to 0', () {
      expect(ExpressionEngine.evaluate('0×−5'), '0');
    });
  });
}
