import 'dart:async';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../services/osrs_api.dart';

/// Category of a data-fetch failure, so screens can show an honest message
/// instead of blaming the connection for every failure.
enum FetchErrorKind { network, server, format, unknown }

/// Human-readable description of a fetch failure.
class FetchErrorInfo {
  const FetchErrorInfo({
    required this.kind,
    required this.title,
    required this.hint,
  });

  final FetchErrorKind kind;
  final String title;
  final String hint;

  /// Single sentence for screens that show one message, e.g.
  /// "Server error (HTTP 500). The wiki is having trouble. Try again later."
  String get fullText => '$title. $hint';
}

/// Classifies [error] — which may be a [ParallelWaitError] from a parallel
/// fetch such as BootstrapScreen's — into a [FetchErrorInfo].
///
/// - Connectivity ([SocketException], http [http.ClientException]) -> network.
/// - Non-2xx HTTP status ([OsrsApiHttpException]) -> server.
/// - Response shape mismatch ([FormatException]) -> format.
/// - Anything else -> unknown.
FetchErrorInfo describeFetchError(Object error) {
  final actual = _unwrapParallelWait(error);

  if (actual is SocketException || actual is http.ClientException) {
    return const FetchErrorInfo(
      kind: FetchErrorKind.network,
      title: 'No internet connection',
      hint: 'Check your connection and try again.',
    );
  }

  if (actual is OsrsApiHttpException) {
    return FetchErrorInfo(
      kind: FetchErrorKind.server,
      title: 'Server error (HTTP ${actual.statusCode})',
      hint: 'The wiki is having trouble. Try again later.',
    );
  }

  if (actual is FormatException) {
    return const FetchErrorInfo(
      kind: FetchErrorKind.format,
      title: 'Unexpected data from the server',
      hint: 'The app may need an update to match the API.',
    );
  }

  return const FetchErrorInfo(
    kind: FetchErrorKind.unknown,
    title: 'Something went wrong',
    hint: 'Try again.',
  );
}

/// `(f1, f2).wait` throws a [ParallelWaitError] wrapping the per-future
/// errors; unwrap it to the first failing error so classification works.
///
/// Record `.wait` stores each failing future's result as an [AsyncError]
/// (records cannot hold raw errors), so unwrap that too.
Object _unwrapParallelWait(Object error) {
  if (error is! ParallelWaitError) {
    return error;
  }
  final errors = error.errors as dynamic;
  try {
    final first = errors.$1 as Object?;
    final second = errors.$2 as Object?;
    final actual = first ?? second ?? error;
    return actual is AsyncError ? actual.error : actual;
  } on NoSuchMethodError {
    return error;
  }
}