import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/features/subtitles/logic/video_filename_parser.dart';

void main() {
  group('VideoFilenameParser Tests', () {
    test('Parses SxxExx TV show filenames correctly', () {
      final parsed = VideoFilenameParser.parse(
          'Breaking.Bad.S01E05.720p.HDTV.x264-CTU.mkv');
      expect(parsed.cleanTitle, equals('Breaking Bad'));
      expect(parsed.season, equals(1));
      expect(parsed.episode, equals(5));
      expect(parsed.isTVShow, isTrue);
      expect(parsed.formattedEpisodeStr, equals('S01E05'));
    });

    test('Parses NxN TV show filenames correctly', () {
      final parsed =
          VideoFilenameParser.parse('Game_of_Thrones_3x09_1080p.mp4');
      expect(parsed.cleanTitle, equals('Game of Thrones'));
      expect(parsed.season, equals(3));
      expect(parsed.episode, equals(9));
      expect(parsed.isTVShow, isTrue);
      expect(parsed.formattedEpisodeStr, equals('S03E09'));
    });

    test('Parses Movie with year correctly', () {
      final parsed =
          VideoFilenameParser.parse('The.Matrix.1999.1080p.BluRay.x264.mp4');
      expect(parsed.cleanTitle, equals('The Matrix'));
      expect(parsed.year, equals(1999));
      expect(parsed.isTVShow, isFalse);
    });

    test('Parses simple title without episode or year', () {
      final parsed = VideoFilenameParser.parse('My Sample Video.mp4');
      expect(parsed.cleanTitle, equals('My Sample Video'));
      expect(parsed.isTVShow, isFalse);
    });
  });
}
