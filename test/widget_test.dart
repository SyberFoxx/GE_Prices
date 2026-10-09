// Smoke tests for GE Prices.
//
// The app has no dependency injection around networking, so these tests rely on
// the default flutter_test HttpClient, which fails every request with HTTP 400.
// That makes the bootstrap error path deterministic and lets us assert the UI
// degrades gracefully instead of crashing (see AGENTS.md, verification
// protocol step 4). A 400 is classified as a server error, not offline.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ge_prices/main.dart';
import 'package:ge_prices/screens/about_screen.dart';

void main() {
  testWidgets('app boots and shows a dignified error state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    // Let BootstrapScreen fire its requests and resolve to the server error.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Server error (HTTP 400)'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('About screen shows name, version and wiki attribution', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    // Let the version lookup resolve. There is no package_info_plus platform
    // implementation in tests, so the version falls back to the "—" placeholder
    // (on a device it shows the real pubspec version).
    await tester.pump();

    expect(find.text('GE Prices'), findsOneWidget);
    expect(find.text('Version —'), findsOneWidget);
    expect(find.text('oldschool.runescape.wiki'), findsOneWidget);
  });
}
