import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'screens/bootstrap_screen.dart';
import 'services/price_alerts_background_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    unawaited(_initializePriceAlertsSafely());
    WidgetsBinding.instance.addObserver(_ForegroundAlertReconciler());
  }
  runApp(const MyApp());
}

/// Reconciles price alerts whenever the app returns to the foreground: alerts
/// crossed while the system deferred the background check are notified right
/// away instead of staying silent until the next 15-minute run.
class _ForegroundAlertReconciler with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    unawaited(PriceAlertsBackgroundService.reconcileNow());
  }
}

Future<void> _initializePriceAlertsSafely() async {
  try {
    await PriceAlertsBackgroundService.initialize();
    // A notification tap that launched the app opens its item once the
    // navigator exists.
    unawaited(PriceAlertsBackgroundService.openPendingLaunchItem());
    // Deterministic foreground check on cold start, independent of the
    // lifecycle-observer timing above.
    unawaited(PriceAlertsBackgroundService.reconcileNow());
  } catch (error) {
    debugPrint('Background price alerts unavailable: $error');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GE Prices',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.darkTheme,
      home: const BootstrapScreen(),
    );
  }
}
