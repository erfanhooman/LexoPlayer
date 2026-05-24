import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/features/main_menu/presentation/main_menu_screen.dart';

void main() {
  group('formatMediaTitle tests', () {
    test('TV show with season and episode tags', () {
      expect(
        formatMediaTitle('House.of.the.Dragon.S02.1080p.mkv'),
        equals('House of the Dragon - S02'),
      );
      expect(
        formatMediaTitle('Game.of.Thrones.S08E03.720p.h264.mkv'),
        equals('Game of Thrones - S08E03'),
      );
    });

    test('Movie with release year', () {
      expect(
        formatMediaTitle('The.Matrix.1999.1080p.bluray.mkv'),
        equals('The Matrix (1999)'),
      );
      expect(
        formatMediaTitle('Interstellar.2014.2160p.web-dl.mp4'),
        equals('Interstellar (2014)'),
      );
    });

    test('HTTP/HTTPS streaming links', () {
      expect(
        formatMediaTitle('https://streaming.service.com/movies/Inception.2010.1080p.mp4?token=123'),
        equals('Inception (2010)'),
      );
    });

    test('Simple video files without tags', () {
      expect(
        formatMediaTitle('My_Home_Video.mp4'),
        equals('My Home Video'),
      );
      expect(
        formatMediaTitle('/Users/user/Movies/Vacation-Trip-2025.mov'),
        equals('Vacation Trip (2025)'),
      );
    });

    test('Edge cases', () {
      expect(formatMediaTitle(''), equals('Unknown Title'));
    });
  });
}
