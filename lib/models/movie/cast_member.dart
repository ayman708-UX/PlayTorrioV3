class CastMember {
  final String name;
  final String? character;
  final String? profileUrl;
  final String? tmdbId;

  const CastMember({
    required this.name,
    this.character,
    this.profileUrl,
    this.tmdbId,
  });

  factory CastMember.fromJson(dynamic json) {
    if (json is String) {
      return CastMember(name: json);
    }
    if (json is Map<String, dynamic>) {
      final name = json['name']?.toString() ?? json['title']?.toString() ?? 'Unknown';
      final character = json['character']?.toString() ?? json['role']?.toString();
      final profile = json['profile_path']?.toString() ??
          json['image']?.toString() ??
          json['photo']?.toString() ??
          json['profile']?.toString();
      final profileUrl = profile != null && profile.isNotEmpty
          ? (profile.startsWith('http') ? profile : 'https://image.tmdb.org/t/p/w276_and_h350_face$profile')
          : null;
      final tmdbId = json['id']?.toString() ?? json['tmdb_id']?.toString();

      return CastMember(
        name: name,
        character: character,
        profileUrl: profileUrl,
        tmdbId: tmdbId,
      );
    }
    return CastMember(name: json?.toString() ?? 'Unknown');
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (character != null) 'character': character,
        if (profileUrl != null) 'profileUrl': profileUrl,
        if (tmdbId != null) 'tmdbId': tmdbId,
      };
}

class CrewMember {
  final String name;
  final String job;
  final String? profileUrl;

  const CrewMember({
    required this.name,
    required this.job,
    this.profileUrl,
  });

  factory CrewMember.fromJson(dynamic json, {String job = 'Director'}) {
    if (json is String) {
      return CrewMember(name: json, job: job);
    }
    if (json is Map<String, dynamic>) {
      final name = json['name']?.toString() ?? 'Unknown';
      final role = json['job']?.toString() ?? json['role']?.toString() ?? job;
      final profile = json['profile_path']?.toString() ?? json['photo']?.toString() ?? json['image']?.toString();
      final profileUrl = profile != null && profile.isNotEmpty
          ? (profile.startsWith('http') ? profile : 'https://image.tmdb.org/t/p/w276_and_h350_face$profile')
          : null;

      return CrewMember(
        name: name,
        job: role,
        profileUrl: profileUrl,
      );
    }
    return CrewMember(name: json?.toString() ?? 'Unknown', job: job);
  }
}
