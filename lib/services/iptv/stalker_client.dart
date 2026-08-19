import 'dart:convert';

import '../../models/iptv/iptv_models.dart';
import 'iptv_http.dart';

/// Port of `StalkerClient.kt` — Stalker portal channel fetching.
class StalkerClient {
  static Future<List<IptvChannel>> fetchChannels(
    String server,
    String macAddress,
    String accountId,
  ) async {
    final baseUrl = server.replaceAll(RegExp(r'/+$'), '');
    final mac = macAddress.trim().toUpperCase();
    final token = await _getToken(baseUrl, mac);
    if (token == null) return const [];
    final channelsJson = await IptvHttp.getText(
      '$baseUrl/stalker_portal/api/v1/channels?mac=$mac&token=$token&type=all',
    );
    return _parseChannels(channelsJson, accountId, baseUrl);
  }

  static Future<String?> _getToken(String baseUrl, String mac) async {
    try {
      final response = await IptvHttp.getText(
        '$baseUrl/stalker_portal/api/v1/portal/init?mac=$mac',
      );
      final obj = jsonDecode(response) as Map<String, dynamic>;
      final token = obj['token']?.toString();
      if (token != null && token.isNotEmpty) return token;
      final data = obj['data'];
      if (data is Map) {
        final jsToken = data['js_token']?.toString();
        final apiToken = data['api_token']?.toString();
        return jsToken ?? apiToken;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static List<IptvChannel> _parseChannels(
    String jsonStr,
    String sourceId,
    String baseUrl,
  ) {
    final channels = <IptvChannel>[];
    try {
      final root = jsonDecode(jsonStr) as Map<String, dynamic>;
      final data = root['data'] as List<dynamic>? ?? root.values.first;
      var counter = 0;
      if (data is! List) return const [];
      for (final element in data) {
        final obj = element as Map<String, dynamic>;
        final name = obj['name']?.toString().trim() ??
            obj['title']?.toString().trim() ??
            '';
        if (name.isEmpty) continue;
        final cmd = obj['cmd']?.toString();
        final url = _extractUrl(cmd, baseUrl);
        if (url == null) continue;
        counter++;
        final chId = 'stalker_${sourceId}_$counter';
        final logo = obj['logo']?.toString();
        final epgId = obj['epg_id']?.toString();
        channels.add(
          IptvChannel(
            id: chId,
            name: name,
            logo: (logo == null || logo.isEmpty) ? null : logo,
            group: obj['genres']?.toString().trim() ?? 'Other',
            url: url,
            epgChannelId: (epgId == null || epgId.isEmpty) ? null : epgId,
            sourceType: SourceType.stalker,
            sourceId: sourceId,
          ),
        );
      }
    } catch (_) {}
    return channels;
  }

  static String? _extractUrl(String? cmd, String baseUrl) {
    if (cmd == null) return null;
    final parts = cmd.split(' ');
    final uri = parts.isEmpty ? '' : parts.last;
    if (uri.startsWith('http://') || uri.startsWith('https://')) return uri;
    if (uri.isEmpty) return null;
    return '$baseUrl/$uri';
  }
}
