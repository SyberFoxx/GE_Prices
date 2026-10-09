/// Represents a buy limit tracking entry for an item.
/// 
/// The 4-hour window starts when the player first buys an item.
/// The limit value is copied from the item mapping at the time of registration.
/// 
/// NOTE: manual tracking - the game API does not expose remaining buy limits.
class LimitEntry {
  final int itemId;
  final String itemName;
  final int quantityBought;
  final int windowStart; // epoch milliseconds
  final int limit; // copied from mapping at registration time

  const LimitEntry({
    required this.itemId,
    required this.itemName,
    required this.quantityBought,
    required this.windowStart,
    required this.limit,
  });

  /// Returns the remaining quantity the player can still buy in this window.
  int get remaining => (limit - quantityBought).clamp(0, limit);

  /// Returns the percentage of the limit that has been used (0.0 to 1.0).
  double get usedPercentage => limit > 0 ? quantityBought / limit : 0.0;

  /// Returns true if the 4-hour window has expired.
  bool isExpired(Duration windowDuration) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - windowStart >= windowDuration.inMilliseconds;
  }

  /// Returns the remaining time in the current window, or null if expired.
  Duration? remainingTime(Duration windowDuration) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowEnd = windowStart + windowDuration.inMilliseconds;
    final remainingMs = windowEnd - now;
    if (remainingMs <= 0) return null;
    return Duration(milliseconds: remainingMs);
  }

  /// Returns a new LimitEntry with the quantity added.
  LimitEntry addQuantity(int quantity) {
    return LimitEntry(
      itemId: itemId,
      itemName: itemName,
      quantityBought: quantityBought + quantity,
      windowStart: windowStart,
      limit: limit,
    );
  }

  /// Returns a new LimitEntry with a new window started.
  LimitEntry startNewWindow(int quantity, int newLimit) {
    return LimitEntry(
      itemId: itemId,
      itemName: itemName,
      quantityBought: quantity,
      windowStart: DateTime.now().millisecondsSinceEpoch,
      limit: newLimit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'quantityBought': quantityBought,
      'windowStart': windowStart,
      'limit': limit,
    };
  }

  factory LimitEntry.fromJson(Map<String, dynamic> json) {
    return LimitEntry(
      itemId: json['itemId'] as int? ?? 0,
      itemName: json['itemName'] as String? ?? '',
      quantityBought: json['quantityBought'] as int? ?? 0,
      windowStart: json['windowStart'] as int? ?? 0,
      limit: json['limit'] as int? ?? 0,
    );
  }
}