import 'package:path/path.dart' as path;

/// Metadata parsed from a video filename.
class ParsedVideoMetadata {
  final String rawFilename;
  final String cleanTitle;
  final int? season;
  final int? episode;
  final int? year;
  final List<String> qualityTokens;
  final String? releaseGroup;

  const ParsedVideoMetadata({
    required this.rawFilename,
    required this.cleanTitle,
    this.season,
    this.episode,
    this.year,
    this.qualityTokens = const [],
    this.releaseGroup,
  });

  bool get isTVShow => season != null && episode != null;

  String get formattedEpisodeStr => isTVShow
      ? 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}'
      : '';

  @override
  String toString() {
    if (isTVShow) {
      return '$cleanTitle $formattedEpisodeStr';
    } else if (year != null) {
      return '$cleanTitle ($year)';
    }
    return cleanTitle;
  }
}

/// Utility for parsing media file names into structured title, season, episode, and year metadata.
class VideoFilenameParser {
  VideoFilenameParser._();

  static const List<String> _noiseTokens = [
    '720p',
    '1080p',
    '2160p',
    '4k',
    'hdr',
    'hdr10',
    'hdtv',
    'web-dl',
    'webdl',
    'webrip',
    'web',
    'bluray',
    'bdrip',
    'brrip',
    'dvdrip',
    'dvd',
    'x264',
    'x265',
    'h264',
    'h265',
    'hevc',
    'avc',
    'aac',
    'dts',
    'ac3',
    '5.1',
    '7.1',
    '10bit',
    'subbed',
    'dubbed',
    'remastered',
    'extended',
    'proper',
    'repack',
    'unrated',
    'director',
    'cut',
    'yify',
    'rarbg',
    'eztv',
    'psa',
    'tgx',
    'ettv',
    'vxt'
  ];

  static ParsedVideoMetadata parse(String filePathOrName) {
    final filename = path.basename(filePathOrName);
    String basenameWithoutExt = path.basenameWithoutExtension(filename);

    int? season;
    int? episode;

    // Pattern 1: S01E05 or s1e5
    final sExRegex = RegExp(r'[sS](\d{1,2})[eE](\d{1,2})');
    final sExMatch = sExRegex.firstMatch(basenameWithoutExt);

    // Pattern 2: 1x05 or 01x05 (delimiters: dots, underscores, dashes, spaces)
    final xRegex =
        RegExp(r'(?:^|[._\-\s])(\d{1,2})[xX](\d{1,2})(?:[._\-\s]|$)');
    final xMatch =
        sExMatch == null ? xRegex.firstMatch(basenameWithoutExt) : null;

    if (sExMatch != null) {
      season = int.tryParse(sExMatch.group(1)!);
      episode = int.tryParse(sExMatch.group(2)!);
    } else if (xMatch != null) {
      season = int.tryParse(xMatch.group(1)!);
      episode = int.tryParse(xMatch.group(2)!);
    }

    final epMatch = sExMatch ?? xMatch;

    // Extract Year (e.g., 1999, 2023)
    int? year;
    final yearRegex = RegExp(r'\b(19\d\d|20\d\d)\b');
    final yearMatches = yearRegex.allMatches(basenameWithoutExt);
    for (final match in yearMatches) {
      final y = int.tryParse(match.group(0)!);
      if (y != null) {
        // If S01E05 or 1x05 was found before year, ignore year if it matches episode/season numbers
        if (epMatch != null && match.start >= epMatch.start) {
          continue;
        }
        year = y;
        break;
      }
    }

    // Collect quality tokens present in filename
    final lowerName = basenameWithoutExt.toLowerCase();
    final foundTokens = <String>[];
    for (final token in _noiseTokens) {
      if (lowerName.contains(token)) {
        foundTokens.add(token);
      }
    }

    // Cut off title at S01E05 / 1x05 or Year or quality noise marker
    String titlePart = basenameWithoutExt;
    if (epMatch != null) {
      titlePart = titlePart.substring(0, epMatch.start);
    } else if (year != null) {
      final yearMatch = yearRegex.firstMatch(titlePart);
      if (yearMatch != null && yearMatch.start > 2) {
        titlePart = titlePart.substring(0, yearMatch.start);
      }
    }

    // Clean delimiters (dots, underscores, dashes, brackets)
    String cleanTitle = titlePart
        .replaceAll(RegExp(r'[._\-\[\]\(\)]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // If clean title ends up empty (e.g. file was just named "S01E01.mp4"), fallback to clean basename
    if (cleanTitle.isEmpty) {
      cleanTitle = basenameWithoutExt
          .replaceAll(RegExp(r'[._\-\[\]\(\)]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    return ParsedVideoMetadata(
      rawFilename: filename,
      cleanTitle: cleanTitle,
      season: season,
      episode: episode,
      year: year,
      qualityTokens: foundTokens,
    );
  }
}
