// Unit tests for the fetch-error classifier (utils/fetch_errors.dart).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ge_prices/services/osrs_api.dart';
import 'package:ge_prices/utils/fetch_errors.dart';

void main() {
  group('describeFetchError', () {
    test('maps SocketException to network', () {
      final info = describeFetchError(const SocketException('refused'));
      expect(info.kind, FetchErrorKind.network);
      expect(info.title, 'No internet connection');
    });

    test('maps http ClientException to network', () {
      final info = describeFetchError(http.ClientException('Connection failed'));
      expect(info.kind, FetchErrorKind.network);
    });

    test('maps OsrsApiHttpException to server with the status code', () {
      final info = describeFetchError(const OsrsApiHttpException(500));
      expect(info.kind, FetchErrorKind.server);
      expect(info.title, 'Server error (HTTP 500)');
    });

    test('maps FormatException to format', () {
      final info = describeFetchError(const FormatException('no data key'));
      expect(info.kind, FetchErrorKind.format);
      expect(info.title, 'Unexpected data from the server');
    });

    test('maps anything else to unknown', () {
      final info = describeFetchError(ArgumentError('boom'));
      expect(info.kind, FetchErrorKind.unknown);
      expect(info.title, 'Something went wrong');
    });

    test('unwraps ParallelWaitError from the parallel startup fetch', () {
      // ParallelWaitError(values, errors): the SDK builds the errors record
      // itself for record `.wait`, so unwrapping must read it correctly.
      final wrapped = ParallelWaitError(
        (null, null),
        (const OsrsApiHttpException(503), null),
      );
      final info = describeFetchError(wrapped);
      expect(info.kind, FetchErrorKind.server);
      expect(info.title, 'Server error (HTTP 503)');
    });

    test('unwraps AsyncError slots from a real record wait', () {
      // Record `.wait` cannot store raw errors in the record, so each failing
      // slot holds an AsyncError wrapping the original error.
      final wrapped = ParallelWaitError(
        (null, null),
        (
          AsyncError(const OsrsApiHttpException(500), StackTrace.empty),
          null,
        ),
      );
      final info = describeFetchError(wrapped);
      expect(info.kind, FetchErrorKind.server);
      expect(info.title, 'Server error (HTTP 500)');
    });

    test('unwrapped server error keeps an honest single-line message', () {
      final info = describeFetchError(const OsrsApiHttpException(500));
      expect(
        info.fullText,
        'Server error (HTTP 500). The wiki is having trouble. Try again later.',
      );
    });
  });
}