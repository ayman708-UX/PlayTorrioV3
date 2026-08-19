import 'dart:convert';

import '../../models/iptv/iptv_models.dart';

/// Port of `XtreamClient.kt` — Xtream Codes API parsing.
class XtreamClient {
  static PortalAccountInfo? parseAccountInfo(String response) {
    try {
      final decoded = jsonDecode(response);
      if (decoded is! Map<String, dynamic>) return null;
      final info = decoded['user_info'] is Map
          ? decoded['user_info'] as Map<String, dynamic>
          : decoded;
      if (!decoded.containsKey('user_info') &&
          info['auth']?.toString() != '1') {
        return null;
      }

      String? expDate;
      final expRaw = info['exp_date']?.toString();
      if (expRaw != null && expRaw.isNotEmpty && expRaw != 'null') {
        final asLong = int.tryParse(expRaw.trim());
        if (asLong != null) {
          expDate = (asLong > 10000000000 ? asLong : asLong * 1000)
              .toString();
        }
      }

      final isTrialRaw = info['is_trial']?.toString();
      return PortalAccountInfo(
        expDate: expDate,
        maxConnections: int.tryParse(
          info['max_connections']?.toString() ?? '',
        ),
        activeConnections: int.tryParse(
          info['active_connections']?.toString() ?? '',
        ),
        status: info['status']?.toString(),
        isTrial: isTrialRaw == '1' ||
            (isTrialRaw?.toLowerCase() == 'true'),
      );
    } catch (_) {
      return null;
    }
  }

  static List<XtreamCategory> parseCategories(String response) {
    final categories = <XtreamCategory>[];
    try {
      final arr = jsonDecode(response) as List<dynamic>;
      for (final element in arr) {
        final obj = element as Map<String, dynamic>;
        final id = obj['category_id']?.toString();
        final name = obj['category_name']?.toString();
        if (id == null || name == null) continue;
        categories.add(XtreamCategory(id: id, name: name));
      }
    } catch (_) {}
    return categories;
  }

  static List<IptvChannel> parseChannels(
    String response,
    String sourceId,
    String server,
    String username,
    String password,
  ) {
    final channels = <IptvChannel>[];
    try {
      final arr = jsonDecode(response) as List<dynamic>;
      for (final element in arr) {
        final obj = element as Map<String, dynamic>;
        final streamId = obj['stream_id']?.toString();
        if (streamId == null) continue;
        final name = obj['name']?.toString() ??
            obj['stream_type']?.toString() ??
            'Unknown';
        final logo = obj['stream_icon']?.toString();
        final categoryId = obj['category_id']?.toString();
        final epgChannelId = obj['epg_channel_id']?.toString();

        final url = buildXtreamUrl(server, username, password, streamId);

        channels.add(
          IptvChannel(
            id: streamId,
            name: name,
            logo: (logo == null || logo.isEmpty) ? null : logo,
            group: categoryId,
            url: url,
            epgChannelId: (epgChannelId == null || epgChannelId.isEmpty)
                ? null
                : epgChannelId,
            sourceType: SourceType.xtream,
            sourceId: sourceId,
          ),
        );
      }
    } catch (_) {}
    return channels;
  }

  static String buildXtreamUrl(
    String server,
    String username,
    String password,
    String streamId,
  ) {
    final base = server.replaceAll(RegExp(r'/+$'), '');
    return '$base/live/$username/$password/$streamId.ts';
  }
}
