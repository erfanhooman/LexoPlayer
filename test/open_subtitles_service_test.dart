import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/features/subtitles/logic/subtitle_parser.dart';

void main() {
  test('Parse actual downloaded OpenSubtitles SRT file from disk', () async {
    final path = '/Users/erfanhooman/Documents/LexoPlayer/Subtitles/4509790_Don_t_Trust_The_B----_In_Apartment_23_S01E01_720p_WEB-DL_DD5.1_H.264-NFHD-eng.srt';
    final blocks = await SubtitleParser.parseFile(path);
    print('Parsed ${blocks.length} blocks from actual downloaded SRT');
    expect(blocks, isNotEmpty);
    for (int i = 0; i < 10 && i < blocks.length; i++) {
      print('  Block $i: ${blocks[i].startTime} → ${blocks[i].endTime} = "${blocks[i].text}"');
    }
    // Verify first block content matches expected from head output
    expect(blocks[0].text, contains('Living in New York'));
  });
}
