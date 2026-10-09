import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item_price.dart';
import '../screens/about_screen.dart';
import '../services/osrs_api.dart';
import '../theme/app_theme.dart';
import '../utils/alchemy_profit.dart';
import '../utils/ge_tax.dart';
import '../utils/price_format.dart';
import '../widgets/item_tile.dart';
import '../widgets/skeletons.dart';
import '../widgets/updated_badge.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialItems, this.initialLatestPrices});

  final List<ItemMapping>? initialItems;
  final Map<String, ItemPrice>? initialLatestPrices;

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

class _DailyCapRow {
  const _DailyCapRow({
    required this.item,
    required this.currentHigh,
    required this.currentLow,
    required this.alchProfit,
    required this.netMargin,
    required this.dailyCap,
    required this.alchCap,
    required this.flipCap,
  });

  final ItemMapping item;
  final int currentHigh;
  final int currentLow;
  final double alchProfit;
  final double netMargin;
  final double dailyCap;
  final double alchCap;
  final double flipCap;
}

class _HomeScreenState extends State<HomeScreen>
  with WidgetsBindingObserver {
  final OsrsApi _api = OsrsApi();
  final TextEditingController _searchController = TextEditingController();
  static const String _favoriteKey = 'favorite_item_ids';
  static const String _autoRefreshKey = 'auto_refresh_seconds';
  static const Duration _hourlyCacheTtl = Duration(minutes: 5);
  static const Duration _latestCacheTtl = Duration(minutes: 5);
  static const int _minimumMarketVolume = 500;
  static const int _minimumAvgLow = 100;

  List<ItemMapping> _items = <ItemMapping>[];
  List<ItemMapping> _filteredItems = <ItemMapping>[];
  Map<String, ItemPrice> _latestPrices = <String, ItemPrice>{};
  Map<String, HourlyPriceData> _hourlyData = <String, HourlyPriceData>{};
  DateTime? _latestCacheAt;
  DateTime? _hourlyCacheAt;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readAutoRefreshPreference();
    _loadFavorites();
    if (widget.initialItems != null && widget.initialLatestPrices != null) {
      _items = widget.initialItems!;
      _latestPrices = widget.initialLatestPrices!;
      _latestCacheAt = DateTime.now();
      _isLoading = false;
      _applyFilters();
    } else {
      _loadData();
    }
    _loadMarketData();
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
    _autoRefreshTimer = Timer.periodic(
      Duration(seconds: _autoRefreshSeconds),
      (_) {
        if (!mounted) {
          return;
        }
        if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
          return;
        }
        if (_selectedTab == 0 || _selectedTab == 1 || _selectedTab == 2) {
          _loadData();
        }
      },
    );
  }

  void _refreshVisibleTabIfNeeded() {
    final now = DateTime.now();

    if ((_selectedTab == 1 || _selectedTab == 2) && (_latestCacheAt == null || now.difference(_latestCacheAt!) > _latestCacheTtl)) {
      _loadData();
      return;
    }

    if (_selectedTab == 0) {
        if (_hourlyCacheAt == null || now.difference(_hourlyCacheAt!) > _hourlyCacheTtl) {
        _loadMarketData();
      }
        if (_latestCacheAt == null || now.difference(_latestCacheAt!) > _latestCacheTtl) {
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

  Future<void> _loadData() async {
    try {
      final items = await _api.fetchItemMapping();
      final latest = await _api.fetchLatestPrices();

      if (!mounted) {
        return;
      }

      setState(() {
        _items = items;
        _latestPrices = latest.data;
        _latestCacheAt = DateTime.now();
        _isLoading = false;
        _errorMessage = null;
        _applyFilters();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'No internet connection. Check your connection and retry.';
      });
    }
  }

  Future<void> _loadMarketData() async {
    final now = DateTime.now();
    if (_hourlyCacheAt != null &&
        now.difference(_hourlyCacheAt!) < _hourlyCacheTtl &&
        _hourlyData.isNotEmpty) {
      return;
    }

    setState(() {
      _marketLoading = true;
      _marketError = null;
    });

    try {
      final hourly = await _api.fetchHourly();

      if (!mounted) {
        return;
      }

      setState(() {
        _hourlyData = hourly;
        _hourlyCacheAt = now;
        _marketLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _marketLoading = false;
        _marketError = 'No internet connection. Check your connection and retry.';
      });
    }
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

  double _alchemyProfitFor(ItemMapping item) {
    return AlchemyProfit.calculate(
      item: item,
      latestPrices: _latestPrices,
      natureRune: AlchemyProfit.findNatureRune(_items),
    );
  }

  List<_MarketRow> _buildMarketRows() {
    final rows = <_MarketRow>[];

    for (final item in _items) {
      final stat = _hourlyData[item.id.toString()];
      if (stat == null) {
        continue;
      }

      final totalVolume = stat.highPriceVolume + stat.lowPriceVolume;
      final margin = stat.avgHighPrice - stat.avgLowPrice;
        final pct = stat.avgLowPrice > 0 ? (margin / stat.avgLowPrice) * 100 : 0.0;
      final netMargin = GeTax.netMargin(
        high: stat.avgHighPrice,
        low: stat.avgLowPrice,
      );
        final netMarginPct = stat.avgLowPrice > 0 ? (netMargin / stat.avgLowPrice) * 100 : 0.0;

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
    return rows;
  }

  List<_DailyCapRow> _buildDailyCapRows() {
    final rows = <_DailyCapRow>[];
    final natureRune = AlchemyProfit.findNatureRune(_items);

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
      final dailyCap = [alchCap, flipCap].fold<double>(0, (acc, value) => value > acc ? value : acc);

      if (dailyCap <= 0) {
        continue;
      }

      rows.add(
        _DailyCapRow(
          item: item,
          currentHigh: currentHigh,
          currentLow: currentLow,
          alchProfit: alchProfit,
          netMargin: netMargin,
          dailyCap: dailyCap,
          alchCap: alchCap,
          flipCap: flipCap,
        ),
      );
    }

    rows.sort((a, b) => b.dailyCap.compareTo(a.dailyCap));
    return rows.take(15).toList();
  }

  List<AlchemyOpportunity> _buildAlchemyRows() {
    final members = switch (_selectedAlchMembershipFilter) {
      'F2P' => false,
      'Members' => true,
      _ => null,
    };
    return AlchemyProfit.rankedItems(
      items: _items,
      latestPrices: _latestPrices,
      members: members,
    );
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
            children: <String>['All', 'F2P', 'Members']
                .map((filter) {
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
                })
                .toList(),
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
                      onPressed: _loadData,
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
              onRefresh: _loadData,
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
                            style: const TextStyle(color: AppTheme.secondaryTextColor),
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
              : ListView.builder(
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
                            '+${PriceFormat.compactValue(row.dailyPotential.round())}/day',
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
                onPressed: _loadMarketData,
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
    final bestMargins = rows
        .where(
          (row) =>
              row.totalVolume >= _minimumMarketVolume &&
              row.data.avgLowPrice >= _minimumAvgLow,
        )
        .toList()
      ..sort((a, b) => b.netMargin.compareTo(a.netMargin));

    final dailyCaps = _buildDailyCapRows();

    return ListView(
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
            trailing: const SizedBox.shrink(),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          'Daily caps (est.)',
          'Max gp/day if you buy the full 4h GE limit. Estimates only.',
        ),
        ...dailyCaps.map((row) {
          final formatter = NumberFormat.decimalPattern('en_US');
          final buyLimitText = 'x${formatter.format(row.item.limit)}/4h';
          final alchText = row.alchCap > 0
              ? 'Alch: ${PriceFormat.price(row.alchCap.round())}/day'
              : null;
          final flipText = row.flipCap > 0
              ? 'Flip: ${PriceFormat.price(row.flipCap.round())}/day'
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
                  ? (_hourlyCacheAt ?? _latestCacheAt)
                  : _latestCacheAt,
            ),
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
                MaterialPageRoute<void>(
                  builder: (_) => const AboutScreen(),
                ),
              );
            },
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: currentTab,
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
