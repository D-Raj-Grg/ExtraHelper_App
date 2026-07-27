import 'package:extrahelper/core/widgets/dish_thumb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('monogram', () {
    test('takes the first letter of the first two words', () {
      expect(monogram('Buff Sekuwa'), 'BS');
      expect(monogram('Chicken Choila Special'), 'CC');
    });

    test('drops parenthetical qualifiers — they are noise here', () {
      expect(monogram('Aila (per shot)'), 'A');
    });

    test('never renders empty', () {
      expect(monogram(''), '?');
      expect(monogram('   '), '?');
      expect(monogram('---'), '?');
    });
  });
}
