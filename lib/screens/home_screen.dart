import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item_price.dart';
import '../screens/about_screen.dart';
import '../screens/price_alerts_screen.dart';
import '../services/osrs_api.dart';
import '../services/price_alerts_background_service.dart';
import '../theme/app_theme.dart';
import '../utils/alchemy_profit.dart';
import '../utils/fetch_errors.dart';
import '../utils/ge_tax.dart';
import '../utils/price_format.dart';
import '../utils/price_change.dart';
import '../widgets/item_tile.dart';
import '../widgets/price_change_badge.dart';
import '../widgets/skeletons.dart';
import '../widgets/updated_badge.dart';
import 'detail_screen.dart';
import 'limits_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.initialItems,
    this.initialLatestPrices,
    this.startedOffline = false,
  });

  final List<ItemMapping>? initialItems;
  final Map<String, ItemPrice>? initialLatestPrices;

  /// True when BootstrapScreen opened with the on-disk cache because the
  /// network was unavailable, so the UI shows an honest offline banner.
  final bool startedOffline;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _MarketRow {
  const _MarketRow({
    required this.item,
    required this.data,
    required this.totalVolume,
    required this.marginPct,
    required this.netMargin,
    required this.netMarginPct,
  });

  final ItemMapping item;
  final HourlyPriceData data;
  final int totalVolume;
  final double marginPct;
  final double netMargin;
  final double netMarginPct;
}

class _BuyLimitCapRow {
  const _BuyLimitCapRow({
    required this.item,
    required this.currentHigh,
    required this.currentLow,
    required this.alchProfit,
    required this.netMargin,
    required this.limitCap,
    required this.alchCap,
    required this.flipCap,
  });

  final ItemMapping item;
  final int currentHigh;
  final int currentLow;
  final double alchProfit;
  final double netMargin;

  /// Best per-unit profit * buy limit, i.e. the most you could make from one
  /// 4h buy-limit window (not a daily figure — the API gives no daily volume).
  final double limitCap;
  final double alchCap;
  final double flipCap;
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final OsrsApi _api = OsrsApi();
  final TextEditingController _searchController = TextEditingController();
  static const String _favoriteKey = 'favorite_item_ids';
  static const String _autoRefreshKey = 'auto_refresh_seconds';
  static const int _minimumMarketVolume = 500;
  static const int _minimumAvgLow = 100;

  List<ItemMapping> _items = <ItemMapping>[];
  List<ItemMapping> _filteredItems = <ItemMapping>[];
  Map<String, ItemPrice> _latestPrices = <String, ItemPrice>{};
  Map<String, HourlyPriceData> _hourlyData = <String, HourlyPriceData>{};
  Timer? _autoRefreshTimer;
  Set<int> _favoriteItemIds = <int>{};
  bool _isLoading = true;
  bool _marketLoading = true;
  String? _errorMessage;
  String? _marketError;
  int _autoRefreshSeconds = 0;
  String _selectedFavoriteFilter = 'All';
  String _selectedMembershipFilter = 'All';
  String _selectedAlchMembershipFilter = 'All';
  int _selectedTab = 0;
  bool _isOffline = false;

  // Memoized rankings. `IndexedStack` keeps every tab alive, so each build
  // (including every search keystroke) would otherwise re-iterate and re-sort
  // the full item list three times. The caches are keyed on the identity of
  // the source objects, which are replaced wholesale whenever data reloads.
  List<_MarketRow>? _marketRowsCache;
  List<ItemMapping>? _marketRowsCacheItems;
  Map<String, HourlyPriceData>? _marketRowsCacheHourly;

  List<_BuyLimitCapRow>? _buyLimitCapRowsCache;
  List<ItemMapping>? _buyLimitCapRowsCacheItems;
  Map<String, ItemPrice>? _buyLimitCapRowsCachePrices;

  List<AlchemyOpportunity>? _alchemyRowsCache;
  List<ItemMapping>? _alchemyRowsCacheItems;
  Map<String, ItemPrice>? _alchemyRowsCachePrices;
  String? _alchemyRowsCacheFilter;

  ItemMapping? _natureRune;
  List<ItemMapping>? _natureRuneCacheItems;

  // 24h % change (FT-3) for the most-traded rows, fetched lazily from the
  // hourly timeseries (one request per item, cached 5 min by OsrsApi).
  final Map<int, double> _change24hByItemId = <int, double>{};
  final Set<int> _change24hRequested = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isOffline = widget.startedOffline;
    _readAutoRefreshPreference();
    _loadFavorites();
    if (widget.initialItems != null && widget.initialLatestPrices != null) {
      _items = widget.initialItems!;
      _latestPrices = widget.initialLatestPrices!;
      _isLoading = false;
      _applyFilters();
    } else {
      _loadData();
    }
    if (widget.startedOffline) {
      // Avoid a 15s network timeout on a known-offline start: show the cached
      // snapshot and let the banner's Retry go back online.
      _loadCachedMarketData();
    } else {
      _loadMarketData();
    }
  }

  Future<void> _readAutoRefreshPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    setState(() {
      _autoRefreshSeconds = prefs.getInt(_autoRefreshKey) ?? 0;
    });
    _restartAutoRefresh();
  }

  Future<void> _persistAutoRefreshPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoRefreshKey, _autoRefreshSeconds);
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteIds = prefs.getStringList(_favoriteKey) ?? <String>[];

    if (!mounted) {
      return;
    }

    setState(() {
      _favoriteItemIds = favoriteIds.map(int.tryParse).whereType<int>().toSet();
      _applyFilters();
    });
  }

  void _restartAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;

    if (_autoRefreshSeconds <= 0) {
      return;
    }

    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    // wiki API asks for reasonable use; polling latest only, foreground only.
    _autoRefreshTimer = Timer.periodic(Duration(seconds: _autoRefreshSeconds), (
      _,
    ) {
      if (!mounted) {
        return;
      }
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      // Let the TTL-gated refresh decide so auto-refresh never bypasses the
      // 5-minute cache (reasonable wiki API usage).
      _refreshVisibleTabIfNeeded();
    });
  }

  void _refreshVisibleTabIfNeeded() {
    final now = DateTime.now();

    if ((_selectedTab == 1 || _selectedTab == 2) &&
        (_api.latestCacheAt == null ||
            now.difference(_api.latestCacheAt!) > OsrsApi.cacheTtl)) {
      _loadData();
      return;
    }

    if (_selectedTab == 0) {
      if (_api.hourlyCacheAt == null ||
          now.difference(_api.hourlyCacheAt!) > OsrsApi.cacheTtl) {
        _loadMarketData();
      }
      if (_api.latestCacheAt == null ||
          now.difference(_api.latestCacheAt!) > OsrsApi.cacheTtl) {
        _loadData();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restartAutoRefresh();
      _refreshVisibleTabIfNeeded();
      return;
    }

    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    try {
      final items = await _api.fetchItemMapping(forceRefresh: forceRefresh);
      final latest = await _api.fetchLatestPrices(forceRefresh: forceRefresh);

      if (!mounted) {
        return;
      }

      setState(() {
        _items = items;
        _latestPrices = latest.data;
        _isLoading = false;
        _errorMessage = null;
        _isOffline = false;
        _applyFilters();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        if (_items.isEmpty) {
          _errorMessage = describeFetchError(error).fullText;
        } else {
          // Keep whatever we already have (possibly a cached snapshot) and let
          // the offline banner explain why it might be stale.
          _isOffline = true;
        }
      });
    }
  }

  Future<void> _loadMarketData({bool forceRefresh = false}) async {
    if (_hourlyData.isEmpty) {
      setState(() {
        _marketLoading = true;
        _marketError = null;
      });
    }

    try {
      final hourly = await _api.fetchHourly(forceRefresh: forceRefresh);

      if (!mounted) {
        return;
      }

      setState(() {
        _hourlyData = hourly;
        _marketLoading = false;
        _marketError = null;
        _isOffline = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      // Fall back to the cached 1h snapshot so the dashboard still renders.
      final cached = await _api.loadCachedHourly();
      if (!mounted) {
        return;
      }

      setState(() {
        if (cached != null && cached.isNotEmpty) {
          _hourlyData = cached;
        }
        _marketLoading = false;
        if (_hourlyData.isEmpty) {
          _marketError = describeFetchError(error).fullText;
        } else {
          _isOffline = true;
        }
      });
    }
  }

  /// Seeds the dashboard from the cached 1h snapshot without touching the
  /// network (used on a known-offline start).
  Future<void> _loadCachedMarketData() async {
    final cached = await _api.loadCachedHourly();
    if (!mounted) {
      return;
    }

    setState(() {
      if (cached != null && cached.isNotEmpty) {
        _hourlyData = cached;
      }
      _marketLoading = false;
    });
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    var results = _items;

    if (_selectedFavoriteFilter == 'Favorites') {
      results = results
          .where((item) => _favoriteItemIds.contains(item.id))
          .toList();
    }

    if (_selectedMembershipFilter == 'F2P') {
      results = results.where((item) => !item.members).toList();
    } else if (_selectedMembershipFilter == 'Members') {
      results = results.where((item) => item.members).toList();
    }

    if (query.isNotEmpty) {
      results = results
          .where((item) => item.name.toLowerCase().contains(query))
          .toList();
    }

    _filteredItems = results;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _applyFilters();
    });
  }

  ItemMapping? _natureRuneFor() {
    if (!identical(_natureRuneCacheItems, _items)) {
      _natureRune = AlchemyProfit.findNatureRune(_items);
      _natureRuneCacheItems = _items;
    }
    return _natureRune;
  }

  double _alchemyProfitFor(ItemMapping item) {
    return AlchemyProfit.calculate(
      item: item,
      latestPrices: _latestPrices,
      natureRune: _natureRuneFor(),
    );
  }

  /// Fetches the 24h % change for [itemIds] (most-traded rows) in parallel and
  /// renders it via the ▲/▼ badge. Best effort: missing/failed items just keep
  /// the "—" badge; results are cached per item id so rebuilds don't refetch.
  Future<void> _loadChange24h(Iterable<int> itemIds) async {
    final missing = itemIds.where(
      (id) => !_change24hRequested.contains(id),
    );
    if (missing.isEmpty) {
      return;
    }
    _change24hRequested.addAll(missing);

    final results = await Future.wait<MapEntry<int, double?>>(
      missing.map((id) async {
        double? percent;
        try {
          final points = await _api.fetchHistoricalPrices(
            itemId: id,
            timestep: '1h',
          );
          percent = percentChange24h(points);
        } catch (_) {
          // Offline or an item without history: the badge stays "—".
        }
        return MapEntry<int, double?>(id, percent);
      }),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      for (final entry in results) {
        if (entry.value != null) {
          _change24hByItemId[entry.key] = entry.value!;
        }
      }
    });
  }

  List<_MarketRow> _buildMarketRows() {
    if (_marketRowsCache != null &&
        identical(_marketRowsCacheItems, _items) &&
        identical(_marketRowsCacheHourly, _hourlyData)) {
      return _marketRowsCache!;
    }

    final rows = <_MarketRow>[];

    for (final item in _items) {
      final stat = _hourlyData[item.id.toString()];
      if (stat == null) {
        continue;
      }

      final totalVolume = stat.highPriceVolume + stat.lowPriceVolume;
      final margin = stat.avgHighPrice - stat.avgLowPrice;
      final pct = stat.avgLowPrice > 0
          ? (margin / stat.avgLowPrice) * 100
          : 0.0;
      final netMargin = GeTax.netMargin(
        high: stat.avgHighPrice,
        low: stat.avgLowPrice,
      );
      final netMarginPct = stat.avgLowPrice > 0
          ? (netMargin / stat.avgLowPrice) * 100
          : 0.0;

      rows.add(
        _MarketRow(
          item: item,
          data: stat,
          totalVolume: totalVolume,
          marginPct: pct,
          netMargin: netMargin,
          netMarginPct: netMarginPct,
        ),
      );
    }

    rows.sort((a, b) => b.totalVolume.compareTo(a.totalVolume));
    _marketRowsCache = rows;
    _marketRowsCacheItems = _items;
    _marketRowsCacheHourly = _hourlyData;
    return rows;
  }

  List<_BuyLimitCapRow> _buildBuyLimitCapRows() {
    if (_buyLimitCapRowsCache != null &&
        identical(_buyLimitCapRowsCacheItems, _items) &&
        identical(_buyLimitCapRowsCachePrices, _latestPrices)) {
      return _buyLimitCapRowsCache!;
    }

    final rows = <_BuyLimitCapRow>[];
    final natureRune = _natureRuneFor();

    for (final item in _items) {
      final limit = item.limit;
      if (limit <= 0) {
        continue;
      }

      final currentPrice = _latestPrices[item.id.toString()];
      final currentHigh = currentPrice?.high ?? 0;
      final currentLow = currentPrice?.low ?? 0;
      if (currentHigh <= 0) {
        continue;
      }

      final alchProfit = AlchemyProfit.calculate(
        item: item,
        latestPrices: _latestPrices,
        natureRune: natureRune,
      );

      final netMargin = currentLow > 0
          ? GeTax.netMargin(high: currentHigh, low: currentLow)
          : 0.0;
      final alchCap = alchProfit > 0 ? alchProfit * limit : 0.0;
      final flipCap = netMargin > 0 ? netMargin * limit : 0.0;
      final limitCap = [
        alchCap,
        flipCap,
      ].fold<double>(0, (acc, value) => value > acc ? value : acc);

      if (limitCap <= 0) {
        continue;
      }

      rows.add(
        _BuyLimitCapRow(
          item: item,
          currentHigh: currentHigh,
          currentLow: currentLow,
          alchProfit: alchProfit,
          netMargin: netMargin,
          limitCap: limitCap,
          alchCap: alchCap,
          flipCap: flipCap,
        ),
      );
    }

    rows.sort((a, b) => b.limitCap.compareTo(a.limitCap));
    final result = rows.take(15).toList();
    _buyLimitCapRowsCache = result;
    _buyLimitCapRowsCacheItems = _items;
    _buyLimitCapRowsCachePrices = _latestPrices;
    return result;
  }

  List<AlchemyOpportunity> _buildAlchemyRows() {
    if (_alchemyRowsCache != null &&
        identical(_alchemyRowsCacheItems, _items) &&
        identical(_alchemyRowsCachePrices, _latestPrices) &&
        _alchemyRowsCacheFilter == _selectedAlchMembershipFilter) {
      return _alchemyRowsCache!;
    }

    final members = switch (_selectedAlchMembershipFilter) {
      'F2P' => false,
      'Members' => true,
      _ => null,
    };
    final rows = AlchemyProfit.rankedItems(
      items: _items,
      latestPrices: _latestPrices,
      members: members,
    );
    _alchemyRowsCache = rows;
    _alchemyRowsCacheItems = _items;
    _alchemyRowsCachePrices = _latestPrices;
    _alchemyRowsCacheFilter = _selectedAlchMembershipFilter;
    return rows;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildSearchTab() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Search items...',
              hintStyle: TextStyle(color: AppTheme.secondaryTextColor),
              prefixIcon: Icon(
                Icons.search,
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ToggleButtons(
            isSelected: <bool>[
              _selectedFavoriteFilter == 'All',
              _selectedFavoriteFilter == 'Favorites',
            ],
            onPressed: (int index) {
              setState(() {
                _selectedFavoriteFilter = index == 0 ? 'All' : 'Favorites';
                _applyFilters();
              });
            },
            borderRadius: BorderRadius.circular(12),
            selectedColor: Colors.black,
            fillColor: AppTheme.accentColor,
            color: Colors.white,
            children: const <Widget>[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('All'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Favorites'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <String>['All', 'F2P', 'Members'].map((filter) {
              final isSelected = _selectedMembershipFilter == filter;
              return ChoiceChip(
                label: Text(filter),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _selectedMembershipFilter = filter;
                    _applyFilters();
                  });
                },
                selectedColor: AppTheme.accentColor,
                backgroundColor: AppTheme.panelColor,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          Expanded(
            child: ListView.builder(
              itemCount: 6,
              itemBuilder: (context, index) => const ItemRowSkeleton(),
            ),
          )
        else if (_errorMessage != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => _loadData(forceRefresh: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_filteredItems.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No results found.',
                style: TextStyle(color: AppTheme.secondaryTextColor),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadData(forceRefresh: true),
              color: AppTheme.accentColor,
              child: ListView.builder(
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  final price = _latestPrices[item.id.toString()];

                  return ItemTile(
                    item: item,
                    onTap: () async {
                      final _ = await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => DetailScreen(
                            item: item,
                            currentPrice: price,
                            allItems: _items,
                            latestPrices: _latestPrices,
                          ),
                        ),
                      );

                      if (!mounted) {
                        return;
                      }

                      await _loadFavorites();
                      setState(() {
                        _applyFilters();
                      });
                    },
                    subtitle: price == null
                        ? const Text(
                            'No data available',
                            style: TextStyle(
                              color: AppTheme.secondaryTextColor,
                            ),
                          )
                        : Text(
                            'High: ${PriceFormat.compact(price.high)}\nLow: ${PriceFormat.compact(price.low)}',
                            style: const TextStyle(
                              color: AppTheme.secondaryTextColor,
                            ),
                          ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAlchemyTab() {
    if (_isLoading) {
      return ListView.builder(
        itemCount: 6,
        itemBuilder: (context, index) => const ItemRowSkeleton(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }

    final rows = _buildAlchemyRows();
    return Column(
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'High alch value minus nature rune cost. Assumes fire staff equipped.',
              style: TextStyle(
                color: AppTheme.secondaryTextColor,
                fontSize: 12,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: <String>['All', 'F2P', 'Members'].map((filter) {
              final isSelected = _selectedAlchMembershipFilter == filter;
              return ChoiceChip(
                label: Text(filter),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _selectedAlchMembershipFilter = filter;
                  });
                },
                selectedColor: AppTheme.accentColor,
                backgroundColor: AppTheme.panelColor,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text(
                    'No profitable items found.',
                    style: TextStyle(color: AppTheme.secondaryTextColor),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadData(forceRefresh: true),
                  color: AppTheme.accentColor,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final limit = NumberFormat.decimalPattern('en_US')
                          .format(row.item.limit);
                      return ItemTile(
                        item: row.item,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => DetailScreen(
                                item: row.item,
                                currentPrice:
                                    _latestPrices[row.item.id.toString()],
                                allItems: _items,
                                latestPrices: _latestPrices,
                              ),
                            ),
                          );
                        },
                        title: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                row.item.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '+${PriceFormat.compactValue(row.limitPotential.round())}/4h',
                              style: const TextStyle(
                                color: AppTheme.accentColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Alch: ${PriceFormat.price(row.item.highAlch)}',
                              style: const TextStyle(
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
                            Text(
                              'Buy: ${PriceFormat.price(row.currentHigh)}',
                              style: const TextStyle(
                                color: AppTheme.secondaryTextColor,
                              ),
                            ),
                            Text(
                              'Profit: ${PriceFormat.price(row.profit.round())}',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'x$limit/4h',
                              style: const TextStyle(
                                color: AppTheme.secondaryTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMarketTab() {
    if (_marketLoading) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Most traded (1h)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          MarketSectionSkeleton(rows: 2),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Best margins (1h)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          MarketSectionSkeleton(rows: 2),
        ],
      );
    }

    if (_marketError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _marketError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _loadMarketData(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final rows = _buildMarketRows();
    final topVolume = rows.take(20).toList();

    // 24h % change badge for the most-traded rows — lazy per-item timeseries,
    // cached by OsrsApi so rebuilds never refetch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChange24h(topVolume.map((row) => row.item.id));
    });
    final bestMargins =
        rows
            .where(
              (row) =>
                  row.totalVolume >= _minimumMarketVolume &&
                  row.data.avgLowPrice >= _minimumAvgLow &&
                  // A "best margin" that loses money after GE tax is not a
                  // margin worth showing.
                  row.netMargin > 0,
            )
            .toList()
          ..sort((a, b) => b.netMargin.compareTo(a.netMargin));

    final buyLimitCaps = _buildBuyLimitCapRows();

    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: <Widget>[
        _buildSectionHeader('Most traded (1h)'),
        ...topVolume.map((row) {
          final totalVolume = row.totalVolume;
          return ItemTile(
            item: row.item,
            onTap: () {
              final currentPrice = _latestPrices[row.item.id.toString()];
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DetailScreen(
                    item: row.item,
                    currentPrice: currentPrice,
                    allItems: _items,
                    latestPrices: _latestPrices,
                  ),
                ),
              );
            },
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Price: ${PriceFormat.price(row.data.avgLowPrice)}',
                  style: const TextStyle(color: AppTheme.secondaryTextColor),
                ),
                Text(
                  '${PriceFormat.compact(totalVolume)} traded in 1h',
                  style: const TextStyle(color: AppTheme.secondaryTextColor),
                ),
              ],
            ),
            trailing: PriceChangeBadge(_change24hByItemId[row.item.id]),
          );
        }),
        _buildSectionHeader('Best margins (1h)'),
        ...bestMargins.take(20).map((row) {
          final netAmount = row.netMargin;
          final netPct = row.netMarginPct;
          final netText =
              'Net est.: ${PriceFormat.price(netAmount.round())} ${netPct >= 0 ? '(+${netPct.toStringAsFixed(1)}%)' : '(${netPct.toStringAsFixed(1)}%)'}';
          final alchemyProfit = _alchemyProfitFor(row.item);

          return ItemTile(
            item: row.item,
            onTap: () {
              final currentPrice = _latestPrices[row.item.id.toString()];
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DetailScreen(
                    item: row.item,
                    currentPrice: currentPrice,
                    allItems: _items,
                    latestPrices: _latestPrices,
                  ),
                ),
              );
            },
            title: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    row.item.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (alchemyProfit > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Alch+',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Price: ${PriceFormat.full(row.data.avgLowPrice)}',
                  style: const TextStyle(color: AppTheme.secondaryTextColor),
                ),
                Text(
                  netText,
                  style: TextStyle(
                    color: netAmount >= 0 ? Colors.green : Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }),
        _buildSectionHeaderWithTooltip(
          'Buy-limit caps (est.)',
          'Max gp per 4h buy-limit window if you buy the full limit. Estimates only.',
        ),
        ...buyLimitCaps.map((row) {
          final formatter = NumberFormat.decimalPattern('en_US');
          final buyLimitText = 'x${formatter.format(row.item.limit)}/4h';
          final alchText = row.alchCap > 0
              ? 'Alch: ${PriceFormat.price(row.alchCap.round())}/4h'
              : null;
          final flipText = row.flipCap > 0
              ? 'Flip: ${PriceFormat.price(row.flipCap.round())}/4h'
              : null;

          return ItemTile(
            item: row.item,
            onTap: () {
              final currentPrice = _latestPrices[row.item.id.toString()];
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DetailScreen(
                    item: row.item,
                    currentPrice: currentPrice,
                    allItems: _items,
                    latestPrices: _latestPrices,
                  ),
                ),
              );
            },
            title: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    row.item.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  buyLimitText,
                  style: const TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Price: ${PriceFormat.full(row.currentHigh)}',
                  style: const TextStyle(color: AppTheme.secondaryTextColor),
                ),
                if (alchText != null)
                  Text(
                    alchText,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (flipText != null)
                  Text(
                    flipText,
                    style: const TextStyle(
                      color: AppTheme.accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );

    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: AppTheme.accentColor,
      child: content,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSectionHeaderWithTooltip(String title, String tooltipMessage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: tooltipMessage,
            child: const Icon(
              Icons.info_outline,
              size: 16,
              color: AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Honest strip shown when the app is displaying cached/offline data.
  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF3A2E12),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Offline — showing the last saved prices.',
              style: TextStyle(color: Colors.amber, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _refreshAll,
            style: TextButton.styleFrom(
              foregroundColor: Colors.amber,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Refreshes both the item list / latest prices and the hourly market data.
  /// Used by the offline banner's Retry and by pull-to-refresh.
  Future<void> _refreshAll() async {
    // Drop the cached 24h badges so a forced refresh re-fetches fresh series.
    _change24hByItemId.clear();
    _change24hRequested.clear();
    await Future.wait<void>(<Future<void>>[
      _loadData(forceRefresh: true),
      _loadMarketData(forceRefresh: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = <Widget>[
      _buildMarketTab(),
      _buildAlchemyTab(),
      _buildSearchTab(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('GE Prices'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: UpdatedBadge(
              lastUpdated: _selectedTab == 0
                  ? (_api.hourlyCacheAt ?? _api.latestCacheAt)
                  : _api.latestCacheAt,
            ),
          ),
          if (PriceAlertsBackgroundService.isAndroid)
            IconButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PriceAlertsScreen(
                      items: _items,
                      latestPrices: _latestPrices,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.notifications_none),
              tooltip: 'Active alerts',
            ),
          IconButton(
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => LimitsScreen(
                    allItems: _items,
                    latestPrices: _latestPrices,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: 'My limits',
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'Auto refresh',
            onSelected: (value) {
              setState(() {
                _autoRefreshSeconds = value;
              });
              _persistAutoRefreshPreference();
              _restartAutoRefresh();
            },
            itemBuilder: (context) => const <PopupMenuEntry<int>>[
              PopupMenuItem<int>(value: 0, child: Text('Off')),
              PopupMenuItem<int>(value: 30, child: Text('30s')),
              PopupMenuItem<int>(value: 60, child: Text('60s')),
            ],
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
              );
            },
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_isOffline) _buildOfflineBanner(),
          Expanded(
            child: IndexedStack(index: _selectedTab, children: currentTab),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedTab = index;
          });
          _refreshVisibleTabIfNeeded();
          _restartAutoRefresh();
        },
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.trending_up_outlined),
            selectedIcon: Icon(Icons.trending_up),
            label: 'Market',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Alch',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
        ],
      ),
    );
  }
}
