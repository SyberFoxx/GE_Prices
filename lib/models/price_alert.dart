class PriceAlert {
  const PriceAlert({
    required this.itemId,
    required this.itemName,
    required this.targetPrice,
    required this.direction,
    required this.active,
    required this.createdAt,
    this.triggeredAt,
  });

  final int itemId;
  final String itemName;
  final int targetPrice;
  final String direction;
  final bool active;
  final DateTime createdAt;

  /// When the alert fired, or null while it has never triggered. A triggered
  /// alert is deactivated but kept as history instead of silently disappearing.
  final DateTime? triggeredAt;

  bool get isTriggered => triggeredAt != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'itemName': itemName,
    'targetPrice': targetPrice,
    'direction': direction,
    'active': active,
    'createdAt': createdAt.toIso8601String(),
    'triggeredAt': triggeredAt?.toIso8601String(),
  };

  factory PriceAlert.fromJson(Map<String, dynamic> json) {
    final direction = json['direction'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (direction != 'above' && direction != 'below') {
      throw const FormatException('Invalid price alert direction.');
    }
    if (createdAt == null) {
      throw const FormatException('Invalid price alert creation time.');
    }

    return PriceAlert(
      itemId: (json['itemId'] as num).toInt(),
      itemName: json['itemName'] as String,
      targetPrice: (json['targetPrice'] as num).toInt(),
      direction: direction as String,
      active: json['active'] as bool,
      createdAt: createdAt,
      // Absent on alerts stored before history existed.
      triggeredAt: DateTime.tryParse(json['triggeredAt'] as String? ?? ''),
    );
  }

  PriceAlert copyWith({bool? active, DateTime? triggeredAt}) => PriceAlert(
    itemId: itemId,
    itemName: itemName,
    targetPrice: targetPrice,
    direction: direction,
    active: active ?? this.active,
    createdAt: createdAt,
    triggeredAt: triggeredAt ?? this.triggeredAt,
  );

  bool isTriggeredBy(int currentPrice) {
    return direction == 'above'
        ? currentPrice >= targetPrice
        : currentPrice <= targetPrice;
  }
}
