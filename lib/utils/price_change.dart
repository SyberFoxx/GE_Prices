import '../models/item_price.dart';

/// 24-hour % change in the trade price (`avgHigh`), computed from hourly bars
/// (v2 timeseries lookback `7d`).
///
/// Compares the latest non-null bar against the bar ~24h earlier. Bars without
/// trades are omitted by the wiki API, so only non-null prices are used and a
/// missing window never counts as 0. Returns null when there isn't enough data
/// to compare.
double? percentChange24h(List<HistoricalPricePoint> points) {
  if (points.length < 2) {
    return null;
  }

  final priced = points
      .where((point) => point.avgHighPrice != null)
      .toList();
  if (priced.length < 2) {
    return null;
  }

  // Hourly bars: the bar 24 positions before the last one is ~24h older.
  final base = priced[priced.length > 24 ? priced.length - 25 : 0];
  final basePrice = base.avgHighPrice;
  if (basePrice == null || basePrice == 0) {
    return null;
  }

  return (priced.last.avgHighPrice! - basePrice) / basePrice * 100;
}