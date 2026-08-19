// Port of `PortalNutzScraper.kt` — hunts for working Xtream portal credentials
// across GitHub, Telegram, Reddit and other public lists, verifies them, and
// returns the best ones as [PortalNutzEntry]s.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'iptv_http.dart';
import 'xtream_client.dart';

class PortalNutzEntry {
  final String label;
  final String url;
  final String username;
  final String password;
  final int channelCount;
  final String domain;
  final String? expDate;
  final int? maxConnections;
  final int? activeConnections;
  final String? status;
  final bool isTrial;

  const PortalNutzEntry({
    required this.label,
    required this.url,
    required this.username,
    required this.password,
    this.channelCount = 0,
    required this.domain,
    this.expDate,
    this.maxConnections,
    this.activeConnections,
    this.status,
    this.isTrial = false,
  });
}

sealed class PortalNutzEvent {
  const PortalNutzEvent();
}

class PortalNutzProgress extends PortalNutzEvent {
  final String message;
  const PortalNutzProgress(this.message);
}

class PortalNutzResult extends PortalNutzEvent {
  final List<PortalNutzEntry> portals;
  const PortalNutzResult(this.portals);
}

class PortalNutzError extends PortalNutzEvent {
  final String message;
  const PortalNutzError(this.message);
}

class PortalNutzScraper {
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 11; NuvioTV) AppleWebKit/537.36';

  static const int _fetchTimeoutMs = 4000;
  static const int _maxParallelFetches = 24;
  static const int _maxCountParallel = 48;
  static const int _maxVerifyBytes = 2 * 1024 * 1024;
  static const int _maxCountBytes = 8 * 1024 * 1024;
  static const int _maxRawFileBytes = 8 * 1024 * 1024;
  static const int _candidatePoolSize = 80;
  static const int _cacheTtlMs = 60 * 60 * 1000;
  static const int _cacheMax = 100;

  static bool _cancelled = false;

  static void cancel() {
    _cancelled = true;
  }

  // ── Cache ───────────────────────────────────────────────────────────────

  static final Map<String, _CachedPortal> _portalCache = {};

  static void _cachePut(String key, _CachedPortal portal) {
    _portalCache[key] = portal;
    if (_portalCache.length > _cacheMax) {
      _portalCache.remove(_portalCache.keys.first);
    }
  }

  static void _cacheSweep() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _portalCache.removeWhere((_, p) => now - p.verifiedAt > _cacheTtlMs);
  }

  static List<_CachedPortal> _cacheSnapshot() {
    _cacheSweep();
    return _portalCache.values.toList();
  }

  // ── Sources ─────────────────────────────────────────────────────────────

  static const List<String> _worldRepoFallback = [
    '25.txt', '71.txt', 'ABN.txt', 'DOV.txt',
    '%5BK_B_W_%20Client%5D.txt', 'br.txt',
    'channels_fulltime%20(OR).txt', 'channels_fulltime.txt',
    'kgen%20(4).txt', 'kgen.txt', 'rg.txt', 'x.txt',
    '%7BAllTelegram%7D2.txt',
  ];

  static const List<String> _telegramChannels = [
    'xtreamcodes', 'xtream_iptv_code', 'satglobaltv', 'IPTVXTREAMPRO',
    'm3u86', 'iptvgratuitfr0', 'extremeportals',
  ];

  static const List<String> _redditSubreddits = ['IPTV_ZONENEW', 'xml2'];

  static const List<String> _pasteDomains = [
    'paste.sh', 'pastebin.com', 'justpaste.it', 'controlc.com',
    'pastes.dev', 'text.is', 'rentry.co',
  ];

  static final RegExp _rawPaste = RegExp(
    'https?://(?:${_pasteDomains.join('|')})/[a-zA-Z0-9#_=\\-]+',
    caseSensitive: false,
  );

  static final RegExp _b64Re = RegExp(r'aHR0c[a-zA-Z0-9+/=]{10,}');

  static const List<String> _redditRssHosts = [
    'old.reddit.com', 'www.reddit.com',
  ];

  static const Set<String> _adultTerms = {
    'xxx', 'adult', 'porn', 'sex', 'erotic', '18+', 'onlyfans', 'cam', 'nude',
    'playboy', 'penthouse', 'hustler', 'brazzers', 'bangbros',
    'pornhub', 'xvideos', 'xhamster', 'xnxx', 'redtube',
    'milf', 'ebony', 'lesbian', 'gay', 'shemale', 'tranny',
    'sexo', 'porno', 'adultos', 'fetish', 'bdsm', 'hardcore',
  };

  static const Set<String> _sportsKeywords = {
    'espn', 'nfl', 'nba', 'mlb', 'nhl', 'ufc', 'dazn', 'bein sport',
    'premier league', 'laliga', 'serie a', 'bundesliga', 'ligue 1',
    ' champions ', 'europa league', 'world cup', 'fifa', 'ncaa',
    'nascar', 'formula 1', 'f1', 'motogp', 'wwe', 'aew',
    'tennis', 'us open', 'wimbledon', 'australian open',
    'nfl network', 'nba tv', 'mlb network', 'nhl network',
    'golf', 'pga', 'masters', 'cricket', 'ipl',
    'boxing', 'mma', 'one championship', 'wrc', 'world rally',
    'olympics', 'super bowl', 'stanley cup', 'world series',
    'ncaa football', 'ncaa basketball', 'march madness',
    'sports', 'sport', 'deporte', 'deportes',
  };

  static String cleanPortalUrl(String raw) {
    var clean = raw.replaceAll(RegExp(r'\s+'), '');
    final qIdx = clean.indexOf('?');
    if (qIdx >= 0) clean = clean.substring(0, qIdx);
    clean = clean.replaceAll(
      RegExp(
        r'/+?(?:get|live|portal|c|index|playlist|player_api|xmltv|index\.php|portal\.php)\.php$',
        caseSensitive: false,
      ),
      '',
    );
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (!clean.startsWith('http')) clean = 'http://$clean';
    return clean;
  }

  static String extractDomain(String url) {
    var cleaned = url.replaceFirst('https://', '').replaceFirst('http://', '');
    final slashIdx = cleaned.indexOf('/');
    return slashIdx >= 0 ? cleaned.substring(0, slashIdx) : cleaned;
  }

  static String domainKey(String url) {
    return url
        .replaceFirst('https://', '')
        .replaceFirst('http://', '')
        .split('/')
        .first
        .split(':')
        .first
        .toLowerCase();
  }

  static List<_Portal> extractPortals(String text, String source) {
    if (text.length < 15) return const [];
    var cleaned = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'<(?:p|br|div|li|h\d)[^>]*>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');

    final seen = <String>{};
    final portals = <_Portal>[];

    final urlParamRegex = RegExp(
      r'''(https?://[^?\s"'<]+)\?(?:[^\s"'<]*?&)?(?:username|user)=([^&\s"'<]+)\s*&(?:password|pass)=([^&\s"'<]+)''',
      caseSensitive: false,
    );
    for (final m in urlParamRegex.allMatches(cleaned)) {
      final url = cleanPortalUrl(m.group(1)!);
      final user = m.group(2)!.trim();
      final pass = m.group(3)!.trim();
      if (url.isNotEmpty &&
          user.length >= 3 &&
          pass.length >= 3 &&
          !user.contains('http') &&
          !pass.contains('http')) {
        final key = '$url|$user|$pass';
        if (seen.add(key)) {
          portals.add(_Portal(url, user, pass, source));
        }
      }
    }

    final labelRegex = RegExp(
      r'''(?:Portal|Host(?:\s*URL)?|Panel|Real|URL|🔗|Url)\W*?(https?://[^<\s"']+)[\s\S]{1,500}?(?:Username|User|Usu[áa]rio|Usuario|👤|Identifiant)\W*?([^\s|<"'\n]+)[\s\S]{1,200}?(?:Password|Pass|Senha|Contrase[ñn]a|🔑|Mot\s*de\s*[Pp]asse)\W*?([^\s|<"'\n]+)''',
      caseSensitive: false,
    );
    for (final m in labelRegex.allMatches(cleaned)) {
      final url = cleanPortalUrl(m.group(1)!);
      final user = m.group(2)!.trim();
      final pass = m.group(3)!.trim();
      if (url.isNotEmpty &&
          user.length >= 3 &&
          pass.length >= 3 &&
          !user.contains('http') &&
          !pass.contains('http')) {
        final key = '$url|$user|$pass';
        if (seen.add(key)) {
          portals.add(_Portal(url, user, pass, source));
        }
      }
    }

    return portals;
  }

  static bool isAdultText(String text) {
    final lower = text.toLowerCase();
    return _adultTerms.any(lower.contains);
  }

  static bool hasNonLatinScript(String text) {
    return RegExp(r'[\u0400-\u04FF\u0500-\u052F]').hasMatch(text) ||
        RegExp(r'[\u0600-\u06FF]').hasMatch(text) ||
        RegExp(r'[\u4E00-\u9FFF]').hasMatch(text) ||
        RegExp(r'[\u3040-\u30FF]').hasMatch(text);
  }

  // ── HTTP helpers ────────────────────────────────────────────────────────

  static Future<String?> _fetchText(String url) async {
    if (_cancelled) return null;
    try {
      return await IptvHttp.getText(
        url,
        timeout: const Duration(milliseconds: _fetchTimeoutMs),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _fetchTextWithHeaders(
    String url,
    Map<String, String> headers,
  ) async {
    if (_cancelled) return null;
    try {
      return await IptvHttp.getText(
        url,
        headers: headers,
        timeout: const Duration(milliseconds: _fetchTimeoutMs),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _fetchTextLimited(
    String url,
    Map<String, String> headers,
    int maxBytes,
  ) async {
    if (_cancelled) return null;
    try {
      return await IptvHttp.getTextLimited(
        url,
        headers: headers,
        limitBytes: math.max(maxBytes, 1024),
        timeout: const Duration(milliseconds: _fetchTimeoutMs),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _decodeBase64(String raw) {
    final u = raw.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
    final padded = u + ('=' * ((4 - u.length % 4) % 4));
    try {
      return utf8.decode(base64Decode(padded), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _fetchPasteContent(String url) async {
    try {
      if (url.contains('pastebin.com/') && !url.contains('/raw/')) {
        final id = url.substringAfter('pastebin.com/').substringBefore('?')
            .substringBefore('#');
        return await _fetchTextWithHeaders(
          'https://pastebin.com/raw/$id',
          {'User-Agent': _ua},
        );
      }
      if (url.contains('pastes.dev/')) {
        final id = url.substringAfter('pastes.dev/').substringBefore('?')
            .substringBefore('#');
        return await _fetchTextWithHeaders(
          'https://api.pastes.dev/$id',
          {'User-Agent': _ua},
        );
      }
      if (url.contains('rentry.co/') && !url.contains('/raw')) {
        final id = url.substringAfter('rentry.co/').substringBefore('?')
            .substringBefore('#');
        return await _fetchTextWithHeaders(
          'https://rentry.co/$id/raw',
          {'User-Agent': _ua},
        );
      }
      return await _fetchText(url);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _collectPortalsFromText(
    String text,
    String source,
    Set<String> seen,
    List<_Portal> portals,
  ) async {
    for (final p in extractPortals(text, source)) {
      final key = '${p.url}|${p.username}|${p.password}';
      if (seen.add(key)) portals.add(p);
    }
    for (final m in _b64Re.allMatches(text)) {
      final decoded = _decodeBase64(m.group(0)!);
      if (decoded == null) continue;
      for (final p in extractPortals(decoded, '$source:b64')) {
        final key = '${p.url}|${p.username}|${p.password}';
        if (seen.add(key)) portals.add(p);
      }
    }
    for (final m in _rawPaste.allMatches(text)) {
      final content = await _fetchPasteContent(m.group(0)!);
      if (content == null) continue;
      for (final p in extractPortals(content, '$source:paste')) {
        final key = '${p.url}|${p.username}|${p.password}';
        if (seen.add(key)) portals.add(p);
      }
    }
  }

  // ── GitHub ──────────────────────────────────────────────────────────────

  static Future<List<_Portal>> _fetchGitHubPortals(
    void Function(PortalNutzEvent) onEvent,
  ) async {
    onEvent(const PortalNutzProgress('Shaking the tree for ripe nutz...'));
    final seen = <String>{};
    final portals = <_Portal>[];

    final repos = [
      ('akeotaseo', 'world_repo', 'Updater_Matrix/XML2', false, _worldRepoFallback),
      ('Armiiin', 'world_repo', 'Updater_Matrix/XML2', false, _worldRepoFallback),
      ('rochana-sadila', 'Xtream-Codes-Library', '', true, const <String>[]),
    ];

    for (final repo in repos) {
      final (owner, name, path, isJson, fallbackFiles) = repo;
      var files = <(String, String, int)>[];

      final apiUrl =
          'https://api.github.com/repos/$owner/$name/contents/$path?ref=main';
      final jsonText = await _fetchTextLimited(
        apiUrl,
        {
          'User-Agent': _ua,
          'Accept': 'application/vnd.github.v3+json',
        },
        2 * 1024 * 1024,
      );
      if (jsonText != null) {
        try {
          final arr = jsonDecode(jsonText) as List<dynamic>;
          for (final item in arr) {
            final obj = item as Map<String, dynamic>;
            if (obj['type']?.toString() == 'file') {
              final fileName = obj['name']?.toString() ?? '';
              final downloadUrl = obj['download_url']?.toString() ?? '';
              final ext = isJson ? '.json' : '.txt';
              if (fileName.endsWith(ext) && downloadUrl.isNotEmpty) {
                final size = int.tryParse(obj['size']?.toString() ?? '') ??
                    (1 << 63) - 1;
                files.add((fileName, downloadUrl, size));
              }
            }
          }
          files.sort((a, b) => a.$3.compareTo(b.$3));
        } catch (_) {}
      }

      if (files.isEmpty) {
        final base = 'https://raw.githubusercontent.com/$owner/$name/main/$path';
        if (isJson) {
          files = [('xtreams.json', '$base/xtreams.json', (1 << 63) - 1)];
        } else {
          files = fallbackFiles
              .map((f) => (f, '$base/${f.trimLeft()}', (1 << 63) - 1))
              .toList();
        }
      }

      for (final chunk in _chunk(files.take(20).toList(), _maxParallelFetches)) {
        final results = await Future.wait(chunk.map((f) async {
          final (fileName, dlUrl, _) = f;
          final text = await _fetchTextLimited(
            dlUrl,
            {'User-Agent': _ua},
            _maxRawFileBytes,
          );
          if (text == null) return <_Portal>[];
          final result = <_Portal>[];
          if (isJson || fileName.endsWith('.json')) {
            try {
              final arr = jsonDecode(text) as List<dynamic>;
              for (final entry in arr) {
                final e = entry as Map<String, dynamic>;
                final pUrl = e['url']?.toString() ?? '';
                final user = e['username']?.toString() ?? e['user']?.toString() ?? '';
                final pass = e['password']?.toString() ?? e['pass']?.toString() ?? '';
                if (pUrl.isNotEmpty && user.length >= 3 && pass.length >= 3) {
                  result.add(_Portal(
                    cleanPortalUrl(pUrl),
                    user,
                    pass,
                    'github/$name',
                  ));
                }
              }
            } catch (_) {}
          } else {
            result.addAll(extractPortals(text, 'github/$name:$fileName'));
          }
          return result;
        }));
        for (final r in results) {
          for (final p in r) {
            final key = '${p.url}|${p.username}|${p.password}';
            if (seen.add(key)) portals.add(p);
          }
        }
      }
    }

    onEvent(PortalNutzProgress('Bagged ${portals.length} wild nutz so far...'));
    return portals;
  }

  // ── Telegram ────────────────────────────────────────────────────────────

  static Future<List<_Portal>> _fetchTelegramPortals(
    void Function(PortalNutzEvent) onEvent,
  ) async {
    onEvent(const PortalNutzProgress('Tapping the social vines for nutz...'));
    final seen = <String>{};
    final portals = <_Portal>[];

    for (final chunk in _chunk(_telegramChannels, _maxParallelFetches)) {
      final results = await Future.wait(chunk.map((channel) async {
        final channelPortals = <_Portal>[];
        try {
          final url = 'https://t.me/s/$channel';
          final html = await _fetchTextWithHeaders(url, {'User-Agent': _ua});
          if (html == null) return channelPortals;
          final msgRegex = RegExp(
            r'<div class="tgme_widget_message_text[^"]*"[^>]*>([\s\S]*?)</div>\s*</div>',
          );
          for (final m in msgRegex.allMatches(html)) {
            final text = m.group(1)!
                .replaceAll(RegExp(r'<br\s*/?>'), '\n')
                .replaceAll(RegExp(r'<[^>]+>'), '')
                .replaceAll('&amp;', '&')
                .replaceAll('&lt;', '<')
                .replaceAll('&gt;', '>')
                .replaceAll('&quot;', '"')
                .trim();
            if (text.isNotEmpty) {
              final localSeen = <String>{};
              await _collectPortalsFromText(
                text,
                'telegram:$channel',
                localSeen,
                channelPortals,
              );
            }
          }
        } catch (_) {}
        return channelPortals;
      }));
      for (final channelPortals in results) {
        for (final p in channelPortals) {
          final key = '${p.url}|${p.username}|${p.password}';
          if (seen.add(key)) portals.add(p);
        }
      }
    }

    onEvent(PortalNutzProgress('Caught ${portals.length} more rolling nutz...'));
    return portals;
  }

  // ── Reddit ──────────────────────────────────────────────────────────────

  static Future<List<_Portal>> _fetchRedditPortals() async {
    final seen = <String>{};
    final portals = <_Portal>[];

    for (final chunk in _chunk(_redditSubreddits, _maxParallelFetches)) {
      final results = await Future.wait(chunk.map((sub) async {
        final subPortals = <_Portal>[];
        String? rss;
        for (final host in _redditRssHosts) {
          final url = 'https://$host/r/$sub/new/.rss';
          rss = await _fetchTextWithHeaders(url, {
            'User-Agent':
                'Mozilla/5.0 (compatible; PodcastFeedFetcher/1.0; +http://example.com)',
          });
          if (rss != null) break;
        }
        if (rss == null) return subPortals;
        try {
          final itemRegex = RegExp(r'<item>([\s\S]*?)</item>');
          for (final item in itemRegex.allMatches(rss)) {
            final itemText = item.group(1)!;
            final title = RegExp(r'<title>([\s\S]*?)</title>')
                .firstMatch(itemText)
                ?.group(1);
            final desc = RegExp(r'<description>([\s\S]*?)</description>')
                .firstMatch(itemText)
                ?.group(1);
            final body = '${title ?? ''}\n${desc ?? ''}'
                .replaceAll('&amp;', '&')
                .replaceAll('&lt;', '<')
                .replaceAll('&gt;', '>')
                .replaceAll('&quot;', '"');
            if (body.length > 15) {
              subPortals.addAll(extractPortals(body, 'reddit:$sub'));
            }
          }
        } catch (_) {}
        return subPortals;
      }));
      for (final subPortals in results) {
        for (final p in subPortals) {
          final key = '${p.url}|${p.username}|${p.password}';
          if (seen.add(key)) portals.add(p);
        }
      }
    }
    return portals;
  }

  // ── AMZ (iptv.tutoje.cz) ────────────────────────────────────────────────

  static Future<List<_Portal>> _fetchAmzPortals(
    void Function(PortalNutzEvent) onEvent,
  ) async {
    onEvent(const PortalNutzProgress('Digging through the deep stash...'));
    final seen = <String>{};
    final portals = <_Portal>[];

    try {
      for (var page = 1; page <= 5; page++) {
        final html = await _fetchTextWithHeaders(
          'https://iptv.tutoje.cz/list/?page=$page',
          {'User-Agent': _ua},
        );
        if (html == null) break;
        final hashes = RegExp(r'\?data=([a-f0-9]{32})')
            .allMatches(html)
            .map((m) => m.group(1)!)
            .toSet()
            .toList();
        if (hashes.isEmpty) break;
        for (final hash in hashes.take(20)) {
          final decoded = await _fetchTextWithHeaders(
            'https://iptv.tutoje.cz/?data=$hash',
            {'User-Agent': _ua},
          );
          if (decoded == null) continue;
          final serverMatch = RegExp(r'name="server_url"\s+value="([^"]*)"')
              .firstMatch(decoded);
          final userMatches = RegExp(
            r'<span[^>]*class="[^"]*font-black text-3xl[^"]*"[^>]*>([^<]+)</span>',
          ).allMatches(decoded).toList();
          final server = serverMatch?.group(1);
          if (server == null) continue;
          final username = userMatches.isNotEmpty
              ? userMatches.first.group(1)!.trim()
              : null;
          if (username == null) continue;
          final password = userMatches.length > 1
              ? userMatches[1].group(1)!.trim()
              : '';
          final key = '$server|$username|$password';
          if (seen.add(key)) {
            portals.add(_Portal(server, username, password, 'amziptv'));
          }
        }
      }
    } catch (_) {}

    onEvent(PortalNutzProgress('Unearthed ${portals.length} hidden nutz...'));
    return portals;
  }

  // ── Verification ────────────────────────────────────────────────────────

  static Future<_VerifiedPortal?> _verifyPortal(_Portal p) async {
    if (_cancelled) return null;
    if (isAdultText(p.url)) return null;
    final viaApi = await _verifyViaPlayerApi(p);
    if (viaApi != null) return viaApi;
    return _verifyViaM3U(p);
  }

  static Future<_VerifiedPortal?> _verifyViaPlayerApi(_Portal p) async {
    try {
      final url = '${p.url}/player_api.php?username=${p.username}&password=${p.password}';
      final body = await _fetchTextWithHeaders(url, {'User-Agent': 'VLC/3.0.20'});
      if (body == null) return null;
      try {
        final element = jsonDecode(body);
        if (element is Map<String, dynamic>) {
          final info = element['user_info'] is Map
              ? element['user_info'] as Map<String, dynamic>
              : element;
          final auth = info['auth']?.toString() ?? '';
          final status = info['status']?.toString() ?? '';
          if (auth == '1' ||
              status == 'active' ||
              element.containsKey('user_info')) {
            final name = info['username']?.toString() ?? p.username;
            final accountInfo = XtreamClient.parseAccountInfo(body);
            return _VerifiedPortal(
              portal: p,
              name: name,
              domain: extractDomain(p.url),
              expDate: accountInfo?.expDate,
              maxConnections: accountInfo?.maxConnections,
              activeConnections: accountInfo?.activeConnections,
              status: accountInfo?.status,
              isTrial: accountInfo?.isTrial ?? false,
            );
          }
        }
      } catch (_) {}
    } catch (_) {}
    return null;
  }

  static Future<_VerifiedPortal?> _verifyViaM3U(_Portal p) async {
    try {
      final url =
          '${p.url}/get.php?username=${p.username}&password=${p.password}&type=m3u_plus';
      final text = await _fetchTextLimited(
        url,
        {'User-Agent': 'VLC/3.0.20'},
        _maxVerifyBytes,
      );
      if (text == null) return null;
      if (RegExp(r'#EXTM3U', caseSensitive: false).hasMatch(text) &&
          !RegExp(r'<html|<head|<body', caseSensitive: false).hasMatch(text)) {
        final urlCount = text.split('\n').where((l) => l.startsWith('http')).length;
        if (urlCount >= 5) {
          final lines = text.split('\n');
          final adultCount = lines.where(isAdultText).length;
          final adultRatio = adultCount / (lines.isEmpty ? 1 : lines.length);
          if (adultRatio < 0.15) {
            return _VerifiedPortal(
              portal: p,
              name: p.username,
              domain: extractDomain(p.url),
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<int> _getChannelCount(_Portal p) async {
    try {
      final url =
          '${p.url}/player_api.php?username=${p.username}&password=${p.password}&action=get_live_streams';
      final text = await _fetchTextLimited(
        url,
        {'User-Agent': 'VLC/3.0.20'},
        _maxCountBytes,
      );
      if (text != null) {
        try {
          final arr = jsonDecode(text);
          if (arr is List) return arr.length;
        } catch (_) {}
      }
    } catch (_) {}

    try {
      final url =
          '${p.url}/get.php?username=${p.username}&password=${p.password}&type=m3u_plus';
      final text = await _fetchTextLimited(
        url,
        {'User-Agent': 'VLC/3.0.20'},
        _maxCountBytes,
      );
      if (text != null) {
        return text.split('\n').where((l) => l.startsWith('http')).length;
      }
    } catch (_) {}
    return 0;
  }

  static String _cacheKey(_VerifiedPortal vp) =>
      '${domainKey(vp.portal.url)}|${vp.portal.username}|${vp.portal.password}'
          .toLowerCase();

  // ── Goal-oriented verify ────────────────────────────────────────────────

  static Future<List<_VerifiedPortal>> _verifyGoalOriented(
    List<_Portal> candidates,
    int maxResults,
    void Function(int tested) onTested,
  ) async {
    if (candidates.isEmpty || maxResults <= 0) return const [];
    final results = <_VerifiedPortal>[];
    final workers = math.min(_maxParallelFetches, candidates.length);
    var nextIndex = 0;
    var tested = 0;

    Future<void> worker() async {
      while (true) {
        if (_cancelled || results.length >= maxResults) return;
        final idx = nextIndex;
        nextIndex++;
        if (idx >= candidates.length) return;
        final v = await _verifyPortal(candidates[idx]);
        if (_cancelled) return;
        tested++;
        onTested(tested);
        if (v != null) {
          results.add(v);
          if (results.length >= maxResults) return;
        }
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
    return results;
  }

  static Future<List<_CountedPortal>> _countPortals(
    List<_VerifiedPortal> verified,
    void Function(int done, int total) onProgress,
  ) async {
    final result = <_CountedPortal>[];
    var done = 0;
    for (final chunk in _chunk(verified, _maxCountParallel)) {
      final counted = await Future.wait(
        chunk.map((vp) async => _CountedPortal(vp, await _getChannelCount(vp.portal))),
      );
      result.addAll(counted);
      done += counted.length;
      onProgress(done, verified.length);
    }
    return result;
  }

  static List<PortalNutzEntry> _presentEntries(
    List<_CountedPortal> portals, {
    required int maxPortals,
    required int minChannels,
    required bool noAdult,
    required bool adultOnly,
    required bool englishOnly,
    required bool sportsOnly,
  }) {
    final filtered = portals
        .where((cp) => cp.count >= minChannels)
        .where((cp) => !noAdult || !isAdultText(cp.verified.name))
        .where((cp) => !adultOnly || isAdultText(cp.verified.name))
        .where((cp) => !englishOnly || !hasNonLatinScript(cp.verified.name))
        .where((cp) =>
            !sportsOnly ||
            _sportsKeywords.any((k) =>
                cp.verified.name.toLowerCase().contains(k) ||
                cp.verified.domain.toLowerCase().contains(k)))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final taken = filtered.take(maxPortals).toList();
    var num = 0;
    return taken.map((cp) {
      num++;
      return PortalNutzEntry(
        label: 'portal$num',
        url: cp.verified.portal.url,
        username: cp.verified.portal.username,
        password: cp.verified.portal.password,
        channelCount: math.min(cp.count, 500),
        domain: cp.verified.domain,
        expDate: cp.verified.expDate,
        maxConnections: cp.verified.maxConnections,
        activeConnections: cp.verified.activeConnections,
        status: cp.verified.status,
        isTrial: cp.verified.isTrial,
      );
    }).toList();
  }

  // ── Public API ──────────────────────────────────────────────────────────

  static Future<void> scrape({
    bool englishOnly = true,
    bool noAdult = true,
    bool sportsOnly = false,
    bool adultOnly = false,
    Set<String> excludeServers = const {},
    required void Function(PortalNutzEvent event) onEvent,
  }) async {
    cancel();
    _cancelled = false;
    try {
      final maxPortals = sportsOnly ? 10 : 5;
      final excludedDomains = excludeServers.map(domainKey).toSet();

      // 1. Fast path — 1-hour verified cache already has good portals
      final cachedList = _cacheSnapshot()
          .where((cp) => !excludedDomains.contains(domainKey(cp.url)))
          .where((cp) => !noAdult || !isAdultText(cp.name))
          .where((cp) => !adultOnly || isAdultText(cp.name))
          .where((cp) => !englishOnly || !hasNonLatinScript(cp.name))
          .where((cp) =>
              !sportsOnly ||
              _sportsKeywords.any((k) =>
                  cp.name.toLowerCase().contains(k) ||
                  cp.domain.toLowerCase().contains(k)))
          .toList()
        ..sort((a, b) => b.channelCount.compareTo(a.channelCount));
      final cached = cachedList.take(maxPortals).toList();

      if (cached.isNotEmpty) {
        onEvent(const PortalNutzProgress('Serving fresh nutz from the stash...'));
        var i = 0;
        onEvent(PortalNutzResult(
          cached.map((cp) {
            i++;
            return _toEntry(cp, 'portal$i');
          }).toList(),
        ));
        return;
      }

      // 2. Harvest candidates from all sources, in parallel
      onEvent(const PortalNutzProgress('Throwing nutz at portals...'));
      final fetched = await Future.wait([
        _fetchGitHubPortals(onEvent),
        _fetchTelegramPortals(onEvent),
        _fetchRedditPortals(),
        _fetchAmzPortals(onEvent),
      ]);
      final raw = fetched.expand((e) => e).toList();

      onEvent(PortalNutzProgress('Cracking ${raw.length} shells to find the good ones...'));

      final byCreds = <String, _Portal>{};
      for (final p in raw) {
        byCreds.putIfAbsent('${p.username}|${p.password}'.toLowerCase(), () => p);
      }

      final freshPool = byCreds.values
          .where((p) => !excludedDomains.contains(domainKey(p.url)))
          .toList()
        ..shuffle();
      final pool = freshPool.take(_candidatePoolSize).toList();

      // 3. Goal-oriented verify — stop the instant maxPortals are alive
      onEvent(PortalNutzProgress('Testing nutz... 0/${pool.length}'));
      final verified = await _verifyGoalOriented(pool, maxPortals, (tested) {
        onEvent(PortalNutzProgress('Testing nutz... $tested/${pool.length}'));
      });
      if (verified.isEmpty) {
        onEvent(const PortalNutzError('No ripe nutz found — try different filters!'));
        return;
      }

      // 4. Present immediately (counts=0 placeholder)
      onEvent(const PortalNutzProgress('Roasted the duds, here are the premium nutz!'));
      onEvent(PortalNutzResult(
        _presentEntries(
          verified.map((v) => _CountedPortal(v, 0)).toList(),
          maxPortals: maxPortals,
          minChannels: 0,
          noAdult: noAdult,
          adultOnly: adultOnly,
          englishOnly: englishOnly,
          sportsOnly: sportsOnly,
        ),
      ));

      // 5. Background: fetch channel counts, then cache + re-emit with counts
      final counted = await _countPortals(verified, (done, total) {
        onEvent(PortalNutzProgress('Counting channels... $done/$total'));
      });
      for (final cp in counted) {
        _cachePut(_cacheKey(cp.verified), _toCachedPortal(cp));
      }
      final full = _presentEntries(
        counted,
        maxPortals: maxPortals,
        minChannels: 5,
        noAdult: noAdult,
        adultOnly: adultOnly,
        englishOnly: englishOnly,
        sportsOnly: sportsOnly,
      );
      if (full.isNotEmpty) {
        onEvent(PortalNutzResult(full));
      }
    } catch (e) {
      onEvent(PortalNutzError('Dropped a nutz! $e'));
    }
  }

  static String? formatAccountInfoLine({
    String? expDate,
    int? maxConnections,
    int? activeConnections,
    String? status,
    bool? isTrial,
  }) {
    final parts = <String>[];
    if (expDate != null) {
      final exp = int.tryParse(expDate) ?? 0;
      final days = ((exp - DateTime.now().millisecondsSinceEpoch) ~/ 86400000);
      if (days <= 0) {
        parts.add('Expired');
      } else if (days == 1) {
        parts.add('Exp 1d');
      } else {
        parts.add('Exp ${days}d');
      }
    }
    if (activeConnections != null && maxConnections != null) {
      parts.add('$activeConnections/$maxConnections conns');
    } else if (maxConnections != null) {
      parts.add('max $maxConnections conns');
    }
    if (isTrial == true) parts.add('Trial');
    final statusClean = status?.trim();
    if (statusClean != null &&
        statusClean.isNotEmpty &&
        statusClean.toLowerCase() != 'active') {
      parts.add(statusClean);
    }
    final joined = parts.join(' · ').trim();
    return joined.isEmpty ? null : joined;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static _CachedPortal _toCachedPortal(_CountedPortal cp) => _CachedPortal(
        url: cp.verified.portal.url,
        username: cp.verified.portal.username,
        password: cp.verified.portal.password,
        name: cp.verified.name,
        domain: cp.verified.domain,
        channelCount: math.min(cp.count, 500),
        expDate: cp.verified.expDate,
        maxConnections: cp.verified.maxConnections,
        activeConnections: cp.verified.activeConnections,
        status: cp.verified.status,
        isTrial: cp.verified.isTrial,
        verifiedAt: DateTime.now().millisecondsSinceEpoch,
      );

  static PortalNutzEntry _toEntry(_CachedPortal cp, String label) =>
      PortalNutzEntry(
        label: label,
        url: cp.url,
        username: cp.username,
        password: cp.password,
        channelCount: cp.channelCount,
        domain: cp.domain,
        expDate: cp.expDate,
        maxConnections: cp.maxConnections,
        activeConnections: cp.activeConnections,
        status: cp.status,
        isTrial: cp.isTrial,
      );

  static List<List<T>> _chunk<T>(List<T> items, int size) {
    if (items.isEmpty) return const [];
    final result = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      result.add(items.sublist(i, math.min(i + size, items.length)));
    }
    return result;
  }
}

class _Portal {
  final String url;
  final String username;
  final String password;
  final String source;

  const _Portal(this.url, this.username, this.password, this.source);
}

class _VerifiedPortal {
  final _Portal portal;
  final String name;
  final String domain;
  final String? expDate;
  final int? maxConnections;
  final int? activeConnections;
  final String? status;
  final bool isTrial;

  const _VerifiedPortal({
    required this.portal,
    required this.name,
    required this.domain,
    this.expDate,
    this.maxConnections,
    this.activeConnections,
    this.status,
    this.isTrial = false,
  });
}

class _CountedPortal {
  final _VerifiedPortal verified;
  final int count;

  const _CountedPortal(this.verified, this.count);
}

class _CachedPortal {
  final String url;
  final String username;
  final String password;
  final String name;
  final String domain;
  final int channelCount;
  final String? expDate;
  final int? maxConnections;
  final int? activeConnections;
  final String? status;
  final bool isTrial;
  final int verifiedAt;

  const _CachedPortal({
    required this.url,
    required this.username,
    required this.password,
    required this.name,
    required this.domain,
    required this.channelCount,
    this.expDate,
    this.maxConnections,
    this.activeConnections,
    this.status,
    this.isTrial = false,
    required this.verifiedAt,
  });
}

extension _SubstringHelpers on String {
  String substringAfter(String marker) {
    final idx = indexOf(marker);
    if (idx < 0) return this;
    return substring(idx + marker.length);
  }

  String substringBefore(String marker) {
    final idx = indexOf(marker);
    if (idx < 0) return this;
    return substring(0, idx);
  }
}
