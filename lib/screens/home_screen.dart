import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item_price.dart';
import '../screens/about_screen.dart';
import '../services/osrs_api.dart';
import '../theme/app_theme.dart';
import '../utils/ge_tax.dart';
import '../utils/price_format.dart';
import '../widgets/item_tile.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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

class _HomeScreenState extends State<HomeScreen> {
  final OsrsApi _api = OsrsApi();
  final TextEditingController _searchController = TextEditingController();
  static const String _favoriteKey = 'favorite_item_ids';
  static const Duration _hourlyCacheTtl = Duration(minutes: 5);
  static const int _minimumMarketVolume = 500;
  static const int _minimumAvgLow = 100;

  List<ItemMapping> _items = <ItemMapping>[];
  List<ItemMapping> _filteredItems = <ItemMapping>[];
  Map<String, ItemPrice> _latestPrices = <String, ItemPrice>{};
  Map<String, HourlyPriceData> _hourlyData = <String, HourlyPriceData>{};
  DateTime? _hourlyCacheAt;
  Set<int> _favoriteItemIds = <int>{};
  bool _isLoading = true;
  bool _marketLoading = true;
  String? _errorMessage;
  String? _marketError;
  String _selectedFavoriteFilter = 'All';
  String _selectedMembershipFilter = 'All';
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadData();
    _loadMarketData();
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
        _errorMessage =
            'Could not load the price list. The RuneScape Wiki API did not respond.';
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
        _marketError = 'Could not load the market dashboard.';
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
    if (item.highAlch <= 0) {
      return 0;
    }

    final currentHigh = _latestPrices[item.id.toString()]?.high ?? 0;
    if (currentHigh <= 0) {
      return 0;
    }

    for (final candidate in _items) {
      if (candidate.name == 'Nature rune') {
        final natureRuneLow = _latestPrices[candidate.id.toString()]?.low ?? 0;
        if (natureRuneLow <= 0) {
          return 0;
        }
        return (item.highAlch - natureRuneLow - currentHigh).toDouble();
      }
    }

    return 0;
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

  @override
  void dispose() {
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
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.accentColor),
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
                            style: TextStyle(color: AppTheme.secondaryTextColor),
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

  Widget _buildMarketTab() {
    if (_marketLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentColor),
      );
    }

    if (_marketError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _marketError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
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
                  'Price: ${PriceFormat.full(row.data.avgLowPrice)}',
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
              'Net est.: ${PriceFormat.full(netAmount.round())} gp ${netPct >= 0 ? '(+${netPct.toStringAsFixed(1)}%)' : '(${netPct.toStringAsFixed(1)}%)'}';
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

  @override
  Widget build(BuildContext context) {
    final currentTab = <Widget>[
      _buildMarketTab(),
      _buildSearchTab(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('GE Prices'),
        actions: <Widget>[
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
        },
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.trending_up_outlined),
            selectedIcon: Icon(Icons.trending_up),
            label: 'Market',
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
