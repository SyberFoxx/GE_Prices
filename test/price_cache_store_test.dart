// Unit tests for the on-disk price cache (services/price_cache_store.dart).
//
// The directory is injected so the tests run on the VM without the
// path_provider plugin.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ge_prices/services/price_cache_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ge_cache_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PriceCacheStore storeIn(Directory dir) =>
      PriceCacheStore(directoryProvider: () async => dir);

  group('PriceCacheStore', () {
    test('round-trips a saved body and its timestamp', () async {
      final store = storeIn(tempDir);
      final savedAt = DateTime(2026, 1, 2, 3, 4, 5);

      await store.save('latest', '{"data":{}}', savedAt: savedAt);
      final loaded = await store.load('latest');

      expect(loaded, isNotNull);
      expect(loaded!.body, '{"data":{}}');
      expect(loaded.savedAt, savedAt);
    });

    test('creates the cache directory on demand', () async {
      final nested = Directory('${tempDir.path}/price_cache');
      final store = storeIn(nested);

      await store.save('mapping', '[]');

      expect(await nested.exists(), isTrue);
    });

    test('returns null for an unknown key', () async {
      final store = storeIn(tempDir);
      await store.save('not-a-key', 'x');
      expect(await store.load('not-a-key'), isNull);
    });

    test('returns null when a file has never been written', () async {
      final store = storeIn(tempDir);
      expect(await store.load('hourly'), isNull);
    });

    test('treats a corrupt file as a miss instead of throwing', () async {
      final file = File('${tempDir.path}/latest.json');
      await file.writeAsString('this is not json');

      final store = storeIn(tempDir);
      expect(await store.load('latest'), isNull);
    });

    test('ignores a payload with a missing body', () async {
      final file = File('${tempDir.path}/latest.json');
      await file.writeAsString('{"savedAt":"2026-01-02T03:04:05.000"}');

      final store = storeIn(tempDir);
      expect(await store.load('latest'), isNull);
    });

    test('never throws when the directory cannot be resolved', () async {
      final store = PriceCacheStore(
        directoryProvider: () async => throw Exception('no plugin'),
      );

      await store.save('latest', '{"data":{}}');
      expect(await store.load('latest'), isNull);
    });
  });
}
