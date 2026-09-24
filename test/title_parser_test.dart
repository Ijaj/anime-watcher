import 'package:anime_watcher/services/title_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TitleExtractor.extract', () {
    final cases = <String, (String, List<int>)>{
      'Attack.on.Titan.S01.1080p.BluRay.x265-EMBER': ('Attack On Titan', [1]),
      '[SubsPlease] Frieren - Beyond Journey\'s End S01 (1080p)': ('Frieren Beyond Journey\'s End', [1]),
      'Kaguya-sama.Love.is.War.S01-S03.1080p.WEB-DL': ('Kaguya-sama Love Is War', [1, 2, 3]),
      'Demon Slayer Season 2 1080p': ('Demon Slayer', [2]),
      'Mushoku.Tensei.S02P01.1080p.WEB-DL.DUAL': ('Mushoku Tensei', [2]),
      'Your Name (2016) 1080p BluRay': ('Your Name', []),
      'Spirited_Away_2001_1080p': ('Spirited Away', []),
      'one piece': ('One Piece', []),
      'Mob Psycho 100 S03 1080p': ('Mob Psycho 100', [3]),
      '3.Body.Problem.S01.1080p.NF.WEB-DL.DDP5.1.Atmos.H.264-FLUX': ('3 Body Problem', [1]),
    };

    cases.forEach((input, expected) {
      test(input, () {
        final r = TitleExtractor.extract(input);
        expect(r.title, expected.$1);
        expect(r.seasons, expected.$2);
      });
    });

    test('empty input', () {
      expect(TitleExtractor.extract('').title, '');
    });

    test('year is captured', () {
      expect(TitleExtractor.extract('Your Name (2016) 1080p').year, 2016);
      expect(TitleExtractor.extract('Spirited.Away.2001.1080p').year, 2001);
    });

    test('parts are flagged', () {
      expect(TitleExtractor.extract('Mushoku.Tensei.S02P01').hasParts, isTrue);
    });
  });

  group('TitleExtractor.seasonFromFolderName', () {
    test('recognises season folders', () {
      expect(TitleExtractor.seasonFromFolderName('Season 2'), 2);
      expect(TitleExtractor.seasonFromFolderName('Season.03'), 3);
      expect(TitleExtractor.seasonFromFolderName('S04'), 4);
      expect(TitleExtractor.seasonFromFolderName('Show.S05.1080p'), 5);
      expect(TitleExtractor.seasonFromFolderName('Specials'), 0);
      expect(TitleExtractor.seasonFromFolderName('Subs'), isNull);
    });
  });

  group('EpisodeParser.parse', () {
    final cases = <String, (int?, int?)>{
      'Attack.on.Titan.S01E05.1080p.mkv': (1, 5),
      'Show - s02e10 - Title.mp4': (2, 10),
      'Show 1x07.avi': (1, 7),
      '[SubsPlease] Frieren - 05 (1080p) [A1B2C3D4].mkv': (null, 5),
      '[Group] Show - 12v2 [1080p].mkv': (null, 12),
      'Show Episode 3.mkv': (null, 3),
      'Show.EP09.1080p.x264.mkv': (null, 9),
      'Show E101.mkv': (null, 101),
      '[Group] Show [07][1080p].mkv': (null, 7),
      'Show 04.mkv': (null, 4),
      'Movie.mkv': (null, null),
    };

    cases.forEach((input, expected) {
      test(input, () {
        final r = EpisodeParser.parse(input);
        expect((r.season, r.episode), expected);
      });
    });
  });
}
