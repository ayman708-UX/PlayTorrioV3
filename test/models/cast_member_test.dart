import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/movie/cast_member.dart';

void main() {
  group('CastMember & CrewMember', () {
    test('CastMember parses from string', () {
      final cast = CastMember.fromJson('Leonardo DiCaprio');
      expect(cast.name, 'Leonardo DiCaprio');
      expect(cast.character, isNull);
    });

    test('CastMember parses from JSON map with profile image', () {
      final cast = CastMember.fromJson({
        'name': 'Cillian Murphy',
        'character': 'J. Robert Oppenheimer',
        'profile_path': '/3DOT88s9mFfK64nN1x.jpg',
      });
      expect(cast.name, 'Cillian Murphy');
      expect(cast.character, 'J. Robert Oppenheimer');
      expect(cast.profileUrl, 'https://image.tmdb.org/t/p/w276_and_h350_face/3DOT88s9mFfK64nN1x.jpg');
    });

    test('CrewMember parses director from map', () {
      final crew = CrewMember.fromJson({
        'name': 'Christopher Nolan',
        'job': 'Director',
        'profile_path': '/x8B4P0zH4n8k.jpg',
      });
      expect(crew.name, 'Christopher Nolan');
      expect(crew.job, 'Director');
      expect(crew.profileUrl, 'https://image.tmdb.org/t/p/w276_and_h350_face/x8B4P0zH4n8k.jpg');
    });
  });
}
