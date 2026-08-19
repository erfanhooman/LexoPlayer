import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/features/subtitles/logic/subtitle_parser.dart';

void main() {
  test('Parse actual downloaded OpenSubtitles SRT file or sample content',
      () async {
    const path =
        '/Users/erfanhooman/Documents/LexoPlayer/Subtitles/4509790_Don_t_Trust_The_B----_In_Apartment_23_S01E01_720p_WEB-DL_DD5.1_H.264-NFHD-eng.srt';
    if (File(path).existsSync()) {
      final blocks = await SubtitleParser.parseFile(path);
      expect(blocks, isNotEmpty);
      expect(blocks[0].text, contains('Living in New York'));
    } else {
      const sampleSrt = '''1
00:00:01,000 --> 00:00:04,000
Living in New York is a dream.

2
00:00:05,000 --> 00:00:08,000
It can be scary, but rewarding.
''';
      final blocks = SubtitleParser.parseSrt(sampleSrt);
      expect(blocks, isNotEmpty);
      expect(blocks[0].text, contains('Living in New York'));
    }
  });
}
