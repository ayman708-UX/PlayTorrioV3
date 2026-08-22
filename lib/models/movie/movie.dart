class Movie {
  final String id;
  final String name;
  final String? poster;
  final String? year;
  final String type;
  final String addonBaseUrl;

  Movie({
    required this.id,
    required this.name,
    this.poster,
    this.year,
    required this.type,
    required this.addonBaseUrl,
  });

  factory Movie.fromJson(
    Map<String, dynamic> json,
    String addonBaseUrl, {
    String? fallbackType,
  }) {
    // Prefer the addon-provided type; fall back to the catalog type when the
    // addon omits it (many Stremio addons don't set per-item type).
    final type = json['type']?.toString() ?? fallbackType ?? 'movie';
    return Movie(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      poster: json['poster']?.toString(),
      year: json['releaseInfo']?.toString() ?? json['year']?.toString(),
      type: type,
      addonBaseUrl: addonBaseUrl,
    );
  }
}
