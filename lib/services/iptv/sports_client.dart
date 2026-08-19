// Port of `SportsClient.kt` — thesportsdb TV events.
import 'dart:convert';

import '../../models/iptv/sports_models.dart';
import 'iptv_http.dart';

class SportsClient {
  static const String _base = 'https://www.thesportsdb.com/api/v1/json/123';

  static Future<List<SportEvent>> fetchTodaysEvents(String date) async {
    try {
      final url = '$_base/eventstv.php?d=$date';
      final response = await IptvHttp.getText(url,
          timeout: const Duration(seconds: 15));
      final root = jsonDecode(response);
      if (root is! Map<String, dynamic>) return const [];
      final events = (root['tvevents'] ?? root['events']) as List<dynamic>? ??
          const [];
      return events
          .whereType<Map<String, dynamic>>()
          .map((e) => SportEvent.fromJson(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
