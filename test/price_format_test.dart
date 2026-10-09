import 'package:flutter_test/flutter_test.dart';
import 'package:ge_prices/utils/ge_tax.dart';
import 'package:ge_prices/utils/price_format.dart';

void main() {
  group('PriceFormat', () {
    test('formats compact values as expected', () {
      expect(PriceFormat.compact(1234), '1.2k gp');
      expect(PriceFormat.compact(1234567), '1.2M gp');
      expect(PriceFormat.compact(190), '190 gp');
      expect(PriceFormat.compactValue(1234567), '1.2M');
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

    test('applies 2% tax per unit and the 5M cap', () {
      // Spot-check: sell at 110 -> 2.2 gp per unit sold.
      expect(GeTax.taxOn(salePrice: 110), 2.2);
      expect(GeTax.taxOn(salePrice: 0), 0);
      // Below the cap the full 2% applies.
      expect(GeTax.taxOn(salePrice: 100000000), 2000000.0);
      // 2% of 300M = 6M, clamped to the 5M cap.
      expect(GeTax.taxOn(salePrice: 300000000), 5000000.0);
    });
  });
}
