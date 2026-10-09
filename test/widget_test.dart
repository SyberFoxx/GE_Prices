// Smoke tests for GE Prices.
//
// The app has no dependency injection around networking, so these tests rely on
// the default flutter_test HttpClient, which fails every request with HTTP 400.
// That makes the bootstrap error path deterministic and lets us assert the UI
// degrades gracefully instead of crashing (see AGENTS.md, verification
// protocol step 4). A 400 is classified as a server error, not offline.
//
// BootstrapScreen also falls back to the on-disk price cache, so path_provider
// is mocked to a throwaway directory: an empty cache exercises the error path,
// and a seeded cache exercises the offline path.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ge_prices/main.dart';
import 'package:ge_prices/screens/about_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // path_provider's method channel name; the plugin has no test implementation,
  // so we answer it ourselves. The cache appends `/price_cache` to this path.
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory supportDir;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('ge_widget_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      return supportDir.path;
    });
  });

  setUp(() async {
    // HomeScreen reads SharedPreferences on mount; without a mock the plugin
    // channel is missing in tests.
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // Start every test with an empty cache. Removing (and not recreating) it
    // keeps the singleton's cached directory path valid while a fresh read
    // simply misses.
    final cacheDir = Directory('${supportDir.path}/price_cache');
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await supportDir.exists()) {
      await supportDir.delete(recursive: true);
    }
  });

  /// Lets the bootstrap network + disk-cache work finish, then rebuilds.
  ///
  /// `testWidgets` runs under a fake clock that never advances real `dart:io`
  /// (the on-disk cache). Each round alternates a fake-async [pump] — which
  /// drains the awaiting continuations and issues the next file read — with a
  /// real [runAsync] turn that lets that read actually complete. A handful of
  /// rounds is plenty for a couple of local temp files.
  Future<void> settleBootstrap(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pump();
  }

  testWidgets('app boots and shows a dignified error state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    // Let BootstrapScreen fire its requests and resolve to the server error.
    await settleBootstrap(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Server error (HTTP 400)'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('opens with cached data and an offline banner when offline', (
    WidgetTester tester,
  ) async {
    final cacheDir = Directory('${supportDir.path}/price_cache');
    // Synchronous on purpose: real async file I/O does not complete under the
    // fake clock of testWidgets unless it runs inside tester.runAsync.
    cacheDir.createSync(recursive: true);

    void seed(String key, String body) {
      File('${cacheDir.path}/$key.json').writeAsStringSync(
        jsonEncode(<String, Object?>{
          'savedAt': DateTime.now().toIso8601String(),
          'body': body,
        }),
      );
    }

    seed(
      'mapping',
      jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'id': 2,
          'name': 'Cannonball',
          'examine': '',
          'members': true,
          'limit': 7000,
          'icon': 'Cannonball.png',
          'highalch': 0,
        },
      ]),
    );
    seed(
      'latest',
      jsonEncode(<String, Object?>{
        'timestamp': 1,
        'data': <String, Object?>{
          '2': <String, Object?>{
            'high': 200,
            'low': 180,
            'highTime': 1,
            'lowTime': 1,
          },
        },
      }),
    );

    await tester.pumpWidget(const MyApp());
    await settleBootstrap(tester);

    expect(tester.takeException(), isNull);
    // HomeScreen (not the error screen) rendered from the cached snapshot.
    expect(find.text('GE Prices'), findsOneWidget);
    expect(
      find.text('Offline — showing the last saved prices.'),
      findsOneWidget,
    );
    expect(find.text('Server error (HTTP 400)'), findsNothing);

    // cached_network_image's cache manager schedules a one-shot 10s cleanup
    // timer; let it fire so no timer is left pending when the tree is disposed.
    await tester.pump(const Duration(seconds: 11));
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
