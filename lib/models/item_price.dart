class ItemMapping {
  final int id;
  final String name;
  final String examine;
  final bool members;
  final int limit;
  final String icon;

  const ItemMapping({
    required this.id,
    required this.name,
    required this.examine,
    required this.members,
    required this.limit,
    required this.icon,
  });

  factory ItemMapping.fromJson(Map<String, dynamic> json) {
    return ItemMapping(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      examine: json['examine'] as String? ?? '',
      members: json['members'] as bool? ?? false,
      limit: json['limit'] as int? ?? 0,
      icon: json['icon'] as String? ?? '',
    );
  }
}

class ItemPrice {
  final int avgHigh;
  final int avgLow;
  final int highTime;
  final int lowTime;
  final int high;
  final int low;

  const ItemPrice({
    required this.avgHigh,
    required this.avgLow,
    required this.highTime,
    required this.lowTime,
    required this.high,
    required this.low,
  });

  factory ItemPrice.fromJson(Map<String, dynamic> json) {
    return ItemPrice(
      avgHigh: json['avgHigh'] as int? ?? 0,
      avgLow: json['avgLow'] as int? ?? 0,
      highTime: json['highTime'] as int? ?? 0,
      lowTime: json['lowTime'] as int? ?? 0,
      high: json['high'] as int? ?? 0,
      low: json['low'] as int? ?? 0,
    );
  }
}

class LatestPriceResponse {
  final int timestamp;
  final Map<String, ItemPrice> data;

  const LatestPriceResponse({
    required this.timestamp,
    required this.data,
  });

  factory LatestPriceResponse.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final mappedData = <String, ItemPrice>{};

    if (rawData is Map<String, dynamic>) {
      for (final entry in rawData.entries) {
        mappedData[entry.key] = ItemPrice.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }

    return LatestPriceResponse(
      timestamp: json['timestamp'] as int? ?? 0,
      data: mappedData,
    );
  }
}
