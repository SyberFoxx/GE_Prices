import 'package:flutter_test/flutter_test.dart';
import 'package:ge_prices/models/price_alert.dart';
import 'package:ge_prices/services/alerts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AlertsService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = AlertsService();
  });

  test('persists and reloads alert fields through JSON storage', () async {
    final createdAt = DateTime.utc(2026, 10, 9, 12);
    final alert = PriceAlert(
      itemId: 2,
      itemName: 'Cannonball',
      targetPrice: 1,
      direction: 'above',
      active: true,
      createdAt: createdAt,
    );

    await service.add(alert);
    final loaded = await service.load();

    expect(loaded, hasLength(1));
    expect(loaded.single.itemId, 2);
    expect(loaded.single.itemName, 'Cannonball');
    expect(loaded.single.targetPrice, 1);
    expect(loaded.single.direction, 'above');
    expect(loaded.single.active, isTrue);
    expect(loaded.single.createdAt, createdAt);
  });

  test('returns active alerts and supports deactivate and remove', () async {
    final activeAlert = PriceAlert(
      itemId: 2,
      itemName: 'Cannonball',
      targetPrice: 1,
      direction: 'above',
      active: true,
      createdAt: DateTime.utc(2026, 10, 9, 12),
    );
    final inactiveAlert = activeAlert.copyWith(active: false);
    await service.save(<PriceAlert>[activeAlert, inactiveAlert]);

    expect(await service.active(), hasLength(1));

    await service.setActive(activeAlert, false);
    expect(await service.active(), isEmpty);

    await service.remove(inactiveAlert);
    expect(await service.load(), isEmpty);
  });

  test('matches inclusive above and below target prices', () {
    final base = PriceAlert(
      itemId: 2,
      itemName: 'Cannonball',
      targetPrice: 1,
      direction: 'above',
      active: true,
      createdAt: DateTime.utc(2026, 10, 9, 12),
    );
    final below = PriceAlert(
      itemId: base.itemId,
      itemName: base.itemName,
      targetPrice: 5,
      direction: 'below',
      active: true,
      createdAt: base.createdAt,
    );

    expect(base.isTriggeredBy(1), isTrue);
    expect(base.isTriggeredBy(0), isFalse);
    expect(below.isTriggeredBy(5), isTrue);
    expect(below.isTriggeredBy(6), isFalse);
  });
}
