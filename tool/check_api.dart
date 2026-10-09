// ignore_for_file: avoid_print

import 'package:ge_prices/services/osrs_api.dart';

Future<void> main() async {
  final api = OsrsApi();
  final items = await api.fetchItemMapping();
  final latest = await api.fetchLatestPrices();

  final item = items.firstWhere(
    (entry) => entry.id == 2,
    orElse: () => items.first,
  );

  final price = latest.data[item.id.toString()];

  // Exercises the v2 timeseries path (timestep -> lookback mapping).
  final points = await api.fetchHistoricalPrices(
    itemId: item.id,
    timestep: '24h',
  );

  print('item: ${item.id} - ${item.name}');
  print('price: high=${price?.high ?? 'null'} low=${price?.low ?? 'null'}');
  print('keys: ${latest.data.keys.take(3).toList()}');
  print('timeseries: ${points.length} points (24h bars, lookback 1y)');
}
