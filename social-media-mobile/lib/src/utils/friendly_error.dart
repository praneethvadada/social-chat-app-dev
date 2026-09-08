import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

/// A user-facing rendering of a failure.
///
/// Raw exceptions are for us, not for the person holding the phone. Dumping
/// `e.toString()` on screen shows them hostnames, ports and errno values they
/// can do nothing with - and quietly advertises our internal addresses to
/// anyone looking at the screen. Everything here is phrased as "what happened
/// and what you can do about it"; the original error still goes to the console.
class FriendlyError {
  final String title;
  final String message;
  final IconData icon;

  const FriendlyError(this.title, this.message, this.icon);

  /// Translate any thrown object into something worth showing.
  ///
  /// Unrecognised failures deliberately fall through to a generic message
  /// rather than leaking their text - if we haven't accounted for it, we
  /// can't promise it is safe or meaningful to display.
  factory FriendlyError.from(Object? error) {
    // Log the real thing so the detail is never actually lost.
    debugPrint('[FriendlyError] $error');

    if (error is SocketException || error is HttpException) {
      return const FriendlyError(
        'No connection',
        "We can't reach Revolution Chat right now. Check your internet connection "
            'and try again.',
        Icons.wifi_off_rounded,
      );
    }
    if (error is TimeoutException) {
      return const FriendlyError(
        'Taking too long',
        'The connection timed out. Please try again.',
        Icons.hourglass_empty_rounded,
      );
    }

    final text = error?.toString().toLowerCase() ?? '';

    // http/ClientException wraps the socket failure in a plain string, so the
    // type check above misses it - match on the text as a second pass.
    if (text.contains('socketexception') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('clientexception') ||
        text.contains('connection reset')) {
      return const FriendlyError(
        'No connection',
        "We can't reach Revolution Chat right now. Check your internet connection "
            'and try again.',
        Icons.wifi_off_rounded,
      );
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return const FriendlyError(
        'Taking too long',
        'The connection timed out. Please try again.',
        Icons.hourglass_empty_rounded,
      );
    }
    if (text.contains('unauthorized') || text.contains('401')) {
      return const FriendlyError(
        'Session expired',
        'Please log in again to continue.',
        Icons.lock_outline_rounded,
      );
    }
    if (text.contains('forbidden') || text.contains('403')) {
      return const FriendlyError(
        'Not available',
        "You don't have access to this.",
        Icons.block_rounded,
      );
    }
    if (text.contains('not found') || text.contains('404')) {
      return const FriendlyError(
        'Not found',
        "This isn't available anymore.",
        Icons.search_off_rounded,
      );
    }
    if (text.contains('internal server error') ||
        text.contains('500') ||
        text.contains('502') ||
        text.contains('503') ||
        text.contains('bad gateway') ||
        text.contains('service unavailable')) {
      return const FriendlyError(
        'Something went wrong',
        "We're having trouble on our end. Please try again in a moment.",
        Icons.cloud_off_rounded,
      );
    }

    return const FriendlyError(
      'Something went wrong',
      'Please try again in a moment.',
      Icons.error_outline_rounded,
    );
  }

  /// Just the sentence, for toasts and inline labels.
  static String messageOf(Object? error) => FriendlyError.from(error).message;
}
