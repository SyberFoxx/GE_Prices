import '../models/item_price.dart';

/// How many times the latest hourly volume exceeds the average of the previous
/// bars (1.0 = exactly average, 3.0 = three times the average).
///
/// Volume is the reported lower-bound (units traded per 5-minute aggregated
/// window), so a spike here means a real dump/pump. Returns null when there is
/// nothing comparable: no history, no trades in the latest bar, or a zero
/// baseline (the wiki omits windows with no trades, and a zero baseline would
/// turn any volume into an infinite spike).
double? volumeSpikeRatio(List<HistoricalPricePoint> points) {
  if (points.length < 2) {
    return null;
  }

  final latest = points.last;
  final latestVolume =
      (latest.highPriceVolume ?? 0) + (latest.lowPriceVolume ?? 0);
  if (latestVolume <= 0) {
    return null;
  }

  var sum = 0;
  var count = 0;
  for (final point in points.take(points.length - 1)) {
    final volume = (point.highPriceVolume ?? 0) + (point.lowPriceVolume ?? 0);
    if (volume > 0) {
      sum += volume;
      count++;
    }
  }
  if (count == 0) {
    return null;
  }

  final average = sum / count;
  if (average <= 0) {
    return null;
  }
  return latestVolume / average;
}