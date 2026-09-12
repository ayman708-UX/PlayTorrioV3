import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/stream/stream_model.dart';
import '../player/player_settings.dart';

/// Production-grade HTTP/HLS/MP4 Stream Health & Liveness Checker for PlayTorrioHTTP.
///
/// Validates stream URLs using lightweight range requests, respecting exact headers,
/// referrers, origins, and user-agents, and rejecting dead status codes or broken payloads.
class StreamHealthChecker {
  static const int _minBytes = 8 * 1024;
  static const int _maxBytes = 64 * 1024;
  static const Duration _timeout = Duration(seconds: 5);

  /// Tests if a [StreamSource] is alive and delivers a valid video/audio stream.
  ///
  /// Torrent streams (`infoHash != null`) are always considered alive by this checker.
  static Future<bool> isAlive(StreamSource source) async {
    // Torrents are managed by TorrServer / DHT
    if (source.infoHash != null && source.infoHash!.isNotEmpty) {
      return true;
    }

    final rawUrl = source.url ?? source.externalUrl;
    if (rawUrl == null || rawUrl.isEmpty || !rawUrl.startsWith('http')) {
      return false;
    }

    // Resolve complete headers (including Referer, Origin, User-Agent)
    final effectiveHeaders = PlayerSettings.resolveStreamHeaders(rawUrl, source.headers);

    return _probeUrl(rawUrl, effectiveHeaders);
  }

  /// Probes the stream URL using a GET Range request.
  static Future<bool> _probeUrl(String url, Map<String, String> headers, [int redirectCount = 0]) async {
    if (redirectCount > 5) return false;

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers['User-Agent'] = headers['User-Agent'] ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
        ..headers['Accept'] = '*/*'
        ..headers['Connection'] = 'keep-alive'
        ..headers['Range'] = 'bytes=0-${_maxBytes - 1}';

      // Attach all scraper headers (Referer, Origin, Cookie, Authorization, etc.)
      headers.forEach((k, v) {
        if (v.isNotEmpty && k.toLowerCase() != 'range' && k.toLowerCase() != 'content-length') {
          req.headers[k] = v;
        }
      });

      final resp = await client.send(req).timeout(_timeout);
      final code = resp.statusCode;

      // Handle 3xx Redirects manually to preserve Origin and Referer
      if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
        final location = resp.headers['location'];
        if (location != null && location.isNotEmpty) {
          final redirectedUri = Uri.parse(url).resolve(location).toString();
          final redirectHeaders = PlayerSettings.resolveStreamHeaders(redirectedUri, headers);
          client.close();
          return await _probeUrl(redirectedUri, redirectHeaders, redirectCount + 1);
        }
        return false;
      }

      // Check valid HTTP response codes
      if (code != 200 && code != 206) {
        return false;
      }

      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      final cl = int.tryParse(resp.headers['content-length'] ?? '') ?? -1;

      // Check for dead error pages (HTML/JSON/XML)
      final isM3U8 = ct.contains('mpegurl') || url.toLowerCase().contains('.m3u8');
      if (!isM3U8 && _isDeadContentType(ct)) {
        return false;
      }

      // Read initial payload bytes
      final buf = <int>[];
      try {
        await for (final chunk in resp.stream.timeout(_timeout)) {
          buf.addAll(chunk);
          if (buf.length >= _maxBytes) break;
          if (buf.length >= _minBytes) break;
        }
      } catch (_) {}

      // M3U8 validation
      if (isM3U8 || ct.contains('mpegurl')) {
        final headStr = utf8.decode(
          buf.sublist(0, buf.length < 1024 ? buf.length : 1024),
          allowMalformed: true,
        );
        return headStr.contains('#EXTM3U') || headStr.contains('#EXTINF') || headStr.contains('#EXT-X-STREAM-INF');
      }

      if (buf.isEmpty) return false;
      if (cl >= 1 && cl <= 1000) return false; // Tiny empty stub files

      // Binary video / stream container signature checks
      if (_hasVideoSignature(buf)) return true;

      // If we received >= _minBytes of binary content without dead content type, it's alive
      if (buf.length >= _minBytes && !_isDeadContentType(ct)) {
        return true;
      }

      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static bool _isDeadContentType(String ct) =>
      ct.contains('text/html') ||
      ct.contains('application/json') ||
      ct.contains('text/xml') ||
      ct.contains('text/plain') ||
      ct.contains('application/xml');

  static bool _hasVideoSignature(List<int> buf) {
    if (buf.length < 4) return false;

    // MPEG-TS sync byte (0x47)
    if (buf[0] == 0x47) {
      var validTs = true;
      var checkedPackets = 0;
      var i = 0;
      while (i < buf.length - 188 && checkedPackets < 6) {
        if (buf[i] != 0x47) {
          validTs = false;
          break;
        }
        checkedPackets++;
        i += 188;
      }
      if (validTs && checkedPackets >= 2) return true;
    }

    // MP4 / MOV / M4V box identifiers (ftyp, moov, mdat, wide, skip, free)
    if (buf.length >= 8) {
      final s = String.fromCharCodes(buf.sublist(4, 8));
      if (s == 'ftyp' || s == 'moov' || s == 'mdat' || s == 'wide' || s == 'skip' || s == 'free') {
        return true;
      }
    }

    // M3U8 string headers
    if (buf.length >= 7) {
      final s = String.fromCharCodes(buf.sublist(0, 7));
      if (s == '#EXTM3U') return true;
    }
    if (buf.length >= 4) {
      final s = String.fromCharCodes(buf.sublist(0, 4));
      if (s == '#EXT') return true;
    }

    // Matroska / WebM (0x1A 0x45 0xDF 0xA3)
    if (buf.length >= 4 && buf[0] == 0x1A && buf[1] == 0x45 && buf[2] == 0xDF && buf[3] == 0xA3) {
      return true;
    }

    // Ogg stream (0x4F 0x67 0x67 0x53 -> 'OggS')
    if (buf.length >= 4 && buf[0] == 0x4F && buf[1] == 0x67 && buf[2] == 0x67 && buf[3] == 0x53) {
      return true;
    }

    // FLV container ('FLV\x01')
    if (buf.length >= 4 && buf[0] == 0x46 && buf[1] == 0x4C && buf[2] == 0x56 && buf[3] == 0x01) {
      return true;
    }

    // H.264 / H.265 NAL unit start codes (0x000001 or 0x00000001)
    if (buf.length >= 4 && buf[0] == 0x00 && buf[1] == 0x00 && buf[2] == 0x00 && buf[3] == 0x01) {
      return true;
    }
    if (buf.length >= 3 && buf[0] == 0x00 && buf[1] == 0x00 && buf[2] == 0x01) {
      return true;
    }

    // AAC ADTS frame sync (0xFFF)
    if (buf.length >= 2 && buf[0] == 0xFF && (buf[1] & 0xF0) == 0xF0) {
      return true;
    }

    // MP3 frame sync (0xFFE or 0xFFF)
    if (buf.length >= 2 && buf[0] == 0xFF && (buf[1] & 0xE0) == 0xE0) {
      return true;
    }

    return false;
  }
}
