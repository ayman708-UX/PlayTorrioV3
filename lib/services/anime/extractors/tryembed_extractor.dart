import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class TryEmbedTrack {
  final String file;
  final String label;
  final String lang;
  final bool isDefault;

  TryEmbedTrack({
    required this.file,
    required this.label,
    required this.lang,
    this.isDefault = false,
  });

  factory TryEmbedTrack.fromJson(Map<String, dynamic> json) {
    return TryEmbedTrack(
      file: json['url']?.toString() ?? json['file']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Subtitles',
      lang: json['lang']?.toString() ?? 'en',
      isDefault: json['default'] == true,
    );
  }
}

class TryEmbedResult {
  final String url;
  final String serverName; // e.g. "Moko", "Beta", "Timi", "Light", "Zen"
  final Map<String, String> headers;
  final List<TryEmbedTrack> tracks;
  final Map<String, dynamic>? intro;
  final Map<String, dynamic>? outro;
  final String category; // 'sub' or 'dub'

  TryEmbedResult({
    required this.url,
    required this.serverName,
    required this.headers,
    this.tracks = const [],
    this.intro,
    this.outro,
    required this.category,
  });
}

class TryEmbedExtractor {
  static final TryEmbedExtractor instance = TryEmbedExtractor._internal();
  TryEmbedExtractor._internal();

  static const String baseUrl = 'https://tryembed.us.cc';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  /// Scrapes the video stream and subtitles from TryEmbed for an Anilist Anime ID and Episode.
  Future<List<TryEmbedResult>> extractAll({
    required int anilistId,
    required int episodeNumber,
    required String category, // 'sub' or 'dub'
  }) async {
    final results = <TryEmbedResult>[];
    try {
      final cat = category.toLowerCase() == 'dub' ? 'dub' : 'sub';
      final embedUrl = '$baseUrl/embed/anime/$anilistId/$episodeNumber/$cat?autoSkip=true';

      final embedReq = await _httpClient.getUrl(Uri.parse(embedUrl));
      embedReq.headers.set('User-Agent', _userAgent);
      embedReq.headers.set(
        'Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      );
      embedReq.headers.set('Accept-Language', 'en-US,en;q=0.9');
      embedReq.headers.set('Referer', 'https://google.com/');

      final embedRes = await embedReq.close().timeout(const Duration(seconds: 10));
      if (embedRes.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[TryEmbed] Embed request failed: ${embedRes.statusCode}');
        }
        return results;
      }

      final cookieMap = <String, String>{};
      for (final cookie in embedRes.cookies) {
        cookieMap[cookie.name] = cookie.value;
      }

      final body = await embedRes.transform(utf8.decoder).join();
      final nonceMatch =
          RegExp(r'''EMBED_NONCE\s*=\s*["']([^"']+)["']''').firstMatch(body);
      final nonce = nonceMatch?.group(1) ?? '';

      String buildCookieHeader() =>
          cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');

      final apiUrl =
          '$baseUrl/api/stream_data?id=$anilistId&episode=$episodeNumber&audio=$cat&nonce=${Uri.encodeComponent(nonce)}';

      final apiReq = await _httpClient.getUrl(Uri.parse(apiUrl));
      apiReq.headers.set('User-Agent', _userAgent);
      apiReq.headers.set('Accept', '*/*');
      apiReq.headers.set('Referer', embedUrl);
      apiReq.headers.set('Origin', baseUrl);
      apiReq.headers.set('Sec-Fetch-Dest', 'empty');
      apiReq.headers.set('Sec-Fetch-Mode', 'cors');
      apiReq.headers.set('Sec-Fetch-Site', 'same-origin');
      apiReq.headers.set('X-Embed-Nonce', nonce);
      if (cookieMap.isNotEmpty) {
        apiReq.headers.set('Cookie', buildCookieHeader());
      }

      final apiRes = await apiReq.close().timeout(const Duration(seconds: 10));
      if (apiRes.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[TryEmbed] Stream data request failed: ${apiRes.statusCode}');
        }
        return results;
      }

      for (final cookie in apiRes.cookies) {
        cookieMap[cookie.name] = cookie.value;
      }

      final apiBody = await apiRes.transform(utf8.decoder).join();
      final data = jsonDecode(apiBody) as Map<String, dynamic>;
      final providers = data['providers'] as List? ?? [];

      // Parse global captions/subtitles
      final globalTracks = <TryEmbedTrack>[];
      if (data['captions'] is List) {
        for (final item in data['captions']) {
          if (item is Map<String, dynamic>) {
            final trackUrl = item['url']?.toString() ?? item['file']?.toString() ?? '';
            if (trackUrl.isNotEmpty) {
              globalTracks.add(TryEmbedTrack.fromJson(item));
            }
          }
        }
      }

      // Parse intro/outro
      Map<String, dynamic>? intro;
      if (data['intro'] is Map<String, dynamic>) {
        final start = data['intro']['start'];
        final end = data['intro']['end'];
        if (start != null && end != null && (end as num) > (start as num)) {
          intro = {'start': start, 'end': end};
        }
      }

      Map<String, dynamic>? outro;
      if (data['outro'] is Map<String, dynamic>) {
        final start = data['outro']['start'];
        final end = data['outro']['end'];
        if (start != null && end != null && (end as num) > (start as num)) {
          outro = {'start': start, 'end': end};
        }
      }

      final cookieString = buildCookieHeader();

      for (final provider in providers) {
        if (provider is! Map<String, dynamic>) continue;
        final serverName = provider['name']?.toString() ?? provider['id']?.toString() ?? 'Server';
        final qualities = provider['qualities'] as List? ?? [];
        if (qualities.isEmpty) continue;

        String? streamUrl;
        for (final q in qualities) {
          if (q is! Map<String, dynamic>) continue;
          final directUrl = q['directUrl']?.toString();
          final token = q['token']?.toString();
          final fallbackToken = q['fallbackToken']?.toString();

          if (directUrl != null && directUrl.isNotEmpty) {
            streamUrl = directUrl;
            break;
          } else if (token != null && token.isNotEmpty) {
            streamUrl = '$baseUrl/s/$token.m3u8';
            break;
          } else if (fallbackToken != null && fallbackToken.isNotEmpty) {
            streamUrl = '$baseUrl/s/$fallbackToken.m3u8';
            break;
          }
        }

        if (streamUrl != null && streamUrl.isNotEmpty) {
          final tracks = List<TryEmbedTrack>.from(globalTracks);
          if (provider['captions'] is List) {
            for (final item in provider['captions']) {
              if (item is Map<String, dynamic>) {
                final trackUrl = item['url']?.toString() ?? item['file']?.toString() ?? '';
                if (trackUrl.isNotEmpty && !tracks.any((t) => t.file == trackUrl)) {
                  tracks.add(TryEmbedTrack.fromJson(item));
                }
              }
            }
          }

          results.add(
            TryEmbedResult(
              url: streamUrl,
              serverName: serverName,
              headers: {
                'Referer': embedUrl,
                'Origin': baseUrl,
                'User-Agent': _userAgent,
                if (cookieString.isNotEmpty) 'Cookie': cookieString,
              },
              tracks: tracks,
              intro: intro,
              outro: outro,
              category: cat,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TryEmbed] Extraction error: $e');
      }
    }
    return results;
  }
}
