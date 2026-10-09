import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/item_price.dart';
import 'price_cache_store.dart';

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

  /// How long to wait for the Wiki before giving up. Without this, a stalled
  /// connection leaves the app on a spinner forever (mobile networks drop
  /// requests silently instead of erroring).
  static const Duration requestTimeout = Duration(seconds: 15);

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

  /// Last-good responses on disk, so the app can open offline.
  final PriceCacheStore _diskCache = PriceCacheStore();

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

    final response = await _get(Uri.parse(_mappingUrl));

    if (response.statusCode != HttpStatus.ok) {
      throw OsrsApiHttpException(
        response.statusCode,
        reasonPhrase: response.reasonPhrase,
      );
    }

    final mapping = _parseMapping(response.body);

    // Update caches
    _mappingCache = mapping;
    _mappingCacheAt = DateTime.now();
    await _diskCache.save('mapping', response.body);

    return mapping;
  }

  Future<LatestPriceResponse> fetchLatestPrices({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid(_latestCacheAt) && _latestCache != null) {
      return _latestCache!;
    }

    final response = await _get(Uri.parse(_latestUrl));

    if (response.statusCode != HttpStatus.ok) {
      throw OsrsApiHttpException(
        response.statusCode,
        reasonPhrase: response.reasonPhrase,
      );
    }

    final latest = _parseLatest(response.body);

    // Update caches
    _latestCache = latest;
    _latestCacheAt = DateTime.now();
    await _diskCache.save('latest', response.body);

    return latest;
  }

  Future<Map<String, HourlyPriceData>> fetchHourly({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid(_hourlyCacheAt) && _hourlyCache != null) {
      return _hourlyCache!;
    }

    final response = await _get(Uri.parse(_hourlyUrl));

    if (response.statusCode != HttpStatus.ok) {
      throw OsrsApiHttpException(
        response.statusCode,
        reasonPhrase: response.reasonPhrase,
      );
    }

    final hourlyData = _parseHourly(response.body);

    // Update caches
    _hourlyCache = hourlyData;
    _hourlyCacheAt = DateTime.now();
    await _diskCache.save('hourly', response.body);

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

    final response = await _get(
      Uri.parse('$_timeSeriesUrl?id=${itemId.toString()}&lookback=$lookback'),
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

  /// Parses a `/mapping` body. Shared by live fetches and the disk cache.
  List<ItemMapping> _parseMapping(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('Mapping response is not a list.');
    }

    return decoded
        .map((item) => ItemMapping.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  /// Parses a `/latest` body. Shared by live fetches and the disk cache.
  LatestPriceResponse _parseLatest(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Latest response is not a map.');
    }

    return LatestPriceResponse.fromJson(decoded);
  }

  /// Parses a `/1h` body. Shared by live fetches and the disk cache.
  Map<String, HourlyPriceData> _parseHourly(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Hourly response is not a map.');
    }

    return HourlyPriceResponse.fromJson(decoded).data;
  }

  /// Loads the last cached `/mapping` snapshot from disk, or null if missing.
  ///
  /// On success the in-memory cache is seeded with the snapshot and its honest
  /// capture time, so the "last updated" badge reflects the disk copy.
  Future<List<ItemMapping>?> loadCachedMapping() async {
    final cached = await _diskCache.load('mapping');
    if (cached == null) {
      return null;
    }

    try {
      final mapping = _parseMapping(cached.body);
      _mappingCache = mapping;
      _mappingCacheAt = cached.savedAt;
      return mapping;
    } catch (_) {
      return null;
    }
  }

  /// Loads the last cached `/latest` snapshot from disk, or null if missing.
  Future<LatestPriceResponse?> loadCachedLatest() async {
    final cached = await _diskCache.load('latest');
    if (cached == null) {
      return null;
    }

    try {
      final latest = _parseLatest(cached.body);
      _latestCache = latest;
      _latestCacheAt = cached.savedAt;
      return latest;
    } catch (_) {
      return null;
    }
  }

  /// Loads the last cached `/1h` snapshot from disk, or null if missing.
  Future<Map<String, HourlyPriceData>?> loadCachedHourly() async {
    final cached = await _diskCache.load('hourly');
    if (cached == null) {
      return null;
    }

    try {
      final hourly = _parseHourly(cached.body);
      _hourlyCache = hourly;
      _hourlyCacheAt = cached.savedAt;
      return hourly;
    } catch (_) {
      return null;
    }
  }

  /// The two pieces BootstrapScreen needs to open offline: item mapping and
  /// latest prices. Returns null when either snapshot is missing.
  Future<({List<ItemMapping> items, LatestPriceResponse latest})?>
  loadCachedStartup() async {
    final items = await loadCachedMapping();
    final latest = await loadCachedLatest();
    if (items == null || latest == null) {
      return null;
    }

    return (items: items, latest: latest);
  }

  /// GET with the required User-Agent, JSON accept header and a hard timeout.
  ///
  /// Every Wiki endpoint needs the custom User-Agent, so it lives here instead
  /// of being repeated per call, and every request is bounded by
  /// [requestTimeout].
  Future<http.Response> _get(Uri uri) {
    return http
        .get(
          uri,
          headers: const <String, String>{
            'User-Agent': _userAgent,
            'Accept': 'application/json',
          },
        )
        .timeout(requestTimeout);
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
