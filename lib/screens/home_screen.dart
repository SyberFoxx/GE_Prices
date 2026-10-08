import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item_price.dart';
import '../services/osrs_api.dart';
import '../theme/app_theme.dart';
import '../widgets/item_list_tile.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OsrsApi _api = OsrsApi();
  final TextEditingController _searchController = TextEditingController();
  static const String _favoriteKey = 'favorite_item_ids';

  List<ItemMapping> _items = <ItemMapping>[];
  List<ItemMapping> _filteredItems = <ItemMapping>[];
  Map<String, ItemPrice> _latestPrices = <String, ItemPrice>{};
  Set<int> _favoriteItemIds = <int>{};
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFavoriteFilter = 'Todos';
  String _selectedMembershipFilter = 'Todos';

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadData();
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
        _errorMessage = 'No se pudo cargar la lista de precios. La API de RuneScape Wiki no respondió.';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('GE Prices')),
      body: Column(
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

                    return ItemListTile(
                      item: item,
                      price: price,
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
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
