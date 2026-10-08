import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/item_price.dart';
import '../theme/app_theme.dart';
import '../utils/price_format.dart';

class ItemListTile extends StatelessWidget {
  const ItemListTile({
    super.key,
    required this.item,
    required this.onTap,
    this.price,
  });

  final ItemMapping item;
  final ItemPrice? price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconUrl = item.icon.trim().isEmpty
        ? null
        : 'https://oldschool.runescape.wiki/images/${item.icon.replaceAll(' ', '_')}';

    final hasSpreadData =
        price != null &&
        price!.high != null &&
        price!.low != null &&
        price!.high! > 0 &&
        price!.low! > 0;
    final spreadText = hasSpreadData
        ? PriceFormat.marginText(high: price!.high, low: price!.low)
        : null;
    final spreadPct = hasSpreadData ? ((price!.high! - price!.low!) / price!.low!) * 100 : 0.0;

    final subtitleChildren = <Widget>[];

    if (price == null) {
      subtitleChildren.add(
        const Text(
          'Sin datos disponibles',
          style: TextStyle(color: AppTheme.secondaryTextColor),
        ),
      );
    } else {
      subtitleChildren.add(
        Text(
          'High: ${PriceFormat.compact(price!.high)}\nLow: ${PriceFormat.compact(price!.low)}',
          style: const TextStyle(color: AppTheme.secondaryTextColor),
        ),
      );

      if (spreadText != null && spreadText.isNotEmpty) {
        subtitleChildren.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              spreadText,
              style: TextStyle(
                color: spreadPct >= 2 ? Colors.green : AppTheme.secondaryTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppTheme.panelColor,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: SizedBox(
          width: 40,
          height: 40,
          child: iconUrl == null
              ? const Icon(
                  Icons.image_not_supported_outlined,
                  color: AppTheme.secondaryTextColor,
                )
              : CachedNetworkImage(
                  imageUrl: iconUrl,
                  memCacheWidth: 64,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    color: const Color(0xFF2A2A2A),
                    child: const Icon(
                      Icons.inventory_2,
                      color: AppTheme.secondaryTextColor,
                    ),
                  ),
                  errorWidget: (context, url, error) => const Icon(
                    Icons.inventory_2,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
        ),
        title: Text(
          item.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: subtitleChildren,
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppTheme.secondaryTextColor,
        ),
        onTap: onTap,
      ),
    );
  }
}
