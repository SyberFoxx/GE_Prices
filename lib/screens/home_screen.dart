import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item_price.dart';
import '../services/osrs_api.dart';
import '../theme/app_theme.dart';
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
  });

  final ItemMapping item;
  final HourlyPriceData data;
  final int totalVolume;
  final double marginPct;
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
  String _selectedFavoriteFilter = 'Todos';
  String _selectedMembershipFilter = 'Todos';
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
            'No se pudo cargar la lista de precios. La API de RuneScape Wiki no respondió.';
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
        _marketError = 'No se pudo cargar el dashboard del mercado.';
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    var results = _items;

    if (_selectedFavoriteFilter == 'Favoritos') {
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

      rows.add(
        _MarketRow(
          item: item,
          data: stat,
          totalVolume: totalVolume,
          marginPct: pct,
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
              hintText: 'Buscar item...',
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
              _selectedFavoriteFilter == 'Todos',
              _selectedFavoriteFilter == 'Favoritos',
            ],
            onPressed: (int index) {
              setState(() {
                _selectedFavoriteFilter = index == 0 ? 'Todos' : 'Favoritos';
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
                child: Text('Todos'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Favoritos'),
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
            children: <String>['Todos', 'F2P', 'Members']
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
                'No se encontraron resultados.',
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
                          builder: (_) =>
                              DetailScreen(item: item, currentPrice: price),
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
                            'Sin datos disponibles',
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
      ..sort((a, b) => b.marginPct.compareTo(a.marginPct));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: <Widget>[
        _buildSectionHeader('Más vendidos (1h)'),
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
                  ),
                ),
              );
            },
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Precio: ${PriceFormat.full(row.data.avgLowPrice)}',
                  style: const TextStyle(color: AppTheme.secondaryTextColor),
                ),
                Text(
                  '${PriceFormat.compact(totalVolume)} en 1h',
                  style: const TextStyle(color: AppTheme.secondaryTextColor),
                ),
              ],
            ),
            trailing: const SizedBox.shrink(),
          );
        }),
        _buildSectionHeader('Mejores márgenes (1h)'),
        ...bestMargins.take(20).map((row) {
          final marginText = PriceFormat.marginText(
            high: row.data.avgHighPrice,
            low: row.data.avgLowPrice,
          );

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
                  ),
                ),
              );
            },
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Precio: ${PriceFormat.full(row.data.avgLowPrice)}',
                  style: const TextStyle(color: AppTheme.secondaryTextColor),
                ),
                Text(
                  marginText,
                  style: TextStyle(
                    color: row.marginPct >= 2 ? Colors.green : AppTheme.secondaryTextColor,
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
      appBar: AppBar(title: const Text('GE Prices')),
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
            label: 'Mercado',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Buscar',
          ),
        ],
      ),
    );
  }
}
