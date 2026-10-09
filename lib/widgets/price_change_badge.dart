import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small ▲/▼ arrow with the 24h % change ("—" when unknown): green when up,
/// red when down, grey when flat or missing data.
class PriceChangeBadge extends StatelessWidget {
  const PriceChangeBadge(this.percent, {super.key});

  final double? percent;

  @override
  Widget build(BuildContext context) {
    final value = percent;
    if (value == null) {
      return const Text(
        '—',
        style: TextStyle(color: AppTheme.secondaryTextColor),
      );
    }

    final Color color;
    final String arrow;
    if (value > 0) {
      color = Colors.greenAccent;
      arrow = '▲';
    } else if (value < 0) {
      color = Colors.redAccent;
      arrow = '▼';
    } else {
      color = AppTheme.secondaryTextColor;
      arrow = '▲';
    }

    return Text(
      '$arrow ${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%',
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}