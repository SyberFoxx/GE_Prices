import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/bootstrap_screen.dart';
import 'services/price_alerts_background_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    unawaited(_initializePriceAlertsSafely());
  }
  runApp(const MyApp());
}

Future<void> _initializePriceAlertsSafely() async {
  try {
    await PriceAlertsBackgroundService.initialize();
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
      theme: AppTheme.darkTheme,
      home: const BootstrapScreen(),
    );
  }
}
