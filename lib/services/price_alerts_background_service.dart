import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../app_navigation.dart';
import '../models/price_alert.dart';
import '../services/alerts_service.dart';
import 'osrs_api.dart';

const String _priceAlertTaskName = 'checkPriceAlerts';
const String _priceAlertWorkName = 'gePricesPriceAlertCheck';
const String _permissionPromptKey = 'price_alert_permission_prompted';

@pragma('vm:entry-point')
void priceAlertCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != _priceAlertTaskName) {
      return true;
    }

    return PriceAlertsBackgroundService.checkActiveAlerts();
  });
}

class PriceAlertsBackgroundService {
  PriceAlertsBackgroundService._();

  static const String channelId = 'price_alerts';
  static const String _channelName = 'Price alerts';
  static const String _channelDescription =
      'Notifications when an item reaches a saved price target.';

  /// Small status-bar icon. Must be a `res/drawable` resource: the Android
  /// plugin's `initialize` validates the default icon against the *drawable*
  /// resource type only, so a `mipmap` icon (e.g. `ic_launcher`) throws
  /// `invalid_icon` and blocks the whole alert flow.
  static const String _notificationIcon = 'ic_stat_ge_prices';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static Future<void>? _notificationsInitialization;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static int? _pendingLaunchItemId;

  static Future<void> initialize() async {
    if (!isAndroid) {
      return;
    }

    await _ensureNotificationsInitialized();

    // A tap can launch the app from terminated; remember the item to open once
    // the navigator exists.
    try {
      final launchDetails = await _notifications
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _pendingLaunchItemId = int.tryParse(
          launchDetails?.notificationResponse?.payload ?? '',
        );
      }
    } catch (error) {
      debugPrint('Could not read notification launch details: $error');
    }

    await Workmanager().initialize(priceAlertCallbackDispatcher);
    // 15-min granularity, no instant push; instant push requires backend (planned Pro tier).
    await Workmanager().registerPeriodicTask(
      _priceAlertWorkName,
      _priceAlertTaskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Opens the item a notification launched the app for, if any. Retries until
  /// the navigator is ready (the first frame may not have run yet).
  static Future<void> openPendingLaunchItem() async {
    final itemId = _pendingLaunchItemId;
    if (itemId == null) {
      return;
    }
    _pendingLaunchItemId = null;

    for (var attempt = 0; attempt < 15; attempt++) {
      if (appNavigatorKey.currentState != null) {
        await openItemDetail(itemId);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  static Future<void> _onNotificationTap(NotificationResponse response) async {
    final itemId = int.tryParse(response.payload ?? '');
    if (itemId == null) {
      return;
    }
    await openItemDetail(itemId);
  }

  static Future<bool> requestPermissionOnFirstAlert() async {
    if (!isAndroid) {
      return false;
    }

    await _ensureNotificationsInitialized();
    final preferences = await SharedPreferences.getInstance();
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      return false;
    }

    if (!(preferences.getBool(_permissionPromptKey) ?? false)) {
      final granted = await androidPlugin.requestNotificationsPermission();
      await preferences.setBool(_permissionPromptKey, true);
      return granted ?? await androidPlugin.areNotificationsEnabled() ?? false;
    }

    return await androidPlugin.areNotificationsEnabled() ?? false;
  }

  static Future<bool> checkActiveAlerts() async {
    final alertsService = AlertsService();

    try {
      final alerts = await alertsService.active();
      if (alerts.isEmpty) {
        return true;
      }

      await _ensureNotificationsInitialized();
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null &&
          (await androidPlugin.areNotificationsEnabled() ?? true) == false) {
        return true;
      }

      final latestPrices = await OsrsApi().fetchLatestPrices();
      for (final alert in alerts) {
        final itemPrice = latestPrices.data[alert.itemId.toString()];
        // "Below" targets watch the instant-sell price (low): using the
        // instant-buy price (high) would only ever fire after the market had
        // already moved past the target.
        final currentPrice = alert.direction == 'above'
            ? itemPrice?.high
            : itemPrice?.low;
        if (currentPrice == null || !alert.isTriggeredBy(currentPrice)) {
          continue;
        }

        try {
          await _notifications.show(
            id: _notificationId(alert),
            title:
                '${alert.itemName} crossed ${_formatPrice(alert.targetPrice)} (now ${_formatPrice(currentPrice)})',
            body: 'Price target reached.',
            payload: alert.itemId.toString(),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                channelId,
                _channelName,
                channelDescription: _channelDescription,
                icon: _notificationIcon,
                importance: Importance.high,
                priority: Priority.high,
                enableVibration: false,
              ),
            ),
          );
          await alertsService.markTriggered(alert, DateTime.now());
        } catch (error) {
          debugPrint('Price alert notification failed: $error');
        }
      }

      return true;
    } catch (error) {
      // A failed network cycle leaves alerts active for the next 15-minute run.
      debugPrint('Price alert background check failed: $error');
      return true;
    }
  }

  static Future<void> _ensureNotificationsInitialized() async {
    try {
      await (_notificationsInitialization ??= _initializeNotifications());
    } catch (_) {
      _notificationsInitialization = null;
      rethrow;
    }
  }

  static Future<void> _initializeNotifications() async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_notificationIcon),
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        // The manifest removes VIBRATE (see AndroidManifest.xml); keep the
        // channel consistent so no vibration is requested without the permission.
        enableVibration: false,
      ),
    );
  }

  static int _notificationId(PriceAlert alert) =>
      (alert.itemId * 31 +
          alert.targetPrice * 17 +
          alert.createdAt.millisecondsSinceEpoch) &
      0x7fffffff;

  static String _formatPrice(int price) => '$price gp';
}
