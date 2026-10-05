import 'package:http/http.dart' as http;

import '../../models/stream/stream_model.dart';
import '../player/player_settings.dart';

/// Resolves the real video bitrate of direct HTTP streams by reading the
/// BANDWIDTH attribute off HLS master playlists. Results (including misses)
/// are cached per URL so panels don't re-fetch the same manifests.
class StreamBitrateResolver {
  StreamBitrateResolver._();

  static const Duration _timeout = Duration(seconds: 5);
  static const int _maxManifestBytes = 256 * 1024;
  static const int _maxCacheEntries = 512;

  static final Map<String, int?> _cache = {};

  /// Returns the peak variant bitrate in kbps for [source], or null when the
  /// stream is not an HLS master playlist or can't be reached.
  static Future<int?> resolveKbps(StreamSource source) async {
    final rawUrl = source.url ?? source.externalUrl;
    if (rawUrl == null || rawUrl.isEmpty || !rawUrl.startsWith('http')) {
      return null;
    }
    if (_cache.containsKey(rawUrl)) return _cache[rawUrl];

    final kbps = await _fetchManifestKbps(rawUrl, source.headers);
    _cache[rawUrl] = kbps;
    if (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return kbps;
  }

  static Future<int?> _fetchManifestKbps(
    String url,
    Map<String, String>? headers, [
    int redirectCount = 0,
  ]) async {
    if (redirectCount > 5) return null;

    final client = http.Client();
    try {
      final effectiveHeaders = PlayerSettings.resolveStreamHeaders(url, headers);
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers['User-Agent'] = effectiveHeaders['User-Agent'] ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
        ..headers['Accept'] = '*/*';

      effectiveHeaders.forEach((k, v) {
        if (v.isNotEmpty && k.toLowerCase() != 'range' && k.toLowerCase() != 'content-length') {
          req.headers[k] = v;
        }
      });

      final resp = await client.send(req).timeout(_timeout);

      // Follow redirects manually so Referer/Origin survive the hop
      if (resp.statusCode >= 300 && resp.statusCode < 400) {
        final location = resp.headers['location'];
        if (location != null && location.isNotEmpty) {
          final redirectedUri = Uri.parse(url).resolve(location).toString();
          client.close();
          return await _fetchManifestKbps(redirectedUri, headers, redirectCount + 1);
        }
        return null;
      }
      if (resp.statusCode != 200) return null;

      // Only pull the body for playlist-looking responses — never slurp
      // multi-GB mp4/mkv files just to read a bitrate.
      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      final isPlaylist = ct.contains('mpegurl') || url.toLowerCase().contains('.m3u8');
      if (!isPlaylist) return null;

      final buf = <int>[];
      await for (final chunk in resp.stream.timeout(_timeout)) {
        buf.addAll(chunk);
        if (buf.length >= _maxManifestBytes) break;
      }
      if (buf.isEmpty) return null;

      return parseManifestKbps(String.fromCharCodes(buf));
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Extracts the highest BANDWIDTH variant from an HLS master playlist.
  static int? parseManifestKbps(String manifest) {
    if (!manifest.contains('#EXT-X-STREAM-INF')) return null;
    var peak = 0;
    for (final match in RegExp(r'BANDWIDTH=(\d+)').allMatches(manifest)) {
      final bw = int.tryParse(match.group(1) ?? '');
      if (bw != null && bw > peak) peak = bw;
    }
    if (peak <= 0) return null;
    return (peak / 1000).round();
  }
}
