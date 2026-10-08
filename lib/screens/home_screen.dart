import 'package:flutter/material.dart';

import '../models/item_price.dart';
import '../services/osrs_api.dart';
import '../theme/app_theme.dart';
import 'detail_screen.dart';
import '../widgets/item_list_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OsrsApi _api = OsrsApi();
  final TextEditingController _searchController = TextEditingController();

  List<ItemMapping> _items = <ItemMapping>[];
  List<ItemMapping> _filteredItems = <ItemMapping>[];
  Map<String, ItemPrice> _latestPrices = <String, ItemPrice>{};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
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
        _filteredItems = items;
        _latestPrices = latest.data;
        _isLoading = false;
        _errorMessage = null;
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

  void _onSearchChanged(String value) {
    final query = value.trim().toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredItems = _items;
      } else {
        _filteredItems = _items
            .where((item) => item.name.toLowerCase().contains(query))
            .toList();
      }
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
      appBar: AppBar(
        title: const Text('GE Prices'),
      ),
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
                prefixIcon: Icon(Icons.search, color: AppTheme.secondaryTextColor),
              ),
            ),
          ),
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.accentColor,
                ),
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
              child: ListView.builder(
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  final price = _latestPrices[item.id.toString()];

                  return ItemListTile(
                    item: item,
                    price: price,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => DetailScreen(
                            item: item,
                            currentPrice: price,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
