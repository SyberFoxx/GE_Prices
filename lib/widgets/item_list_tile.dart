import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final priceText = price == null ? 'Sin datos' : 'Avg High: ${price!.avgHigh} • Avg Low: ${price!.avgLow}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppTheme.panelColor,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        trailing: const Icon(Icons.chevron_right, color: AppTheme.secondaryTextColor),
        onTap: onTap,
      ),
    );
  }
}
