import 'package:flutter/material.dart';

import '../models/item_price.dart';
import '../models/price_alert.dart';
import '../services/alerts_service.dart';
import '../theme/app_theme.dart';
import '../utils/price_format.dart';
import 'detail_screen.dart';

class PriceAlertsScreen extends StatefulWidget {
  const PriceAlertsScreen({
    super.key,
    required this.items,
    required this.latestPrices,
  });

  final List<ItemMapping> items;
  final Map<String, ItemPrice> latestPrices;

  @override
  State<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends State<PriceAlertsScreen> {
  final AlertsService _alertsService = AlertsService();
  List<PriceAlert> _alerts = <PriceAlert>[];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    try {
      final alerts = await _alertsService.active();
      if (!mounted) {
        return;
      }

      setState(() {
        _alerts = alerts;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load alerts from local storage.';
      });
    }
  }

  Future<void> _removeAlert(PriceAlert alert) async {
    await _alertsService.remove(alert);
    if (!mounted) {
      return;
    }

    setState(() {
      _alerts.removeWhere(
        (candidate) =>
            candidate.itemId == alert.itemId &&
            candidate.createdAt.isAtSameMomentAs(alert.createdAt),
      );
    });
  }

  ItemMapping? _findItem(int itemId) {
    for (final item in widget.items) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  Future<void> _openItem(PriceAlert alert) async {
    final item = _findItem(alert.itemId);
    if (item == null) {
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          item: item,
          currentPrice: widget.latestPrices[item.id.toString()],
          allItems: widget.items,
          latestPrices: widget.latestPrices,
        ),
      ),
    );
    await _loadAlerts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('Active alerts')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            )
          : _alerts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.notifications_none,
                      color: AppTheme.secondaryTextColor,
                      size: 40,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No active alerts yet. Open an item and tap the bell to create one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.secondaryTextColor),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAlerts,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _alerts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final alert = _alerts[index];
                  final direction = alert.direction == 'above'
                      ? 'Above'
                      : 'Below';
                  return ListTile(
                    leading: const Icon(
                      Icons.notifications_active_outlined,
                      color: AppTheme.accentColor,
                    ),
                    title: Text(
                      alert.itemName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '$direction ${PriceFormat.price(alert.targetPrice)}',
                      style: const TextStyle(
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                    onTap: () => _openItem(alert),
                    trailing: IconButton(
                      tooltip: 'Delete alert',
                      onPressed: () => _removeAlert(alert),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppTheme.secondaryTextColor,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
