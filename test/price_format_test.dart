import 'package:flutter_test/flutter_test.dart';
import 'package:ge_prices/utils/price_format.dart';

void main() {
  group('PriceFormat', () {
    test('formats compact values as expected', () {
      expect(PriceFormat.compact(1234), '1.2k');
      expect(PriceFormat.compact(1234567), '1.2M');
      expect(PriceFormat.compact(190), '190');
    });

    test('formats margin with percentage', () {
      expect(
        PriceFormat.marginText(high: 8523, low: 8300),
        'Margen: 223 gp (+2.7%)',
      );
    });
  });
}
