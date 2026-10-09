import '../models/item_price.dart';

class AlchemyOpportunity {
  const AlchemyOpportunity({
    required this.item,
    required this.currentHigh,
    required this.profit,
    required this.limitPotential,
  });

  final ItemMapping item;
  final int currentHigh;
  final double profit;

  /// Profit if you buy the full 4h GE buy limit once (`profit * limit`).
  /// This is a per-4h figure, not a daily one.
  final double limitPotential;
}

class AlchemyProfit {
  static ItemMapping? findNatureRune(Iterable<ItemMapping> items) {
    for (final item in items) {
      if (item.name == 'Nature rune') {
        return item;
      }
    }
    return null;
  }

  static double calculate({
    required ItemMapping item,
    required Map<String, ItemPrice> latestPrices,
    required ItemMapping? natureRune,
    int? currentHigh,
  }) {
    if (item.highAlch <= 0 || natureRune == null) {
      return 0;
    }

    final buyHigh = currentHigh ?? latestPrices[item.id.toString()]?.high ?? 0;
    final natureRuneLow = latestPrices[natureRune.id.toString()]?.low ?? 0;
    if (buyHigh <= 0 || natureRuneLow <= 0) {
      return 0;
    }

    return (item.highAlch - natureRuneLow - buyHigh).toDouble();
  }

  static List<AlchemyOpportunity> rankedItems({
    required Iterable<ItemMapping> items,
    required Map<String, ItemPrice> latestPrices,
    bool? members,
  }) {
    final natureRune = findNatureRune(items);
    final rows = <AlchemyOpportunity>[];

    for (final item in items) {
      if (item.highAlch <= 0 || (members != null && item.members != members)) {
        continue;
      }

      final currentHigh = latestPrices[item.id.toString()]?.high ?? 0;
      final profit = calculate(
        item: item,
        latestPrices: latestPrices,
        natureRune: natureRune,
      );
      if (profit <= 0) {
        continue;
      }

      rows.add(
        AlchemyOpportunity(
          item: item,
          currentHigh: currentHigh,
          profit: profit,
          limitPotential: profit * item.limit,
        ),
      );
    }

    rows.sort((a, b) => b.limitPotential.compareTo(a.limitPotential));
    return rows.take(50).toList();
  }
}
