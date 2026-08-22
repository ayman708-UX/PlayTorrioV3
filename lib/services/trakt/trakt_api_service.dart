import 'dart:convert';
import 'package:http/http.dart' as http;
import 'trakt_auth_service.dart';

class TraktApiService {
  static const String _baseUrl = 'https://api.trakt.tv';

  static Future<Map<String, String>> _headers() async {
    final auth = TraktAuthService();
    var token = auth.accessToken;
    if (token == null) {
      final refreshed = await auth.refreshAccessToken();
      if (refreshed) token = auth.accessToken;
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${token ?? ''}',
      'trakt-api-version': '2',
      'trakt-api-key': TraktAuthService.clientId,
    };
  }

  static Future<List<Map<String, dynamic>>> getWatchlistMovies() async {
    final headers = await _headers();
    final uri = Uri.parse('$_baseUrl/sync/watchlist/movies');
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getWatchlistShows() async {
    final headers = await _headers();
    final uri = Uri.parse('$_baseUrl/sync/watchlist/shows');
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  static Future<bool> addToWatchlist({
    required List<Map<String, dynamic>> movies,
    required List<Map<String, dynamic>> shows,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse('$_baseUrl/sync/watchlist');
    final body = jsonEncode({
      'movies': movies,
      'shows': shows,
    });

    final response = await http.post(uri, headers: headers, body: body);
    return response.statusCode == 201;
  }

  static Future<bool> removeFromWatchlist({
    required List<Map<String, dynamic>> movies,
    required List<Map<String, dynamic>> shows,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse('$_baseUrl/sync/watchlist/remove');
    final body = jsonEncode({
      'movies': movies,
      'shows': shows,
    });

    final response = await http.post(uri, headers: headers, body: body);
    return response.statusCode == 200;
  }

  static Future<Map<String, dynamic>?> getLastActivities() async {
    final headers = await _headers();
    final uri = Uri.parse('$_baseUrl/sync/last_activities');
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// Scrobble watching/progress/pause/stop to Trakt.
  /// [action]: 'start', 'pause', 'stop'
  /// [progress]: 0.0 to 100.0 percent
  static Future<bool> scrobble({
    required String action,
    required double progress,
    Map<String, dynamic>? movie,
    Map<String, dynamic>? show,
    Map<String, dynamic>? episode,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse('$_baseUrl/scrobble/$action');
    final payload = <String, dynamic>{
      'progress': progress.clamp(0.0, 100.0),
      if (movie != null) 'movie': movie,
      if (show != null) 'show': show,
      if (episode != null) 'episode': episode,
    };

    try {
      final response = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
