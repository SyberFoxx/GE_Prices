import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/item_price.dart';

/// Thrown when the wiki API responds with a non-2xx status code.
///
/// Kept separate from connectivity errors so screens (BootstrapScreen and the
/// Market/Detail error states) can tell a server outage apart from a lack of
/// internet or a response-schema change.
class OsrsApiHttpException implements Exception {
  const OsrsApiHttpException(this.statusCode, {this.reasonPhrase});

  final int statusCode;
  final String? reasonPhrase;

  @override
  String toString() => 'Wiki API error: $statusCode ${reasonPhrase ?? ''}'
      .trim();
}

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
      'https://prices.runescape.wiki/api/v2/osrs/mapping';
  static const String _latestUrl =
      'https://prices.runescape.wiki/api/v2/osrs/latest';
  static const String _timeSeriesUrl =
      'https://prices.runescape.wiki/api/v2/osrs/timeseries';
  static const String _hourlyUrl = 'https://prices.runescape.wiki/api/v2/osrs/1h';
  static const String _userAgent =
      'GEPrices/1.0 (Android; + https://github.com/SyberFoxx/OSRS_pricesEx)';

  /// v2 `/timeseries` takes a `lookback` window instead of v1's `timestep`.
  ///
  /// These values were verified live against the v2 API: each lookback returns
  /// bars whose width matches the UI label (6h -> 5m bars, 7d -> 1h bars, etc).
  /// Beware: the docs say the returned `timestep` is set by the server and may
  /// change without warning, so re-verify if the chart granularity ever looks
  /// off. (lookback '6m' and '1y' both return 24h bars, so '1y' is used for the
  /// daily view.)
  static const Map<String, String> _timestepToLookback = <String, String>{
    '5m': '6h',
    '1h': '7d',
    '6h': '30d',
    '24h': '1y',
  };

  /// Resolves a UI timestep label to the v2 `lookback` value that the API
  /// answers with bars of that width, or null if the label is unsupported.
  static String? lookbackFor(String timestep) =>
      _timestepToLookback[timestep.trim()];

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
      throw OsrsApiHttpException(
        response.statusCode,
        reasonPhrase: response.reasonPhrase,
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
      throw OsrsApiHttpException(
        response.statusCode,
        reasonPhrase: response.reasonPhrase,
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
      throw OsrsApiHttpException(
        response.statusCode,
        reasonPhrase: response.reasonPhrase,
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
    final normalizedTimestep = timestep.trim();
    final lookback = lookbackFor(normalizedTimestep);
    if (lookback == null) {
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
        '$_timeSeriesUrl?id=${itemId.toString()}&lookback=$lookback',
      ),
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw OsrsApiHttpException(
        response.statusCode,
        reasonPhrase: response.reasonPhrase,
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
