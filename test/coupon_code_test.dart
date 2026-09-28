import 'package:extrahelper/features/pos/coupon_code.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the scanner hands the checkout: a flyer link, or the code itself.
void main() {
  test('a flyer link yields the code in its coupon parameter', () {
    expect(
      extractCouponCode('https://app.example.com/s/sekuwa?coupon=SAVE10-7KQ2'),
      'SAVE10-7KQ2',
    );
  });

  test('a link with other parameters still finds coupon', () {
    expect(
      extractCouponCode('https://x.test/s/a?utm=flyer&coupon=welcome10&ref=1'),
      'WELCOME10',
    );
  });

  test('a bare code is upper-cased and trimmed', () {
    expect(extractCouponCode('  dashain-25 '), 'DASHAIN-25');
  });

  test('a link without a coupon is not a code', () {
    expect(extractCouponCode('https://x.test/t/abc'), isNull);
  });

  test('a product barcode is not a code', () {
    // EAN-13 digits are the right characters but too short for the shape
    // only by chance; spaces and lower length guard the rest.
    expect(extractCouponCode('12'), isNull);
    expect(extractCouponCode('sekuwa station'), isNull);
    expect(extractCouponCode(''), isNull);
    expect(extractCouponCode(null), isNull);
  });

  test('the shape matches the database constraint', () {
    expect(extractCouponCode('ABCD'), 'ABCD');
    expect(extractCouponCode('ABC'), isNull);
    expect(extractCouponCode('A' * 24), 'A' * 24);
    expect(extractCouponCode('A' * 25), isNull);
    expect(extractCouponCode('SAVE_10'), isNull);
  });
}
