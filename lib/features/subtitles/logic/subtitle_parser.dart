import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:lexo_player/core/models/subtitle_block.dart';

/// Subtitle container formats supported by [SubtitleParser].
enum SubtitleFormat {
  srt,
  webVtt,
  ass;

  /// Maps a file extension to a format, or `null` when the extension is unknown.
  static SubtitleFormat? fromExtension(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'srt':
        return SubtitleFormat.srt;
      case 'vtt':
        return SubtitleFormat.webVtt;
      case 'ass':
      case 'ssa':
        return SubtitleFormat.ass;
      default:
        return null;
    }
  }
}

/// A robust parser for SRT, WebVTT, and ASS/SSA subtitle files.
class SubtitleParser {
  SubtitleParser._();

  /// Flexible regex matching SRT (`00:01:23,456` or `0:01:23,456` or `01:23.456`)
  /// and WebVTT timestamp arrows.
  static final RegExp _timestampRegex = RegExp(
    r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[,\.](\d{1,3})\s*-->\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[,\.](\d{1,3})',
  );

  /// ASS/SSA timestamp pattern (`H:MM:SS.CC` — centiseconds).
  static final RegExp _assTimeRegex =
      RegExp(r'(\d+):(\d{1,2}):(\d{1,2})[.,](\d{1,3})');

  /// HTML / styling tag pattern used to clean subtitle text.
  static final RegExp _htmlTagRegex = RegExp(r'<[^>]+>');

  /// Recognized subtitle file extensions.
  static const List<String> supportedExtensions = [
    '.srt',
    '.vtt',
    '.ass',
    '.ssa'
  ];

  /// Returns `true` when [filePath] points at a recognized subtitle file.
  static bool isSupportedSubtitleFile(String filePath) {
    final lower = filePath.toLowerCase();
    return supportedExtensions.any((e) => lower.endsWith(e));
  }

  /// Parses a subtitle file at [filePath].
  static Future<List<SubtitleBlock>> parseFile(String filePath) async {
    final file = File(filePath);
    final content = await _readWithFallback(file);
    if (content.trim().isEmpty) return [];

    // Prefer the extension, but fall back to content sniffing so files with
    // missing/misleading extensions still load correctly.
    final format =
        SubtitleFormat.fromExtension(filePath) ?? detectFormat(content);

    switch (format) {
      case SubtitleFormat.srt:
        return parseSrt(content);
      case SubtitleFormat.webVtt:
        return parseVtt(content);
      case SubtitleFormat.ass:
        return parseAss(content);
    }
  }

  /// Detects the subtitle format from raw content (extension-independent).
  static SubtitleFormat detectFormat(String content) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('WEBVTT')) return SubtitleFormat.webVtt;

    final lower = trimmed.toLowerCase();
    if ((lower.contains('[script info]') || lower.contains('[events]')) &&
        (lower.contains('dialogue:') || lower.contains('format:'))) {
      return SubtitleFormat.ass;
    }

    return SubtitleFormat.srt;
  }

  /// Parses raw SRT content into a sorted list of [SubtitleBlock]s using sequential line scanning.
  static List<SubtitleBlock> parseSrt(String content) {
    if (content.trim().isEmpty) return [];

    final blocks = <SubtitleBlock>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalized.split('\n');

    Duration? currentStart;
    Duration? currentEnd;
    final currentTextLines = <String>[];

    void flush() {
      if (currentStart != null &&
          currentEnd != null &&
          currentTextLines.isNotEmpty) {
        _addBlock(
            blocks, currentStart!, currentEnd!, currentTextLines.join(' '));
      }
      currentStart = null;
      currentEnd = null;
      currentTextLines.clear();
    }

    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i].trim();
      final match = _timestampRegex.firstMatch(line);

      if (match != null) {
        flush();
        currentStart = _parseTimestamp(match, end: false);
        currentEnd = _parseTimestamp(match, end: true);
      } else if (currentStart != null && currentEnd != null) {
        if (line.isEmpty) {
          flush();
        } else if (!RegExp(r'^\d+$').hasMatch(line)) {
          currentTextLines.add(line);
        }
      }
    }

    flush();

    blocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    return blocks;
  }

  /// Parses raw WebVTT content into a sorted list of [SubtitleBlock]s.
  static List<SubtitleBlock> parseVtt(String content) {
    if (content.trim().isEmpty) return [];

    final blocks = <SubtitleBlock>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final headerEnd = normalized.indexOf('\n\n');
    final body = headerEnd == -1 ? normalized : normalized.substring(headerEnd);

    final rawLines = body.split('\n');

    Duration? currentStart;
    Duration? currentEnd;
    final currentTextLines = <String>[];

    void flush() {
      if (currentStart != null &&
          currentEnd != null &&
          currentTextLines.isNotEmpty) {
        _addBlock(
            blocks, currentStart!, currentEnd!, currentTextLines.join(' '));
      }
      currentStart = null;
      currentEnd = null;
      currentTextLines.clear();
    }

    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i].trim();

      // Header / metadata blocks are only annotations *outside* of a cue.
      if (line.startsWith('WEBVTT')) continue;
      if (currentStart == null &&
          (line.startsWith('NOTE') ||
              line.startsWith('STYLE') ||
              line.startsWith('REGION'))) {
        continue;
      }

      final match = _timestampRegex.firstMatch(line);

      if (match != null) {
        flush();
        currentStart = _parseTimestamp(match, end: false);
        currentEnd = _parseTimestamp(match, end: true);
      } else if (currentStart != null && currentEnd != null) {
        if (line.isEmpty) {
          flush();
        } else {
          currentTextLines.add(line);
        }
      }
    }

    flush();

    blocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    return blocks;
  }

  /// Parses raw ASS/SSA content into a sorted list of [SubtitleBlock]s.
  ///
  /// Only `[Events]` section `Dialogue:` lines are considered; `Comment:` and
  /// `[V4+ Styles]`/`[Script Info]` sections are ignored. The field layout is
  /// taken from the `Format:` line when present, falling back to the standard
  /// ASS layout when it is not.
  static List<SubtitleBlock> parseAss(String content) {
    if (content.trim().isEmpty) return [];

    final blocks = <SubtitleBlock>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');

    bool inEvents = false;
    List<String> eventFields = const [];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();

      if (line.startsWith('[')) {
        inEvents = lower.startsWith('[events]');
        eventFields = const [];
        continue;
      }

      if (!inEvents) continue;

      if (lower.startsWith('format:')) {
        eventFields = line
            .substring('format:'.length)
            .split(',')
            .map((f) => f.trim().toLowerCase())
            .where((f) => f.isNotEmpty)
            .toList();
        continue;
      }

      if (!lower.startsWith('dialogue:')) continue;

      final body = line.substring(line.indexOf(':') + 1).trim();
      if (body.isEmpty) continue;

      // Locate the comma separating the header fields from the free-form text.
      final fields = eventFields.isNotEmpty
          ? eventFields
          : const [
              'layer',
              'start',
              'end',
              'style',
              'name',
              'marginl',
              'marginr',
              'marginv',
              'effect',
              'text',
            ];
      final textIndex = fields.indexOf('text');
      if (textIndex < 0) continue;

      int commaIndex = -1;
      for (int i = 0; i < textIndex; i++) {
        commaIndex = body.indexOf(',', commaIndex + 1);
        if (commaIndex == -1) break;
      }
      if (commaIndex == -1) continue;

      final head = body.substring(0, commaIndex).split(',');
      final text = body.substring(commaIndex + 1);

      Duration? start;
      Duration? end;
      for (int i = 0; i < head.length && i < fields.length; i++) {
        final field = fields[i];
        final value = head[i].trim();
        if (field == 'start') {
          start = _parseAssTime(value);
        } else if (field == 'end') {
          end = _parseAssTime(value);
        }
      }
      if (start == null || end == null) continue;

      _addBlock(blocks, start, end, text);
    }

    blocks.sort((a, b) => a.startTime.compareTo(b.startTime));
    return blocks;
  }

  /// Validates and appends a cue, skipping empty or reversed-time blocks.
  static void _addBlock(
    List<SubtitleBlock> blocks,
    Duration start,
    Duration end,
    String rawText,
  ) {
    final text = cleanSubtitleText(rawText);
    if (text.isEmpty) return;
    if (end.compareTo(start) <= 0) return;
    blocks.add(SubtitleBlock(startTime: start, endTime: end, text: text));
  }

  /// Converts an ASS/SSA timestamp (`H:MM:SS.CC`) into a [Duration].
  static Duration? _parseAssTime(String raw) {
    final match = _assTimeRegex.firstMatch(raw);
    if (match == null) return null;

    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
    final msRaw = match.group(4) ?? '';
    final milliseconds =
        int.tryParse(msRaw.padRight(3, '0').substring(0, 3)) ?? 0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// Reads [file] with multi-tier encoding fallback.
  ///
  /// Handles UTF-8, UTF-8 BOM, UTF-16 LE/BE (with BOM), Windows-1256 (Persian /
  /// Arabic ANSI), Windows-1251 (Cyrillic), Windows-1252 (Western European), and
  /// finally lenient UTF-8.
  static Future<String> _readWithFallback(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return '';

    // UTF-8 BOM.
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return _decodeUtf8(bytes.sublist(3)) ?? '';
    }

    // UTF-16 LE (FF FE) / BE (FE FF) BOM.
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes, littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes, littleEndian: false);
    }

    // 1. Strict UTF-8.
    final utf8Decoded = _decodeUtf8(bytes);
    if (utf8Decoded != null) return utf8Decoded;

    // 2. Single-byte fallbacks, ordered by how likely they are to appear in
    //    subtitle files. The Persian/Windows-1256 case comes first so Persian
    //    SRT files that used to show nothing now decode correctly.
    const fallbacks = [
      'windows-1256', // Arabic / Persian
      'windows-1251', // Cyrillic
      'windows-1252', // Western European / Latin-1
    ];
    for (final encoding in fallbacks) {
      try {
        final decoded = await CharsetConverter.decode(encoding, bytes);
        if (decoded.isNotEmpty && !decoded.contains('\uFFFD')) {
          return decoded;
        }
      } catch (_) {}
    }

    // 3. Final fallback: lenient UTF-8.
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Decodes [bytes] as strict UTF-8, returning `null` on failure.
  static String? _decodeUtf8(Uint8List bytes) {
    try {
      final decoded = utf8.decode(bytes, allowMalformed: false);
      if (!decoded.contains('\uFFFD')) return decoded;
    } catch (_) {}
    return null;
  }

  /// Decodes UTF-16 content (including its BOM) in the given byte order.
  static Future<String> _decodeUtf16(
    Uint8List bytes, {
    required bool littleEndian,
  }) async {
    try {
      final decoded = await CharsetConverter.decode(
          littleEndian ? 'utf-16le' : 'utf-16be', bytes);
      if (decoded.isNotEmpty && !decoded.contains('\uFFFD')) return decoded;
    } catch (_) {}

    // Manual fallback: skip the 2-byte BOM and decode the remaining code units.
    final codeUnits = <int>[];
    for (int i = 2; i + 1 < bytes.length; i += 2) {
      codeUnits.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }

  /// Converts matched groups of [_timestampRegex] into a [Duration].
  static Duration _parseTimestamp(Match match, {bool end = false}) {
    // Regex groups:
    // Start: g1=hours?, g2=mins, g3=secs, g4=ms
    // End: g5=hours?, g6=mins, g7=secs, g8=ms
    final offset = end ? 4 : 0;

    final hoursStr = match.group(1 + offset);
    final minsStr = match.group(2 + offset);
    final secsStr = match.group(3 + offset);
    final msStr = match.group(4 + offset);

    final hours = hoursStr != null ? int.parse(hoursStr) : 0;
    final minutes = int.parse(minsStr!);
    final seconds = int.parse(secsStr!);

    int milliseconds = 0;
    if (msStr != null && msStr.isNotEmpty) {
      final paddedMs = msStr.padRight(3, '0').substring(0, 3);
      milliseconds = int.parse(paddedMs);
    }

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  /// Cleans raw subtitle text.
  static String cleanSubtitleText(String text) {
    if (text.isEmpty) return '';

    return text
        .replaceAll(RegExp(r'\{[^}]*\}'), ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(_htmlTagRegex, ' ')
        .replaceAll(RegExp(r'(\\N|\\n|\\h|[\r\n\t])'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
