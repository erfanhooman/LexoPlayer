import 'dart:io';

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

      test('parses single-digit hours and mm:ss timestamps', () {
        const srtContent = '''1
0:00:03,200 --> 0:00:05,003
Single digit hour cue

2
01:23.456 --> 01:25.789
Missing hour cue
''';

        final blocks = SubtitleParser.parseSrt(srtContent);
        expect(blocks.length, equals(2));
        expect(blocks[0].text, equals('Single digit hour cue'));
        expect(blocks[0].startTime, equals(const Duration(seconds: 3, milliseconds: 200)));
        expect(blocks[1].text, equals('Missing hour cue'));
        expect(blocks[1].startTime, equals(const Duration(minutes: 1, seconds: 23, milliseconds: 456)));
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

    group('cleanSubtitleText', () {
      test('replaces html br tags with spaces', () {
        expect(
          SubtitleParser.cleanSubtitleText('thrive<br>under'),
          equals('thrive under'),
        );
        expect(
          SubtitleParser.cleanSubtitleText('thrive<br/>under'),
          equals('thrive under'),
        );
        expect(
          SubtitleParser.cleanSubtitleText('thrive<br />under'),
          equals('thrive under'),
        );
      });

      test('replaces ASS linebreaks and style tags with spaces', () {
        expect(
          SubtitleParser.cleanSubtitleText('thrive\\Nunder'),
          equals('thrive under'),
        );
        expect(
          SubtitleParser.cleanSubtitleText('thrive{\\an8}\\Nunder'),
          equals('thrive under'),
        );
        expect(
          SubtitleParser.cleanSubtitleText('thrive\\nunder'),
          equals('thrive under'),
        );
      });

      test('collapses multiple whitespace characters', () {
        expect(
          SubtitleParser.cleanSubtitleText('  thrive   \n\t  under  '),
          equals('thrive under'),
        );
      });
    });

    group('parseAss', () {
      test('parses standard ASS events with Format line', () {
        const assContent = '''[Script Info]
Title: Sample

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default,Arial,20

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,Hello from ASS
Dialogue: 0,0:00:05.25,0:00:08.75,Default,,0,0,0,,Second \\N line, with comma
''';

        final blocks = SubtitleParser.parseAss(assContent);
        expect(blocks.length, equals(2));
        expect(blocks[0].text, equals('Hello from ASS'));
        expect(blocks[0].startTime, equals(const Duration(seconds: 1)));
        expect(blocks[0].endTime, equals(const Duration(seconds: 4)));
        expect(blocks[1].text, equals('Second line, with comma'));
        expect(blocks[1].startTime,
            equals(const Duration(seconds: 5, milliseconds: 250)));
      });

      test('ignores Comment lines and non-event sections', () {
        const assContent = '''[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Comment: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,This is a comment
Dialogue: 0,0:00:02.00,0:00:05.00,Default,,0,0,0,,Real dialogue
''';
        final blocks = SubtitleParser.parseAss(assContent);
        expect(blocks.length, equals(1));
        expect(blocks[0].text, equals('Real dialogue'));
      });

      test('falls back to standard layout when Format line is missing', () {
        const assContent = '''[Events]
Dialogue: 0,0:00:03.50,0:00:06.00,Default,,0,0,0,,No format header
''';
        final blocks = SubtitleParser.parseAss(assContent);
        expect(blocks.length, equals(1));
        expect(blocks[0].startTime,
            equals(const Duration(seconds: 3, milliseconds: 500)));
        expect(blocks[0].text, equals('No format header'));
      });

      test('parses Persian ASS dialogue text', () {
        const assContent = '''[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,سلام دنیا
''';
        final blocks = SubtitleParser.parseAss(assContent);
        expect(blocks.length, equals(1));
        expect(blocks[0].text, equals('سلام دنیا'));
      });
    });

    group('detectFormat', () {
      test('sniffs WebVTT, ASS, and SRT by content', () {
        expect(SubtitleParser.detectFormat('WEBVTT\n\n00:00:01.000 --> 00:00:04.000'),
            SubtitleFormat.webVtt);
        expect(SubtitleParser.detectFormat('[Script Info]\n[Events]\nDialogue: 0,...'),
            SubtitleFormat.ass);
        expect(SubtitleParser.detectFormat('1\n00:00:01,000 --> 00:00:04,000\nHi'),
            SubtitleFormat.srt);
      });
    });

    group('cue validation', () {
      test('skips cues whose end is not after their start', () {
        const srtContent = '''1
00:00:05,000 --> 00:00:02,000
Reversed cue

2
00:00:06,000 --> 00:00:08,000
Good cue
''';
        final blocks = SubtitleParser.parseSrt(srtContent);
        expect(blocks.length, equals(1));
        expect(blocks[0].text, equals('Good cue'));
      });
    });

    group('parseFile', () {
      test('parses a UTF-16 LE encoded SRT file', () async {
        final dir = await Directory.systemTemp.createTemp('lexo_sub_test');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/utf16.srt');
        const text = '1\n00:00:01,000 --> 00:00:04,000\nHello UTF-16\n';
        final codeUnits = text.codeUnits;
        final bytes = <int>[0xFF, 0xFE];
        for (final unit in codeUnits) {
          bytes.add(unit & 0xFF);
          bytes.add((unit >> 8) & 0xFF);
        }
        await file.writeAsBytes(bytes);

        final blocks = await SubtitleParser.parseFile(file.path);
        expect(blocks, isNotEmpty);
        expect(blocks[0].text, equals('Hello UTF-16'));
      });

      test('sniffs format when extension is unknown', () async {
        final dir = await Directory.systemTemp.createTemp('lexo_sub_test');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/subtitle.txt');
        await file.writeAsString(
            'WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nSniffed VTT\n');

        final blocks = await SubtitleParser.parseFile(file.path);
        expect(blocks, isNotEmpty);
        expect(blocks[0].text, equals('Sniffed VTT'));
      });
    });
  });
}
