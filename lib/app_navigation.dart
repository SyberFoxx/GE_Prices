import 'package:flutter/material.dart';

import 'models/item_price.dart';
import 'screens/detail_screen.dart';
import 'services/osrs_api.dart';

/// Global navigator key so code without a [BuildContext] — e.g. a notification
/// tap handler — can push a route.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Opens the detail screen for [itemId] using the shared API cache (or the
/// on-disk snapshot when offline). Best effort: if the item cannot be resolved
/// nothing happens.
Future<void> openItemDetail(int itemId) async {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    return;
  }

  try {
    final api = OsrsApi();
    final items = await api.fetchItemMapping();
    final latest = await api.fetchLatestPrices();

    ItemMapping? resolved;
    for (final candidate in items) {
      if (candidate.id == itemId) {
        resolved = candidate;
        break;
      }
    }
    if (resolved == null) {
      return;
    }

    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          item: resolved!,
          currentPrice: latest.data[itemId.toString()],
          allItems: items,
          latestPrices: latest.data,
        ),
      ),
    );
  } catch (error) {
    debugPrint('Could not open item $itemId from notification: $error');
  }
}
