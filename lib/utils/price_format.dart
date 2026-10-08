import 'package:intl/intl.dart';

class PriceFormat {
  static String compact(int? value) {
    if (value == null) {
      return '—';
    }

    if (value >= 1_000_000) {
      final numericValue = value / 1_000_000;
      return '${_trimTrailingZeros(numericValue)}M';
    }

    if (value >= 1_000) {
      final numericValue = value / 1_000;
      return '${_trimTrailingZeros(numericValue)}k';
    }

    return NumberFormat.decimalPattern('en_US').format(value);
  }

  static String full(int? value) {
    if (value == null) {
      return '—';
    }

    return '${NumberFormat.decimalPattern('en_US').format(value)} gp';
  }

  static String marginText({required int? high, required int? low}) {
    if (high == null || low == null || high <= 0 || low <= 0) {
      return '';
    }

    final margin = high - low;
    final pct = (margin / low) * 100;
    final sign = pct >= 0 ? '+' : '';

    return 'Margen: ${NumberFormat.decimalPattern('en_US').format(margin)} gp ($sign${pct.toStringAsFixed(1)}%)';
  }

  static String _trimTrailingZeros(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
}
