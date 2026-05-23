import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/features/subtitles/logic/subtitle_parser.dart';

void main() {
  group('SubtitleParser', () {
    group('parseSrt', () {
      test('parses standard SRT format', () {
        const srtContent = '''1
00:00:01,000 --> 00:00:04,000
Hello, world!

2
00:00:05,500 --> 00:00:08,200
This is a test.

3
00:00:10,000 --> 00:00:12,500
Multiple lines
joined together
''';

        final blocks = SubtitleParser.parseSrt(srtContent);

        expect(blocks.length, equals(3));
        expect(blocks[0].text, equals('Hello, world!'));
        expect(blocks[0].startTime, equals(const Duration(seconds: 1)));
        expect(blocks[0].endTime,
            equals(const Duration(seconds: 4)));

        expect(blocks[1].text, equals('This is a test.'));
        expect(blocks[1].startTime,
            equals(const Duration(seconds: 5, milliseconds: 500)));

        expect(blocks[2].text, equals('Multiple lines joined together'));
        expect(blocks[2].startTime,
            equals(const Duration(seconds: 10)));
      });

      test('strips HTML tags from text', () {
        const srtContent = '''1
00:00:01,000 --> 00:00:04,000
<b>Bold</b> and <i>italic</i>
''';

        final blocks = SubtitleParser.parseSrt(srtContent);
        expect(blocks[0].text, equals('Bold and italic'));
      });

      test('handles empty content', () {
        final blocks = SubtitleParser.parseSrt('');
        expect(blocks, isEmpty);
      });

      test('results are sorted by startTime', () {
        const srtContent = '''2
00:00:05,000 --> 00:00:08,000
Second

1
00:00:01,000 --> 00:00:04,000
First
''';

        final blocks = SubtitleParser.parseSrt(srtContent);
        expect(blocks[0].text, equals('First'));
        expect(blocks[1].text, equals('Second'));
      });
    });

    group('parseVtt', () {
      test('parses standard WebVTT format', () {
        const vttContent = '''WEBVTT

00:00:01.000 --> 00:00:04.000
Hello from VTT!

00:00:05.500 --> 00:00:08.200
Second cue
''';

        final blocks = SubtitleParser.parseVtt(vttContent);

        expect(blocks.length, equals(2));
        expect(blocks[0].text, equals('Hello from VTT!'));
        expect(blocks[0].startTime, equals(const Duration(seconds: 1)));
      });

      test('skips NOTE and STYLE blocks', () {
        const vttContent = '''WEBVTT

NOTE This is a comment

STYLE
::cue { color: white; }

00:00:01.000 --> 00:00:04.000
Actual subtitle
''';

        final blocks = SubtitleParser.parseVtt(vttContent);
        expect(blocks.length, equals(1));
        expect(blocks[0].text, equals('Actual subtitle'));
      });
    });
  });
}
