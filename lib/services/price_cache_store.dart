import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A raw response body persisted to disk with the moment it was captured.
class CachedBody {
  const CachedBody({required this.body, required this.savedAt});

  /// The untouched response body, so the caller can use the same parser as a
  /// live fetch.
  final String body;

  /// When the body was captured (used for the honest "last updated" badge).
  final DateTime savedAt;
}

/// Best-effort on-disk cache of the Wiki responses the app needs to open
/// offline (item mapping, latest prices and the 1h snapshot).
///
/// Every operation is fail-safe: a missing platform plugin, a read-only
/// filesystem or a corrupt file simply yields `null` / a no-op. Caching can
/// therefore never break a network fetch or a screen.
///
/// The directory is injectable for tests; production uses the app support
/// directory.
class PriceCacheStore {
  PriceCacheStore({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? _defaultDirectory;

  static const Map<String, String> _fileNames = <String, String>{
    'mapping': 'mapping.json',
    'latest': 'latest.json',
    'hourly': 'hourly.json',
  };

  final Future<Directory> Function() _directoryProvider;
  Directory? _directory;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/price_cache');
  }

  Future<Directory?> _ensureDirectory() async {
    final cached = _directory;
    if (cached != null) {
      return cached;
    }

    try {
      final directory = await _directoryProvider();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      _directory = directory;
      return directory;
    } catch (_) {
      return null;
    }
  }

  /// Writes [body] for [key] (`mapping` | `latest` | `hourly`). Never throws.
  Future<void> save(String key, String body, {DateTime? savedAt}) async {
    final fileName = _fileNames[key];
    if (fileName == null) {
      return;
    }

    final directory = await _ensureDirectory();
    if (directory == null) {
      return;
    }

    try {
      final payload = jsonEncode(<String, Object?>{
        'savedAt': (savedAt ?? DateTime.now()).toIso8601String(),
        'body': body,
      });
      await File('${directory.path}/$fileName').writeAsString(
        payload,
        flush: true,
      );
    } catch (_) {
      // A failed cache write must never break a fetch.
    }
  }

  /// Reads the cached body for [key], or `null` if absent/unreadable. Never
  /// throws.
  Future<CachedBody?> load(String key) async {
    final fileName = _fileNames[key];
    if (fileName == null) {
      return null;
    }

    final directory = await _ensureDirectory();
    if (directory == null) {
      return null;
    }

    try {
      final file = File('${directory.path}/$fileName');
      if (!await file.exists()) {
        return null;
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }

      final body = decoded['body'];
      final savedAt = DateTime.tryParse(decoded['savedAt'] as String? ?? '');
      if (body is! String || body.isEmpty || savedAt == null) {
        return null;
      }

      return CachedBody(body: body, savedAt: savedAt);
    } catch (_) {
      // Corrupt or partially written file: treat as a miss.
      return null;
    }
  }
}
