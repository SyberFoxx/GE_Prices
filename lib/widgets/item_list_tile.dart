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

  String _formatPrice(int? value) {
    if (value == null) {
      return '—';
    }

    final formatter = NumberFormat.decimalPattern('en_US');
    return '${formatter.format(value)} gp';
  }

  @override
  Widget build(BuildContext context) {
    final iconUrl = item.icon.trim().isEmpty
        ? null
        : 'https://oldschool.runescape.wiki/images/${item.icon.replaceAll(' ', '_')}';

    final priceText = price == null
        ? 'Sin datos disponibles'
        : 'High: ${_formatPrice(price!.high)}\nLow: ${_formatPrice(price!.low)}';

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
              : Image.network(
                  iconUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.image_not_supported_outlined,
                      color: AppTheme.secondaryTextColor,
                    );
                  },
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
