import 'dart:convert';
import 'dart:io';

import 'package:charset_converter/charset_converter.dart';
import 'package:lexo_player/core/models/subtitle_block.dart';

/// A robust parser for SRT and WebVTT subtitle files.
///
/// Supports:
/// - Automatic format detection by file extension.
/// - Encoding fallback: tries UTF-8 first, then Windows-1252.
/// - Multi-line subtitle text (joined with a single space).
/// - HTML / styling tag stripping.
/// - Output is always sorted by [SubtitleBlock.startTime].
class SubtitleParser {
  SubtitleParser._();

  /// Regex that matches both SRT (`00:01:23,456`) and VTT (`00:01:23.456`)
  /// timestamp arrows, capturing all eight numeric groups.
  static final RegExp _timestampRegex = RegExp(
    r'(\d{2}):(\d{2}):(\d{2})[,\.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,\.](\d{3})',
  );

  /// HTML / styling tag pattern used to clean subtitle text.
  static final RegExp _htmlTagRegex = RegExp(r'<[^>]+>');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Parses a subtitle file at [filePath].
  ///
  /// The format is determined by the file extension:
  /// - `.srt` → [parseSrt]
  /// - `.vtt` → [parseVtt]
  ///
  /// Throws an [UnsupportedError] for unknown extensions.
  ///
  /// **Encoding fallback:** The file is first read as UTF-8. If a
  /// [FormatException] is thrown (invalid byte sequence), the raw bytes are
  /// decoded using `windows-1252` via [CharsetConverter].
  static Future<List<SubtitleBlock>> parseFile(String filePath) async {
    final file = File(filePath);
    final extension = filePath.split('.').last.toLowerCase();

    // Read file content with encoding fallback.
    final content = await _readWithFallback(file);

    switch (extension) {
      case 'srt':
        return parseSrt(content);
      case 'vtt':
        return parseVtt(content);
      default:
        throw UnsupportedError(
          'Unsupported subtitle format: .$extension. '
          'Only .srt and .vtt are supported.',
        );
    }
  }

  /// Parses raw SRT content into a sorted list of [SubtitleBlock]s.
  ///
  /// Each SRT cue is expected in the form:
  /// ```
  /// 1
  /// 00:00:01,000 --> 00:00:04,000
  /// First line of text
  /// Optional second line
  /// ```
  static List<SubtitleBlock> parseSrt(String content) {
    final blocks = <SubtitleBlock>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final cues = normalized.split(RegExp(r'\n\n+'));

    for (final cue in cues) {
      final lines = cue.trim().split('\n');
      if (lines.length < 2) continue;

      // Find the line that contains the timestamp arrow.
      int? tsLineIndex;
      Match? tsMatch;
      for (var i = 0; i < lines.length; i++) {
        final m = _timestampRegex.firstMatch(lines[i]);
        if (m != null) {
          tsLineIndex = i;
          tsMatch = m;
          break;
        }
      }
      if (tsLineIndex == null || tsMatch == null) continue;

      final startTime = _parseTimestamp(tsMatch);
      final endTime = _parseTimestamp(tsMatch, end: true);

      // Text lines follow the timestamp line.
      final textLines = lines
          .sublist(tsLineIndex + 1)
          .map((l) => _stripHtmlTags(l.trim()))
          .where((l) => l.isNotEmpty)
          .toList();
      if (textLines.isEmpty) continue;

      blocks.add(SubtitleBlock(
        startTime: startTime,
        endTime: endTime,
        text: textLines.join(' '),
      ));
    }

    blocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    return blocks;
  }

  /// Parses raw WebVTT content into a sorted list of [SubtitleBlock]s.
  ///
  /// Automatically skips:
  /// - The `WEBVTT` header line (and optional metadata below it).
  /// - `NOTE` comment blocks.
  /// - `STYLE` blocks.
  static List<SubtitleBlock> parseVtt(String content) {
    final blocks = <SubtitleBlock>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Remove the WEBVTT header block (everything up to the first blank line).
    final headerEnd = normalized.indexOf('\n\n');
    final body = headerEnd == -1 ? normalized : normalized.substring(headerEnd);

    final cues = body.split(RegExp(r'\n\n+'));

    for (final cue in cues) {
      final trimmed = cue.trim();
      if (trimmed.isEmpty) continue;

      // Skip NOTE and STYLE blocks.
      if (trimmed.startsWith('NOTE') || trimmed.startsWith('STYLE')) continue;

      final lines = trimmed.split('\n');

      // Find the timestamp line.
      int? tsLineIndex;
      Match? tsMatch;
      for (var i = 0; i < lines.length; i++) {
        final m = _timestampRegex.firstMatch(lines[i]);
        if (m != null) {
          tsLineIndex = i;
          tsMatch = m;
          break;
        }
      }
      if (tsLineIndex == null || tsMatch == null) continue;

      final startTime = _parseTimestamp(tsMatch);
      final endTime = _parseTimestamp(tsMatch, end: true);

      // Text lines follow the timestamp line.
      final textLines = lines
          .sublist(tsLineIndex + 1)
          .map((l) => _stripHtmlTags(l.trim()))
          .where((l) => l.isNotEmpty)
          .toList();
      if (textLines.isEmpty) continue;

      blocks.add(SubtitleBlock(
        startTime: startTime,
        endTime: endTime,
        text: textLines.join(' '),
      ));
    }

    blocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    return blocks;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Reads [file] as UTF-8 first. If that fails with a [FormatException],
  /// falls back to decoding the raw bytes as `windows-1252`.
  static Future<String> _readWithFallback(File file) async {
    try {
      return await file.readAsString(encoding: utf8);
    } on FormatException {
      // UTF-8 decode failed — try windows-1252.
      final bytes = await file.readAsBytes();
      return await CharsetConverter.decode('windows-1252', bytes);
    }
  }

  /// Converts the matched groups of [_timestampRegex] into a [Duration].
  ///
  /// When [end] is `false` (default), groups 1–4 are used (start timestamp).
  /// When [end] is `true`, groups 5–8 are used (end timestamp).
  static Duration _parseTimestamp(Match match, {bool end = false}) {
    final offset = end ? 4 : 0;
    final hours = int.parse(match.group(1 + offset)!);
    final minutes = int.parse(match.group(2 + offset)!);
    final seconds = int.parse(match.group(3 + offset)!);
    final milliseconds = int.parse(match.group(4 + offset)!);

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// Removes all HTML / styling tags (e.g. `<b>`, `<i>`, `<font ...>`) from
  /// [text], returning plain content only.
  static String _stripHtmlTags(String text) {
    return text.replaceAll(_htmlTagRegex, '').trim();
  }
}
