import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/item_price.dart';
import '../theme/app_theme.dart';

class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.title,
  });

  final ItemMapping item;
  final VoidCallback onTap;
  final Widget? subtitle;
  final Widget? trailing;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    final iconUrl = item.icon.trim().isEmpty
        ? null
        : 'https://oldschool.runescape.wiki/images/${item.icon.replaceAll(' ', '_')}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppTheme.panelColor,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: SizedBox(
          width: 40,
          height: 40,
          child: iconUrl == null
              ? const Icon(
                  Icons.inventory_2,
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
        title: title ??
            Text(
              item.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
        subtitle: subtitle,
        trailing: trailing ??
            const Icon(
              Icons.chevron_right,
              color: AppTheme.secondaryTextColor,
            ),
        onTap: onTap,
      ),
    );
  }
}
