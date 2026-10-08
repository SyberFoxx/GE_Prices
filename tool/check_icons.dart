// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;

import 'package:ge_prices/services/osrs_api.dart';

Future<void> main() async {
  final api = OsrsApi();
  final items = await api.fetchItemMapping();

  final sampleItems = items
      .where((item) => item.icon.trim().isNotEmpty)
      .take(5)
      .toList();

  for (final item in sampleItems) {
    final iconName = item.icon.replaceAll(' ', '_');
    final url = 'https://oldschool.runescape.wiki/images/$iconName';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'ge_prices-dev - prototipo personal',
        'Accept': 'image/png',
      },
    );

    print('${item.name} -> $url -> ${response.statusCode}');
  }
}
