import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/item_price.dart';

/// OSRS Wiki API client with in-memory cache.
///
/// A single shared instance is used app-wide so the cache is truly shared
/// between screens (Bootstrap, Home, Detail) instead of fragmenting into one
/// cache per `OsrsApi()`. Each method caches its response for [cacheTtl];
/// pass `forceRefresh: true` to bypass the cache and fetch fresh data.
class OsrsApi {
  OsrsApi._internal();

  /// Shared instance. Use it everywhere so every screen sees the same cache.
  static final OsrsApi _instance = OsrsApi._internal();

  factory OsrsApi() => _instance;

  static const String _mappingUrl =
      'https://prices.runescape.wiki/api/v1/osrs/mapping';
  static const String _latestUrl =
      'https://prices.runescape.wiki/api/v1/osrs/latest';
  static const String _timeSeriesUrl =
      'https://prices.runescape.wiki/api/v1/osrs/timeseries';
  static const String _hourlyUrl = 'https://prices.runescape.wiki/api/v1/osrs/1h';
  static const String _userAgent =
      'GEPrices/1.0 (Android; + https://github.com/SyberFoxx/OSRS_pricesEx)';

  /// Cache time-to-live shared by every endpoint.
  static const Duration cacheTtl = Duration(minutes: 5);

  // Cache storage: timestamp + response data
  List<ItemMapping>? _mappingCache;
  DateTime? _mappingCacheAt;

  LatestPriceResponse? _latestCache;
  DateTime? _latestCacheAt;

  Map<String, HourlyPriceData>? _hourlyCache;
  DateTime? _hourlyCacheAt;

  // Timeseries cache: key is "itemId_timestep"
  final Map<String, List<HistoricalPricePoint>> _timeseriesCache =
      <String, List<HistoricalPricePoint>>{};
  final Map<String, DateTime> _timeseriesCacheAt = <String, DateTime>{};

  bool _isCacheValid(DateTime? cacheAt) {
    if (cacheAt == null) return false;
    return DateTime.now().difference(cacheAt) < cacheTtl;
  }

  /// Timestamp of the last successful `/latest` fetch, or null if never.
  DateTime? get latestCacheAt => _latestCacheAt;

  /// Timestamp of the last successful `/1h` fetch, or null if never.
  DateTime? get hourlyCacheAt => _hourlyCacheAt;

  Future<List<ItemMapping>> fetchItemMapping({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid(_mappingCacheAt) && _mappingCache != null) {
      return _mappingCache!;
    }

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

    final mapping = decoded
        .map((item) => ItemMapping.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();

    // Update cache
    _mappingCache = mapping;
    _mappingCacheAt = DateTime.now();

    return mapping;
  }

  Future<LatestPriceResponse> fetchLatestPrices({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid(_latestCacheAt) && _latestCache != null) {
      return _latestCache!;
    }

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

    final latest = LatestPriceResponse.fromJson(decoded);

    // Update cache
    _latestCache = latest;
    _latestCacheAt = DateTime.now();

    return latest;
  }

  Future<Map<String, HourlyPriceData>> fetchHourly({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid(_hourlyCacheAt) && _hourlyCache != null) {
      return _hourlyCache!;
    }

    final response = await http.get(
      Uri.parse(_hourlyUrl),
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Error fetching hourly market: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Hourly response is not a map.');
    }

    final hourlyData = HourlyPriceResponse.fromJson(decoded).data;

    // Update cache
    _hourlyCache = hourlyData;
    _hourlyCacheAt = DateTime.now();

    return hourlyData;
  }

  Future<List<HistoricalPricePoint>> fetchHistoricalPrices({
    required int itemId,
    required String timestep,
    bool forceRefresh = false,
  }) async {
    const allowedTimesteps = <String>{'5m', '1h', '6h', '24h'};
    final normalizedTimestep = timestep.trim();

    if (!allowedTimesteps.contains(normalizedTimestep)) {
      throw ArgumentError('Unsupported timestep: $timestep');
    }

    final cacheKey = '${itemId}_$normalizedTimestep';

    if (!forceRefresh &&
        _isCacheValid(_timeseriesCacheAt[cacheKey]) &&
        _timeseriesCache.containsKey(cacheKey)) {
      return _timeseriesCache[cacheKey]!;
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

    final points = HistoricalPriceResponse.fromJson(decoded).data;

    // Update cache
    _timeseriesCache[cacheKey] = points;
    _timeseriesCacheAt[cacheKey] = DateTime.now();

    return points;
  }

  /// Invalidates all cached data.
  void clearCache() {
    _mappingCache = null;
    _mappingCacheAt = null;
    _latestCache = null;
    _latestCacheAt = null;
    _hourlyCache = null;
    _hourlyCacheAt = null;
    _timeseriesCache.clear();
    _timeseriesCacheAt.clear();
  }
}
