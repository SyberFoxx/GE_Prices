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
  final int? high;
  final int? low;
  final int? highTime;
  final int? lowTime;

  const ItemPrice({
    required this.high,
    required this.low,
    required this.highTime,
    required this.lowTime,
  });

  factory ItemPrice.fromJson(Map<String, dynamic> json) {
    int? toIntOrNull(dynamic value) {
      if (value is num) {
        return value.toInt();
      }
      return null;
    }

    return ItemPrice(
      high: toIntOrNull(json['high']),
      low: toIntOrNull(json['low']),
      highTime: toIntOrNull(json['highTime']),
      lowTime: toIntOrNull(json['lowTime']),
    );
  }
}

class LatestPriceResponse {
  final int timestamp;
  final Map<String, ItemPrice> data;

  const LatestPriceResponse({required this.timestamp, required this.data});

  factory LatestPriceResponse.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final mappedData = <String, ItemPrice>{};

    if (rawData is Map) {
      for (final entry in rawData.entries) {
        final value = entry.value;
        if (value is Map) {
          mappedData[entry.key.toString()] = ItemPrice.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      }
    }

    return LatestPriceResponse(
      timestamp: json['timestamp'] is num
          ? (json['timestamp'] as num).toInt()
          : 0,
      data: mappedData,
    );
  }
}

class HistoricalPricePoint {
  final int timestamp;
  final int? avgHighPrice;
  final int? avgLowPrice;

  const HistoricalPricePoint({
    required this.timestamp,
    required this.avgHighPrice,
    required this.avgLowPrice,
  });

  factory HistoricalPricePoint.fromJson(Map<String, dynamic> json) {
    int? toIntOrNull(dynamic value) {
      if (value is num) {
        return value.toInt();
      }
      return null;
    }

    return HistoricalPricePoint(
      timestamp: json['timestamp'] is num
          ? (json['timestamp'] as num).toInt()
          : 0,
      avgHighPrice: toIntOrNull(json['avgHighPrice']),
      avgLowPrice: toIntOrNull(json['avgLowPrice']),
    );
  }
}

class HistoricalPriceResponse {
  final List<HistoricalPricePoint> data;

  const HistoricalPriceResponse({required this.data});

  factory HistoricalPriceResponse.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    if (rawData is! List) {
      return const HistoricalPriceResponse(data: <HistoricalPricePoint>[]);
    }

    return HistoricalPriceResponse(
      data: rawData
          .map(
            (entry) => HistoricalPricePoint.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .where(
            (point) =>
                point.timestamp > 0 &&
                point.avgHighPrice != null &&
                point.avgLowPrice != null,
          )
          .toList(),
    );
  }
}
