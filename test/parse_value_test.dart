import 'package:flutter_test/flutter_test.dart';
import 'package:udi_streaks/okr/log_value.dart';
import 'package:udi_streaks/ui/kit.dart';

void main() {
  test('plain numbers', () {
    expect(parseValue('30'), 30);
    expect(parseValue('97.5'), 97.5);
    expect(parseValue('  12 '), 12);
  });

  test('sets x reps shorthand', () {
    expect(parseValue('3x10'), 30);
    expect(parseValue('10x3'), 30);
    expect(parseValue('3*10'), 30);
    expect(parseValue('3×10'), 30);
  });

  test('sums of terms', () {
    expect(parseValue('3x10+2x8'), 46);
    expect(parseValue('10+5'), 15);
  });

  test('per-set lists with commas', () {
    expect(parseValue('8+7+6'), 21);
    expect(parseValue('10,9,8'), 27);
    expect(parseValue('3x7'), 21);
  });

  test('rejects junk', () {
    expect(parseValue(''), isNull);
    expect(parseValue('abc'), isNull);
    expect(parseValue('3x'), isNull);
  });

  group('targetLabel', () {
    test('is the notation the user typed when we kept it', () {
      expect(targetLabel({'target_raw': '3x12', 'target': 36}), '3x12');
    });

    test('falls back to the parsed number', () {
      expect(targetLabel({'target_raw': null, 'target': 36}), '36');
      expect(targetLabel(<String, dynamic>{}), '–');
    });
  });

  group('currentLabel', () {
    test('is the newest entry as it was typed', () {
      expect(currentLabel({'current_raw': '3x11', 'current': 33}), '3x11');
      expect(currentLabel({'current': 33}), '33');
    });

    test('with nothing logged it reads as the starting point', () {
      expect(
          currentLabel({'baseline_raw': '3x10', 'baseline_value': 30}), '3x10');
      expect(currentLabel({'baseline_value': 30}), '30');
    });

    test('and as 0 when there is no starting point either', () {
      expect(currentLabel(<String, dynamic>{}), '0');
    });
  });
}
