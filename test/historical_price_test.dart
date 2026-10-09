import 'package:flutter_test/flutter_test.dart';
import 'package:ge_prices/models/item_price.dart';

void main() {
  test('parses real traded volume from a timeseries point', () {
    final point = HistoricalPricePoint.fromJson(<String, dynamic>{
      'timestamp': 1700000000,
      'avgHighPrice': 100,
      'avgLowPrice': 90,
      'highPriceVolume': 250,
      'lowPriceVolume': 130,
    });

    expect(point.highPriceVolume, 250);
    expect(point.lowPriceVolume, 130);
  });

  test('leaves volume null when the API omits it', () {
    final point = HistoricalPricePoint.fromJson(<String, dynamic>{
      'timestamp': 1700000000,
      'avgHighPrice': 100,
      'avgLowPrice': 90,
    });

    expect(point.highPriceVolume, isNull);
    expect(point.lowPriceVolume, isNull);
  });

  test('drops windows with no trades and invalid timestamps', () {
    final response = HistoricalPriceResponse.fromJson(<String, dynamic>{
      'data': <dynamic>[
        <String, dynamic>{
          'timestamp': 1,
          'avgHighPrice': 100,
          'avgLowPrice': 90,
          'highPriceVolume': 5,
          'lowPriceVolume': 5,
        },
        <String, dynamic>{
          'timestamp': 2,
          'avgHighPrice': null,
          'avgLowPrice': null,
          'highPriceVolume': null,
          'lowPriceVolume': null,
        },
        <String, dynamic>{
          'timestamp': 0,
          'avgHighPrice': 10,
          'avgLowPrice': 5,
          'highPriceVolume': 1,
          'lowPriceVolume': 1,
        },
      ],
    });

    expect(response.data.length, 1);
    expect(response.data.single.avgHighPrice, 100);
    expect(response.data.single.highPriceVolume, 5);
  });
}
