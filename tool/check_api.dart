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

  print('item: ${item.id} - ${item.name}');
  print('price: high=${price?.high ?? 'null'} low=${price?.low ?? 'null'}');
  print('keys: ${latest.data.keys.take(3).toList()}');
}
