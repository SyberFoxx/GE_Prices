import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item_price.dart';
import '../theme/app_theme.dart';

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

  String _formatCompactPrice(int? value) {
    if (value == null) {
      return '—';
    }

    if (value >= 1_000_000) {
      final formatted = (value / 1_000_000).toStringAsFixed(1);
      return '${formatted.endsWith('.0') ? formatted.substring(0, formatted.length - 2) : formatted}M';
    }

    if (value >= 1_000) {
      final formatted = (value / 1_000).toStringAsFixed(1);
      return '${formatted.endsWith('.0') ? formatted.substring(0, formatted.length - 2) : formatted}k';
    }

    return NumberFormat.decimalPattern('en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final iconUrl = item.icon.trim().isEmpty
        ? null
        : 'https://oldschool.runescape.wiki/images/${item.icon.replaceAll(' ', '_')}';

    final priceText = price == null
        ? 'Sin datos disponibles'
        : 'High: ${_formatCompactPrice(price!.high)}\nLow: ${_formatCompactPrice(price!.low)}';

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
        subtitle: Text(
          priceText,
          style: const TextStyle(color: AppTheme.secondaryTextColor),
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
