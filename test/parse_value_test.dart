import 'package:flutter_test/flutter_test.dart';
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
}
