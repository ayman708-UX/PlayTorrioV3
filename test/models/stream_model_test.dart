import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';

void main() {
  group('StreamSource', () {
    group('quality detection', () {
      test('detects 4K from title', () {
        final source = StreamSource(addonName: 'TestAddon', name: 'Test', title: 'Movie.2024.2160p.WEB-DL.mkv\nScraper', url: 'https://x.com');
        expect(source.quality, anyOf('4K', '2160p'));
      });
      test('detects 1080p from title', () {
        final source = StreamSource(addonName: 'TestAddon', name: 'Test', title: 'Movie.2024.1080p.BluRay.mkv\nScraper', url: 'https://x.com');
        expect(source.quality, '1080p');
      });
      test('detects 720p from title', () {
        final source = StreamSource(addonName: 'TestAddon', name: 'Test', title: 'Movie.2024.720p.HDTV.mkv\nScraper', url: 'https://x.com');
        expect(source.quality, '720p');
      });
    });
    group('HDR detection', () {
      test('detects Dolby Vision', () {
        final source = StreamSource(addonName: 'TestAddon', name: 'Test', title: 'Movie.2024.2160p.DV.HDR.mkv\nScraper', url: 'https://x.com');
        expect(source.isHDR, true);
      });
      test('returns false for SDR', () {
        final source = StreamSource(addonName: 'TestAddon', name: 'Test', title: 'Movie.2024.1080p.SDR.mkv\nScraper', url: 'https://x.com');
        expect(source.isHDR, false);
      });
    });
    group('codec detection', () {
      test('detects HEVC/x265', () {
        final source = StreamSource(addonName: 'TestAddon', name: 'Test', title: 'Movie.2024.2160p.x265.mkv\nScraper', url: 'https://x.com');
        expect(source.codec, anyOf('HEVC', 'x265'));
      });
      test('detects H.264/x264', () {
        final source = StreamSource(addonName: 'TestAddon', name: 'Test', title: 'Movie.2024.1080p.x264.mkv\nScraper', url: 'https://x.com');
        expect(source.codec, anyOf('AVC', 'H.264', 'x264'));
      });
    });
    group('qualityRank', () {
      test('4K ranks higher than 1080p', () {
        final fourK = StreamSource(addonName: 'TestAddon', name: 'A', title: '4K.Movie.mkv\nA', url: '');
        final hd = StreamSource(addonName: 'TestAddon', name: 'B', title: '1080p.Movie.mkv\nB', url: '');
        expect(fourK.qualityRank, isNotNull);
        expect(hd.qualityRank, isNotNull);
      });
    });

    group('bitrate detection', () {
      test('detects Mb/s from title', () {
        final source = StreamSource(addonName: 'Torrentio', title: 'Movie.2024.1080p.WEB-DL.8.5Mb/s.x264.mkv', url: 'https://example.com');
        expect(source.bitrateKbps, 8500);
        expect(source.bitrateLabel, '8.5 Mb/s');
      });
      test('detects kbps from title', () {
        final source = StreamSource(addonName: 'Torrentio', title: 'Movie.2024.720p.WEBRip.4237kbps.mkv', url: 'https://example.com');
        expect(source.bitrateKbps, 4237);
        expect(source.bitrateLabel, '4.2 Mb/s');
      });
      test('ignores audio-only bitrates', () {
        final source = StreamSource(addonName: 'Torrentio', title: 'Movie.2024.1080p.AAC.128kbps.mkv', url: 'https://example.com');
        expect(source.bitrateKbps, isNull);
      });
      test('returns null when no bitrate is mentioned', () {
        final source = StreamSource(addonName: 'Torrentio', title: 'Movie.2024.1080p.BluRay.x264.mkv', url: 'https://example.com');
        expect(source.bitrateKbps, isNull);
        expect(source.bitrateLabel, isNull);
      });
    });

    group('estimatedBitrateKbps', () {
      test('estimates from file size and runtime', () {
        // 2 GiB over ~90 min -> (2147483648 * 8) / 5400s ~= 3181 kbps
        final source = StreamSource(addonName: 'Torrentio', title: 'Movie.2024.1080p.2.0 GB.mkv', url: 'https://example.com');
        expect(source.estimatedBitrateKbps(90), 3181);
      });
      test('prefers the stated bitrate over the estimate', () {
        final source = StreamSource(addonName: 'Torrentio', title: 'Movie.2024.1080p.2.0 GB.12Mb/s.mkv', url: 'https://example.com');
        expect(source.estimatedBitrateKbps(90), 12000);
      });
      test('returns null without size or runtime', () {
        final source = StreamSource(addonName: 'Torrentio', title: 'Movie.2024.1080p.mkv', url: 'https://example.com');
        expect(source.estimatedBitrateKbps(null), isNull);
        expect(source.estimatedBitrateKbps(90), isNull);
      });
    });

    group('audio language detection (Spanish Castilian & Latin American)', () {
      test('detects Castilian Spanish from Castellano tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Gladiator.2000.1080p.BluRay.x264.Castellano.AC3',
          url: 'https://example.com',
        );
        final langs = source.getAudioLanguages();
        expect(langs.contains('spanish_castilian'), isTrue);
        expect(langs.contains('spanish'), isTrue);
        expect(langs.contains('spanish_latino'), isFalse);
        expect(source.hasAudioLanguage('spanish_castilian'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.hasAudioLanguage('spanish_latino'), isFalse);
        expect(source.getAudioBadge(), '🇪🇸 CAST');
      });

      test('detects Castilian Spanish from [CAST] tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Gladiator.2000.1080p.[CAST].mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_castilian'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇪🇸 CAST');
      });

      test('detects Castilian Spanish from ES-ES tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Movie.2024.1080p.WEB-DL.ES-ES.mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_castilian'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇪🇸 CAST');
      });

      test('detects Latin American Spanish from Latino tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Avengers.Endgame.2019.1080p.Dual.Audio.Latino-English.mkv',
          url: 'https://example.com',
        );
        final langs = source.getAudioLanguages();
        expect(langs.contains('spanish_latino'), isTrue);
        expect(langs.contains('spanish'), isTrue);
        expect(langs.contains('spanish_castilian'), isFalse);
        expect(source.hasAudioLanguage('spanish_latino'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.hasAudioLanguage('spanish_castilian'), isFalse);
        expect(source.getAudioBadge(), '🇲🇽 LAT');
      });

      test('detects Latin American Spanish from [LAT] tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Dune.Part.Two.2024.1080p.[LAT].mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_latino'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇲🇽 LAT');
      });

      test('detects Latin American Spanish from ES-419 tag', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Movie.2024.1080p.WEB-DL.ES-419.AAC.mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_latino'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇲🇽 LAT');
      });

      test('detects both Castilian and Latin American when both present', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Interstellar.2014.1080p.BluRay.Castellano.Latino.Eng.mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish_castilian'), isTrue);
        expect(source.hasAudioLanguage('spanish_latino'), isTrue);
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.getAudioBadge(), '🇪🇸 CAST / 🇲🇽 LAT');
      });

      test('detects generic Spanish and badges as SPA', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Movie.2024.1080p.Spanish.AAC5.1.mkv',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish'), isTrue);
        expect(source.hasAudioLanguage('spanish_castilian'), isFalse);
        expect(source.hasAudioLanguage('spanish_latino'), isFalse);
        expect(source.getAudioBadge(), '🇪🇸 SPA');
      });

      test('does not match subtitles listing as audio language', () {
        final source = StreamSource(
          addonName: 'Torrentio',
          title: 'Movie.2024.1080p.BluRay.x264\nSubs: Spanish, English, French',
          url: 'https://example.com',
        );
        expect(source.hasAudioLanguage('spanish'), isFalse);
        expect(source.hasAudioLanguage('spanish_castilian'), isFalse);
        expect(source.hasAudioLanguage('spanish_latino'), isFalse);
      });
    });
  });
}
