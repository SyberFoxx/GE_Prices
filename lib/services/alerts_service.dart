import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/price_alert.dart';

class AlertsService {
  static const String _storageKey = 'price_alerts';

  Future<List<PriceAlert>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return <PriceAlert>[];
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        return <PriceAlert>[];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map((json) {
            try {
              return PriceAlert.fromJson(json);
            } on FormatException {
              return null;
            } on TypeError {
              return null;
            }
          })
          .whereType<PriceAlert>()
          .toList();
    } on FormatException {
      return <PriceAlert>[];
    }
  }

  Future<List<PriceAlert>> active() async {
    return (await load()).where((alert) => alert.active).toList();
  }

  /// Alerts that already fired, newest first, kept as history.
  Future<List<PriceAlert>> triggered() async {
    final alerts = (await load()).where((alert) => alert.isTriggered).toList();
    alerts.sort(
      (a, b) => (b.triggeredAt ?? b.createdAt).compareTo(
        a.triggeredAt ?? a.createdAt,
      ),
    );
    return alerts;
  }

  Future<void> save(List<PriceAlert> alerts) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(alerts.map((alert) => alert.toJson()).toList()),
    );
  }

  Future<void> add(PriceAlert alert) async {
    final alerts = await load();
    alerts.add(alert);
    await save(alerts);
  }

  Future<void> remove(PriceAlert alert) async {
    final alerts = await load();
    alerts.removeWhere(_hasSameIdentityAs(alert));
    await save(alerts);
  }

  Future<void> setActive(PriceAlert alert, bool active) async {
    final alerts = await load();
    final index = alerts.indexWhere(_hasSameIdentityAs(alert));
    if (index < 0) {
      return;
    }

    alerts[index] = alerts[index].copyWith(active: active);
    await save(alerts);
  }

  /// Records that [alert] fired at [at] and deactivates it, keeping it in the
  /// triggered history so a fired alert no longer vanishes silently.
  Future<void> markTriggered(PriceAlert alert, DateTime at) async {
    final alerts = await load();
    final index = alerts.indexWhere(_hasSameIdentityAs(alert));
    if (index < 0) {
      return;
    }

    alerts[index] = alerts[index].copyWith(active: false, triggeredAt: at);
    await save(alerts);
  }

  bool Function(PriceAlert) _hasSameIdentityAs(PriceAlert alert) {
    return (candidate) =>
        candidate.itemId == alert.itemId &&
        candidate.createdAt.isAtSameMomentAs(alert.createdAt);
  }
}
