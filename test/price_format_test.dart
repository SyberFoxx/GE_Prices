import 'package:flutter_test/flutter_test.dart';
import 'package:ge_prices/utils/ge_tax.dart';
import 'package:ge_prices/utils/price_format.dart';

void main() {
  group('PriceFormat', () {
    test('formats compact values as expected', () {
      expect(PriceFormat.compact(1234), '1.2k gp');
      expect(PriceFormat.compact(1234567), '1.2M gp');
      expect(PriceFormat.compact(190), '190 gp');
    });

    test('formats margin with percentage', () {
      expect(
        PriceFormat.marginText(high: 8523, low: 8300),
        'Margin: 223 gp (+2.7%)',
      );
    });

    test('uses a single gp suffix for direct price values', () {
      expect(PriceFormat.price(1), '1 gp');
      expect(PriceFormat.price(1234), '1,234 gp');
    });
  });

  group('GeTax', () {
    test('calculates net margin after GE tax', () {
      expect(GeTax.netMargin(high: 10000, low: 9000), 800.0);
      expect(GeTax.netMargin(high: 100000000, low: 90000000), 8000000.0);
    });
  });
}
