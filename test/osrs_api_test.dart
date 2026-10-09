import 'package:flutter_test/flutter_test.dart';
import 'package:ge_prices/services/osrs_api.dart';

void main() {
  group('OsrsApi v2 lookback mapping', () {
    test('maps UI timestep labels to v2 lookbacks that keep bar widths honest',
        () {
      expect(OsrsApi.lookbackFor('5m'), '6h');
      expect(OsrsApi.lookbackFor('1h'), '7d');
      expect(OsrsApi.lookbackFor('6h'), '30d');
      expect(OsrsApi.lookbackFor('24h'), '1y');
    });

    test('ignores surrounding whitespace and rejects unsupported labels', () {
      expect(OsrsApi.lookbackFor(' 6h '), '30d');
      expect(OsrsApi.lookbackFor('2h'), isNull);
      expect(OsrsApi.lookbackFor(''), isNull);
    });
  });

  group('OsrsApi request timeout', () {
    test('bounds every request with a sane, non-zero timeout', () {
      expect(OsrsApi.requestTimeout.inSeconds, greaterThan(0));
      expect(OsrsApi.requestTimeout.inSeconds, lessThanOrEqualTo(60));
    });
  });
}