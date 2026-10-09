import 'package:flutter_test/flutter_test.dart';
import 'package:ge_prices/models/item_price.dart';
import 'package:ge_prices/utils/alchemy_profit.dart';

void main() {
  const natureRune = ItemMapping(
    id: 1,
    name: 'Nature rune',
    examine: '',
    members: false,
    limit: 18_000,
    icon: '',
    highAlch: 0,
  );
  const firstItem = ItemMapping(
    id: 2,
    name: 'First item',
    examine: '',
    members: false,
    limit: 100,
    icon: '',
    highAlch: 20_000,
  );
  const secondItem = ItemMapping(
    id: 3,
    name: 'Second item',
    examine: '',
    members: true,
    limit: 50,
    icon: '',
    highAlch: 15_000,
  );
  const prices = <String, ItemPrice>{
    '1': ItemPrice(high: 105, low: 100, highTime: null, lowTime: null),
    '2': ItemPrice(high: 1_000, low: 900, highTime: null, lowTime: null),
    '3': ItemPrice(high: 5_000, low: 4_800, highTime: null, lowTime: null),
  };

  test('calculates high alch profit for multiple items', () {
    expect(
      AlchemyProfit.calculate(
        item: firstItem,
        latestPrices: prices,
        natureRune: natureRune,
      ),
      18_900,
    );
    expect(
      AlchemyProfit.calculate(
        item: secondItem,
        latestPrices: prices,
        natureRune: natureRune,
      ),
      9_900,
    );
  });

  test(
    'uses a provided current high and safely handles missing nature rune',
    () {
      expect(
        AlchemyProfit.calculate(
          item: firstItem,
          latestPrices: prices,
          natureRune: natureRune,
          currentHigh: 2_000,
        ),
        17_900,
      );
      expect(
        AlchemyProfit.calculate(
          item: firstItem,
          latestPrices: prices,
          natureRune: null,
        ),
        0,
      );
    },
  );

  test('ranks opportunities by 4h buy-limit potential and filters membership', () {
    const items = <ItemMapping>[natureRune, firstItem, secondItem];

    final ranked = AlchemyProfit.rankedItems(
      items: items,
      latestPrices: prices,
    );
    expect(ranked.map((row) => row.item.id), <int>[2, 3]);
    expect(ranked.first.limitPotential, 1_890_000);
    expect(ranked.last.limitPotential, 495_000);

    final f2p = AlchemyProfit.rankedItems(
      items: items,
      latestPrices: prices,
      members: false,
    );
    final members = AlchemyProfit.rankedItems(
      items: items,
      latestPrices: prices,
      members: true,
    );
    expect(f2p.map((row) => row.item.id), <int>[2]);
    expect(members.map((row) => row.item.id), <int>[3]);
  });
}
