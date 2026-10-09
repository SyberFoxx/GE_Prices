// Smoke tests for GE Prices.
//
// The app has no dependency injection around networking, so these tests rely on
// the default flutter_test HttpClient, which fails every request. That makes the
// offline path deterministic and lets us assert the UI degrades gracefully
// instead of crashing (see AGENTS.md, verification protocol step 4).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ge_prices/main.dart';
import 'package:ge_prices/screens/about_screen.dart';

void main() {
  testWidgets('app boots and shows a dignified offline state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    // Let BootstrapScreen fire its requests and resolve to the offline error.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('About screen shows name, version and wiki attribution', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));

    expect(find.text('GE Prices'), findsOneWidget);
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.text('oldschool.runescape.wiki'), findsOneWidget);
  });
}
