import 'package:flutter_test/flutter_test.dart';
import 'package:ge_prices/models/item_price.dart';
import 'package:ge_prices/utils/price_change.dart';

HistoricalPricePoint _point(int index, {int? avgHigh}) {
  return HistoricalPricePoint(
    timestamp: 1700000000 + index * 3600,
    avgHighPrice: avgHigh,
    avgLowPrice: avgHigh,
  );
}

void main() {
  test('returns null with fewer than two priced bars', () {
    expect(percentChange24h(<HistoricalPricePoint>[]), isNull);
    expect(percentChange24h(<HistoricalPricePoint>[_point(0, avgHigh: 100)]),
        isNull);
  });

  test('computes change between two bars', () {
    final points = <HistoricalPricePoint>[
      _point(0, avgHigh: 100),
      _point(1, avgHigh: 110),
    ];
    expect(percentChange24h(points), closeTo(10, 0.0001));
  });

  test('negative change is reported as a negative percentage', () {
    final points = <HistoricalPricePoint>[
      _point(0, avgHigh: 120),
      _point(1, avgHigh: 90),
    ];
    expect(percentChange24h(points), closeTo(-25, 0.0001));
  });

  test('uses the bar ~24h earlier (not the first bar) when > 24 bars', () {
    final points = <HistoricalPricePoint>[
      for (var i = 0; i < 48; i++) _point(i, avgHigh: 100),
    ];
    points[47] = _point(47, avgHigh: 200);
    // Base is the bar 24 positions before the last one (bar 23, price 100),
    // not the very first bar.
    expect(percentChange24h(points), closeTo(100, 0.0001));
  });

  test('ignores bars without a price (windows with no trades)', () {
    final points = <HistoricalPricePoint>[
      _point(0, avgHigh: 100),
      _point(1), // no trades -> omitted by the wiki; must not count as 0
      _point(2, avgHigh: 120),
    ];
    expect(percentChange24h(points), closeTo(20, 0.0001));
  });

  test('returns null when the base price is zero', () {
    final points = <HistoricalPricePoint>[
      _point(0, avgHigh: 0),
      _point(1, avgHigh: 50),
    ];
    expect(percentChange24h(points), isNull);
  });
}