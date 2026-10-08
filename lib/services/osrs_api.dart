import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/item_price.dart';

class OsrsApi {
  static const String _mappingUrl =
      'https://prices.runescape.wiki/api/v1/osrs/mapping';
  static const String _latestUrl =
      'https://prices.runescape.wiki/api/v1/osrs/latest';
  static const String _timeSeriesUrl =
      'https://prices.runescape.wiki/api/v1/osrs/timeseries';
  static const String _userAgent = 'ge_prices-dev - prototipo personal';

  Future<List<ItemMapping>> fetchItemMapping() async {
    final response = await http.get(
      Uri.parse(_mappingUrl),
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Error fetching item mapping: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Mapping response is not a list.');
    }

    return decoded
        .map((item) => ItemMapping.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<LatestPriceResponse> fetchLatestPrices() async {
    final response = await http.get(
      Uri.parse(_latestUrl),
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Error fetching latest prices: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Latest response is not a map.');
    }

    return LatestPriceResponse.fromJson(decoded);
  }

  Future<List<HistoricalPricePoint>> fetchHistoricalPrices({
    required int itemId,
    required String timestep,
  }) async {
    const allowedTimesteps = <String>{'5m', '1h', '6h', '24h'};
    final normalizedTimestep = timestep.trim();

    if (!allowedTimesteps.contains(normalizedTimestep)) {
      throw ArgumentError('Unsupported timestep: $timestep');
    }

    final response = await http.get(
      Uri.parse(
        '$_timeSeriesUrl?id=${itemId.toString()}&timestep=$normalizedTimestep',
      ),
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Error fetching historical prices: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Historical prices response is not a map.');
    }

    return HistoricalPriceResponse.fromJson(decoded).data;
  }
}
