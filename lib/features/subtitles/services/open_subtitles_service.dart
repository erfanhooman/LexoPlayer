import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:lexo_player/features/subtitles/models/open_subtitle_item.dart';
import 'package:lexo_player/features/subtitles/logic/video_filename_parser.dart';
import 'package:lexo_player/features/subtitles/logic/subtitle_parser.dart';

class SubtitleLanguageOption {
  final String code;
  final String englishName;
  final String nativeName;

  const SubtitleLanguageOption({
    required this.code,
    required this.englishName,
    required this.nativeName,
  });

  String get displayName => '$nativeName ($englishName)';
}

const List<SubtitleLanguageOption> kSupportedSubtitleLanguages = [
  SubtitleLanguageOption(code: 'fa', englishName: 'Persian / Farsi', nativeName: 'فارسی'),
  SubtitleLanguageOption(code: 'en', englishName: 'English', nativeName: 'English'),
  SubtitleLanguageOption(code: 'es', englishName: 'Spanish', nativeName: 'Español'),
  SubtitleLanguageOption(code: 'fr', englishName: 'French', nativeName: 'Français'),
  SubtitleLanguageOption(code: 'de', englishName: 'German', nativeName: 'Deutsch'),
  SubtitleLanguageOption(code: 'ar', englishName: 'Arabic', nativeName: 'العربية'),
  SubtitleLanguageOption(code: 'tr', englishName: 'Turkish', nativeName: 'Türkçe'),
  SubtitleLanguageOption(code: 'ru', englishName: 'Russian', nativeName: 'Русский'),
  SubtitleLanguageOption(code: 'it', englishName: 'Italian', nativeName: 'Italiano'),
  SubtitleLanguageOption(code: 'pt', englishName: 'Portuguese', nativeName: 'Português'),
  SubtitleLanguageOption(code: 'zh', englishName: 'Chinese', nativeName: '中文'),
  SubtitleLanguageOption(code: 'ko', englishName: 'Korean', nativeName: '한국어'),
  SubtitleLanguageOption(code: 'ja', englishName: 'Japanese', nativeName: '日本語'),
];

class OpenSubtitlesService {
  final Dio _dio;

  OpenSubtitlesService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.opensubtitles.com/api/v1',
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent': 'LexoPlayer v1.0.0',
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  static String _mapLanguageTo3LetterCode(String code) {
    switch (code.toLowerCase()) {
      case 'fa':
        return 'per';
      case 'en':
        return 'eng';
      case 'es':
        return 'spa';
      case 'fr':
        return 'fre';
      case 'de':
        return 'ger';
      case 'ar':
        return 'ara';
      case 'tr':
        return 'tur';
      case 'ru':
        return 'rus';
      case 'it':
        return 'ita';
      case 'pt':
        return 'por';
      case 'zh':
        return 'chi';
      case 'ko':
        return 'kor';
      case 'ja':
        return 'jpn';
      default:
        return code;
    }
  }

  /// Search OpenSubtitles for candidate subtitles matching query and metadata.
  Future<List<OpenSubtitleItem>> searchSubtitles({
    required String query,
    required String languageCode,
    ParsedVideoMetadata? metadata,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    List<OpenSubtitleItem> results = [];
    final sub3Lang = _mapLanguageTo3LetterCode(languageCode);
    final formattedQuery = Uri.encodeComponent(cleanQuery.toLowerCase().replaceAll(RegExp(r'\s+'), '+')).replaceAll('%2B', '+');
    final restDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent': 'TemporaryUserAgent',
        },
      ),
    );

    // 1. Primary: Query rest.opensubtitles.org public REST API (No API key required)
    try {
      final restUrl = 'https://rest.opensubtitles.org/search/query-$formattedQuery/sublanguageid-$sub3Lang';
      developer.log('Searching rest.opensubtitles.org: $restUrl', name: 'OpenSubtitlesService');
      final response = await restDio.get<dynamic>(restUrl);

      if (response.statusCode == 200 && response.data != null && response.data is List) {
        final list = response.data as List<dynamic>;
        for (final itemJson in list) {
          if (itemJson is Map<String, dynamic>) {
            try {
              final item = OpenSubtitleItem.fromJson(itemJson);
              results.add(item);
            } catch (e) {
              developer.log('Error parsing rest item: $e', name: 'OpenSubtitlesService');
            }
          }
        }
      }
    } catch (e) {
      developer.log('rest.opensubtitles.org search failed: $e', name: 'OpenSubtitlesService');
    }

    // 2. Secondary fallback: api.opensubtitles.com
    if (results.isEmpty) {
      final queryParams = <String, dynamic>{
        'query': cleanQuery,
        'languages': languageCode,
        'order_by': 'download_count',
      };

      if (metadata != null) {
        if (metadata.season != null) queryParams['season_number'] = metadata.season;
        if (metadata.episode != null) queryParams['episode_number'] = metadata.episode;
      }

      try {
        final response = await _dio.get('/subtitles', queryParameters: queryParams);
        if (response.statusCode == 200 && response.data != null) {
          final data = response.data['data'];
          if (data is List) {
            for (final itemJson in data) {
              if (itemJson is Map<String, dynamic>) {
                try {
                  final item = OpenSubtitleItem.fromJson(itemJson);
                  results.add(item);
                } catch (_) {}
              }
            }
          }
        }
      } catch (e) {
        developer.log('api.opensubtitles.com search failed: $e', name: 'OpenSubtitlesService');
      }
    }

    // Score and rank candidates
    results = _scoreAndRankCandidates(results, cleanQuery, metadata);

    return results;
  }

  /// Score candidates based on episode match, release tags, rating, and download count.
  List<OpenSubtitleItem> _scoreAndRankCandidates(
    List<OpenSubtitleItem> items,
    String searchTitle,
    ParsedVideoMetadata? metadata,
  ) {
    if (items.isEmpty) return [];

    final scoredList = <OpenSubtitleItem>[];

    for (final item in items) {
      double score = 0.0;

      // Base rating & download count score
      score += (item.rating * 6.0);
      score += (item.downloadCount / 1000.0).clamp(0.0, 25.0);

      // Match Season & Episode
      if (metadata != null && metadata.isTVShow) {
        final s = metadata.season;
        final e = metadata.episode;

        if (item.seasonNumber == s && item.episodeNumber == e) {
          score += 120.0;
        } else if (item.seasonNumber != null && item.seasonNumber != s) {
          score -= 150.0; // WRONG SEASON PENALTY
        } else if (item.episodeNumber != null && item.episodeNumber != e) {
          score -= 120.0; // WRONG EPISODE PENALTY
        }

        final epStr = 's${s.toString().padLeft(2, '0')}e${e.toString().padLeft(2, '0')}';
        final releaseLower = item.release.toLowerCase();
        final fileLower = item.fileName.toLowerCase();

        if (releaseLower.contains(epStr) || fileLower.contains(epStr)) {
          score += 80.0;
        }
      }

      // Match Year
      if (metadata != null && metadata.year != null && item.year == metadata.year) {
        score += 40.0;
      }

      // Match quality tokens
      if (metadata != null && metadata.qualityTokens.isNotEmpty) {
        final releaseLower = item.release.toLowerCase();
        for (final token in metadata.qualityTokens) {
          if (releaseLower.contains(token)) {
            score += 15.0;
          }
        }
      }

      // Match release group / title similarity
      final cleanSearchTitle = searchTitle.toLowerCase();
      if (item.release.toLowerCase().contains(cleanSearchTitle)) {
        score += 35.0;
      }

      scoredList.add(item.copyWith(matchScore: score));
    }

    // Sort by match score descending
    scoredList.sort((a, b) => b.matchScore.compareTo(a.matchScore));

    // Mark top candidate as recommended
    if (scoredList.isNotEmpty) {
      final topItem = scoredList.first;
      scoredList[0] = topItem.copyWith(isRecommended: true);
    }

    return scoredList;
  }

  /// Download subtitle file (handles direct URL, gzip, zip archives, or raw SRT).
  Future<String> downloadSubtitle(OpenSubtitleItem item, {Directory? targetDir}) async {
    developer.log('Downloading subtitle: ${item.fileName} (fileId: ${item.fileId})',
        name: 'OpenSubtitlesService');

    String? downloadUrl = item.downloadUrl;

    // If file_id is available and downloadUrl is missing, request download link from OpenSubtitles
    if (item.fileId != null) {
      try {
        final resp = await _dio.post('/download', data: {'file_id': item.fileId});
        if (resp.statusCode == 200 && resp.data != null && resp.data['link'] != null) {
          downloadUrl = resp.data['link'].toString();
        }
      } catch (e) {
        developer.log('POST /download link retrieval failed: $e. Falling back to direct URL.',
            name: 'OpenSubtitlesService');
      }
    }

    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception('No valid download link found for this subtitle.');
    }

    final response = await _dio.get<List<int>>(
      downloadUrl,
      options: Options(responseType: ResponseType.bytes),
    );

    if (response.data == null || response.data!.isEmpty) {
      throw Exception('Empty download payload received.');
    }

    final bytes = Uint8List.fromList(response.data!);
    List<int> subtitleContentBytes = bytes;

    // Check GZIP signature (0x1F, 0x8B)
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      developer.log('Decompressing GZIP subtitle payload...', name: 'OpenSubtitlesService');
      subtitleContentBytes = GZipDecoder().decodeBytes(bytes);
    }
    // Check ZIP signature (PK\x03\x04)
    else if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      developer.log('Decompressing ZIP archive payload...', name: 'OpenSubtitlesService');
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (!file.isFile) continue;
        if (SubtitleParser.isSupportedSubtitleFile(file.name)) {
          subtitleContentBytes = file.content as List<int>;
          break;
        }
      }
    }

    final Directory subDir;
    if (targetDir != null) {
      subDir = targetDir;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      subDir = Directory(path.join(appDir.path, 'LexoPlayer', 'Subtitles'));
    }

    if (!await subDir.exists()) {
      await subDir.create(recursive: true);
    }

    // Generate clean file name while preserving the subtitle extension. When
    // the name carries no recognized subtitle extension, sniff the payload so
    // downloaded .ass/.ssa (or mislabeled) files are not saved as .srt.
    String safeName = item.fileName.replaceAll(RegExp(r'[^\w\.-]'), '_');
    if (!SubtitleParser.isSupportedSubtitleFile(safeName)) {
      final detectedExt = _sniffSubtitleExtension(subtitleContentBytes);
      safeName = '$safeName$detectedExt';
    }

    final targetFile = File(path.join(subDir.path, '${item.id}_$safeName'));
    await targetFile.writeAsBytes(subtitleContentBytes, flush: true);

    developer.log('Saved downloaded subtitle to: ${targetFile.path}',
        name: 'OpenSubtitlesService');

    return targetFile.path;
  }

  /// Sniffs a subtitle file extension from raw bytes without decoding fully.
  static String _sniffSubtitleExtension(List<int> bytes) {
    try {
      final head = latin1.decode(bytes.sublist(0, bytes.length < 4096 ? bytes.length : 4096));
      switch (SubtitleParser.detectFormat(head)) {
        case SubtitleFormat.webVtt:
          return '.vtt';
        case SubtitleFormat.ass:
          return '.ass';
        case SubtitleFormat.srt:
          return '.srt';
      }
    } catch (_) {}
    return '.srt';
  }
}
