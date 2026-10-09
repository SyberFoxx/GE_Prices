import 'package:flutter/material.dart';

import 'screens/bootstrap_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
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
