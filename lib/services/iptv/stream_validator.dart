import 'dart:async';

import 'package:http/http.dart' as http;

import 'stream_validation_store.dart';

/// Port of `StreamValidator.kt` — probes stream URLs to decide if they're alive.
class StreamValidator {
  static const Duration ttl = Duration(minutes: 30);
  static const Duration _timeout = Duration(seconds: 3);
  static const int _maxConcurrency = 24;
  static const int _sampleSize = 1024;
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36';

  static const _htmlPagePrefixes = [
    '<!doctype html',
    '<!doctype',
    '<html',
    '<!',
    '<?xml',
  ];
  static const _deadPageTokens = [
    '404',
    '403',
    '401',
    'not found',
    'forbidden',
    'unauthorized',
    'invalid user',
    'invalid username',
    'account disabled',
    'account suspended',
    'credits expired',
    'expired',
    'offline',
    'service unavailable',
    'bad gateway',
    'internal server error',
    'error',
    'failed to open stream',
  ];

  static Future<bool> checkUrl(String url) async {
    var sample = await _probeSample(url, 'bytes=0-${_sampleSize - 1}');
    if (sample == null || sample.isEmpty) {
      sample = await _probeSample(url, null);
    }
    if (sample == null || sample.isEmpty) return false;
    return looksAlive(sample);
  }

  /// Checks a batch with limited concurrency, calling [onResult] per URL.
  static Future<void> checkBatch(
    List<String> urls, {
    void Function(String url, bool alive)? onResult,
    void Function(int checked, int total)? onProgress,
  }) async {
    if (urls.isEmpty) return;
    final semaphore = _Semaphore(_maxConcurrency);
    var completed = 0;

    await Future.wait(urls.map((url) async {
      await semaphore.acquire();
      try {
        final alive = await checkUrl(url);
        onResult?.call(url, alive);
      } finally {
        semaphore.release();
        completed++;
        onProgress?.call(completed, urls.length);
      }
    }));
  }

  /// Validates URLs, updating the [StreamValidationStore], returning dead URLs.
  static Future<Set<String>> validateUrls(
    List<String> urls, {
    void Function(int done, int total)? onProgress,
  }) async {
    final dead = <String>{};
    await checkBatch(
      urls,
      onResult: (url, alive) {
        StreamValidationStore.instance.updateStatus(url, alive);
        if (!alive) dead.add(url);
      },
      onProgress: onProgress,
    );
    return dead;
  }

  static Future<String?> _probeSample(String url, String? range) async {
    final headers = <String, String>{'User-Agent': _userAgent};
    if (range != null) headers['Range'] = range;
    try {
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = response.bodyBytes;
        return utf8Decode(bytes, _sampleSize);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool looksAlive(String sample) {
    final trimmed = sample.replaceFirst(RegExp(r'^\uFEFF+'), '');
    final trimmedStripped = trimmed.trimLeft();
    if (trimmedStripped.isEmpty) return false;
    final lower = trimmedStripped.toLowerCase();
    if (_htmlPagePrefixes.any(lower.startsWith)) return false;
    if (lower.length < 256 &&
        _deadPageTokens.any((t) => lower.contains(t))) {
      return false;
    }
    return true;
  }

  static String utf8Decode(List<int> bytes, int maxBytes) {
    final limited = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
    try {
      return String.fromCharCodes(limited);
    } catch (_) {
      return '';
    }
  }
}

/// Simple async semaphore (Dart has no built-in).
class _Semaphore {
  final int max;
  int _used = 0;
  final List<void Function()> _queue = [];

  _Semaphore(this.max);

  Future<void> acquire() async {
    if (_used < max) {
      _used++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(() => completer.complete());
    await completer.future;
  }

  void release() {
    _used--;
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      _used++;
      next();
    }
  }
}
