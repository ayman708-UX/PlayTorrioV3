import 'dart:convert';

import 'package:http/http.dart' as http;

/// Shared HTTP helpers for the IPTV feature. Ports the `httpGetText*`
/// helpers from `AddonPlatform.kt`.
class IptvHttp {
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const String _vlcUa = 'VLC/3.0.20';

  /// GET a URL and return the body text. Throws on error / non-2xx.
  static Future<String> getText(
    String url, {
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final response = await http
        .get(
          Uri.parse(url),
          headers: {'User-Agent': _ua, ...headers},
        )
        .timeout(timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw Exception('HTTP ${response.statusCode} for $url');
  }

  /// GET with the VLC user agent (used by Xtream / ShortEPG endpoints).
  static Future<String> getTextVlc(
    String url, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return getText(url, headers: {'User-Agent': _vlcUa}, timeout: timeout);
  }

  /// GET a URL with a limited response size (for stream validation).
  static Future<String> getTextLimited(
    String url, {
    int limitBytes = 1024,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final response = await http
        .get(
          Uri.parse(url),
          headers: {'User-Agent': _ua, ...headers, 'Range': 'bytes=0-${limitBytes - 1}'},
        )
        .timeout(timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final bytes = response.bodyBytes;
      final limited = bytes.length > limitBytes
          ? bytes.sublist(0, limitBytes)
          : bytes;
      return utf8.decode(limited, allowMalformed: true);
    }
    throw Exception('HTTP ${response.statusCode} for $url');
  }

  /// Whether a URL "looks alive" from a quick probe.
  static Future<bool> looksAlive(
    String url, {
    int limitBytes = 1024,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      await getTextLimited(
        url,
        limitBytes: limitBytes,
        timeout: timeout,
        headers: {'User-Agent': _vlcUa},
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
