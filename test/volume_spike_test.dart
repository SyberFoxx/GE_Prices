import 'package:flutter_test/flutter_test.dart';
import 'package:ge_prices/models/item_price.dart';
import 'package:ge_prices/utils/volume_spike.dart';

HistoricalPricePoint _point(
  int index, {
  int? avgHigh,
  int highVolume = 0,
  int lowVolume = 0,
}) {
  return HistoricalPricePoint(
    timestamp: 1700000000 + index * 3600,
    avgHighPrice: avgHigh,
    avgLowPrice: avgHigh,
    highPriceVolume: highVolume,
    lowPriceVolume: lowVolume,
  );
}

void main() {
  test('returns null with no previous history', () {
    expect(volumeSpikeRatio(<HistoricalPricePoint>[]), isNull);
    expect(volumeSpikeRatio(<HistoricalPricePoint>[_point(0, highVolume: 10)]),
        isNull);
  });

  test('returns 1.0 when the latest hour matches the average', () {
    final points = <HistoricalPricePoint>[
      for (var i = 0; i < 24; i++) _point(i, highVolume: 100),
    ];
    expect(volumeSpikeRatio(points), closeTo(1.0, 0.0001));
  });

  test('detects a spike above the baseline average', () {
    final points = <HistoricalPricePoint>[
      for (var i = 0; i < 23; i++) _point(i, highVolume: 100),
      _point(23, highVolume: 400),
    ];
    expect(volumeSpikeRatio(points), closeTo(4.0, 0.0001));
  });

  test('sums high and low volumes', () {
    final points = <HistoricalPricePoint>[
      for (var i = 0; i < 23; i++) _point(i, highVolume: 50, lowVolume: 50),
      _point(23, highVolume: 200, lowVolume: 200),
    ];
    // Baseline per bar = 100 units; latest = 400 units.
    expect(volumeSpikeRatio(points), closeTo(4.0, 0.0001));
  });

  test('ignores zero-volume windows (no trades) in the baseline', () {
    final points = <HistoricalPricePoint>[
      for (var i = 0; i < 10; i++)
        _point(i, highVolume: i.isEven ? 200 : 0, lowVolume: 0),
      _point(10, highVolume: 600),
    ];
    // Only the 5 windows with volume count: average = 200.
    expect(volumeSpikeRatio(points), closeTo(3.0, 0.0001));
  });

  test('returns null when the latest hour has no trades', () {
    final points = <HistoricalPricePoint>[
      for (var i = 0; i < 23; i++) _point(i, highVolume: 100),
      _point(23),
    ];
    expect(volumeSpikeRatio(points), isNull);
  });

  test('returns null when every baseline window has zero volume', () {
    final points = <HistoricalPricePoint>[
      for (var i = 0; i < 23; i++) _point(i),
      _point(23, highVolume: 100),
    ];
    expect(volumeSpikeRatio(points), isNull);
  });
}