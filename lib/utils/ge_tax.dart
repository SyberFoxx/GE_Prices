class GeTax {
  // GE tax: 2% on the sale price, capped at 5,000,000 gp.
  // Some items are exempt (e.g. bonds), but for now we estimate for all items.
  // Future improvement: maintain a dedicated exempt-item list and skip taxation there.
  static const double taxRate = 0.02;
  static const double taxCap = 5000000;

  /// GE tax charged when selling a single unit at [salePrice]:
  /// 2% of the sale price, capped at 5,000,000 gp. Returns 0 for
  /// non-positive prices.
  static double taxOn({required int salePrice}) {
    if (salePrice <= 0) {
      return 0;
    }
    return (salePrice * taxRate).clamp(0.0, taxCap);
  }

  static double netMargin({required int high, required int low}) {
    if (high <= 0 || low <= 0) {
      return 0;
    }

    final tax = taxOn(salePrice: high);
    final value = ((high - tax) - low).toDouble();
    return value;
  }
}
