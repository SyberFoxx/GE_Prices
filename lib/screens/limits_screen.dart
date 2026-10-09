import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item_price.dart';
import '../models/limit_entry.dart';
import '../services/limit_service.dart';
import '../theme/app_theme.dart';

/// Screen displaying all active buy limit tracking windows.
/// 
/// Shows all items being tracked with their progress bars,
/// countdown timers, and allows manual reset of windows.
class LimitsScreen extends StatefulWidget {
  const LimitsScreen({
    super.key,
    required this.allItems,
    required this.latestPrices,
  });

  final List<ItemMapping> allItems;
  final Map<String, ItemPrice> latestPrices;

  @override
  State<LimitsScreen> createState() => _LimitsScreenState();
}

class _LimitsScreenState extends State<LimitsScreen> {
  late LimitService _limitService;
  List<LimitEntry> _entries = <LimitEntry>[];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    _limitService = await LimitService.create();
    await _loadEntries();
  }

  Future<void> _loadEntries() async {
    // Clean up expired entries and count them
    final expiredCount = await _limitService.cleanupExpired();
    
    // Reload active entries
    final entries = _limitService.getActiveEntries();
    
    if (!mounted) return;
    
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
    
    // Show subtle message if any windows were reset
    if (expiredCount > 0 && mounted) {
      _showExpiredMessage(expiredCount);
    }
  }

  void _showExpiredMessage(int count) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$count window${count > 1 ? 's' : ''} reset (expired)'),
        backgroundColor: AppTheme.panelColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  Color _getProgressColor(double percentage) {
    if (percentage >= 0.9) {
      return Colors.redAccent;
    } else if (percentage >= 0.7) {
      return Colors.amber;
    } else {
      return Colors.green;
    }
  }

  ItemMapping? _findItem(int itemId) {
    try {
      return widget.allItems.firstWhere((item) => item.id == itemId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _resetEntry(int itemId) async {
    await _limitService.resetEntry(itemId);
    await _loadEntries();
  }

  Future<void> _confirmReset(int itemId, String itemName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.panelColor,
          title: const Text(
            'Reset window?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'This will clear the tracking window for "$itemName". '
            'You\'ll need to start tracking from scratch.',
            style: const TextStyle(color: AppTheme.secondaryTextColor),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _resetEntry(itemId);
    }
  }

  @override
  Widget build(BuildContext context) {
    _startRefreshTimer();
    
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('My Limits'),
        actions: <Widget>[
          if (_entries.isNotEmpty)
            IconButton(
              onPressed: _loadEntries,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState()
              : _buildList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: AppTheme.secondaryTextColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'No active tracking',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Go to any item with a buy limit and tap "Track my buys" to start tracking your purchases.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _entries.length,
      itemBuilder: (BuildContext context, int index) {
        final entry = _entries[index];
        final item = _findItem(entry.itemId);
        return _buildEntryTile(entry, item);
      },
    );
  }

  Widget _buildEntryTile(LimitEntry entry, ItemMapping? item) {
    final remainingTime = entry.remainingTime(LimitService.windowDuration);
    final percentage = entry.usedPercentage;
    final progressColor = _getProgressColor(percentage);
    final isExpired = remainingTime == null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppTheme.panelColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                // Item icon
                SizedBox(
                  width: 40,
                  height: 40,
                  child: item != null && item.icon.trim().isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl:
                              'https://oldschool.runescape.wiki/images/${item.icon.replaceAll(' ', '_')}',
                          memCacheWidth: 48,
                          fit: BoxFit.contain,
                          placeholder: (context, url) => Container(
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(
                              Icons.inventory_2,
                              color: AppTheme.secondaryTextColor,
                              size: 20,
                            ),
                          ),
                          errorWidget: (context, url, error) => const Icon(
                            Icons.inventory_2,
                            color: AppTheme.secondaryTextColor,
                            size: 20,
                          ),
                        )
                      : const Icon(
                          Icons.inventory_2,
                          color: AppTheme.secondaryTextColor,
                          size: 20,
                        ),
                ),
                const SizedBox(width: 12),
                // Item name and progress
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.itemName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: percentage.clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: const Color(0xFF3A3A3A),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(progressColor),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // Bought / Limit
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${NumberFormat.decimalPattern('en_US').format(entry.quantityBought)} / ${NumberFormat.decimalPattern('en_US').format(entry.limit)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${NumberFormat.decimalPattern('en_US').format(entry.remaining)} remaining',
                      style: const TextStyle(
                        color: AppTheme.secondaryTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                // Countdown
                if (!isExpired)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: AppTheme.secondaryTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(remainingTime),
                          style: const TextStyle(
                            color: AppTheme.secondaryTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Expired',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // Reset button
                IconButton(
                  onPressed: () =>
                      _confirmReset(entry.itemId, entry.itemName),
                  icon: const Icon(
                    Icons.refresh,
                    color: AppTheme.secondaryTextColor,
                    size: 20,
                  ),
                  tooltip: 'Reset window',
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}