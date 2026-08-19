class OpenSubtitleItem {
  final String id;
  final int? fileId;
  final String fileName;
  final String language;
  final String languageName;
  final String release;
  final int downloadCount;
  final double rating;
  final String? downloadUrl;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? year;
  final double matchScore;
  final bool isRecommended;

  const OpenSubtitleItem({
    required this.id,
    this.fileId,
    required this.fileName,
    required this.language,
    required this.languageName,
    required this.release,
    this.downloadCount = 0,
    this.rating = 0.0,
    this.downloadUrl,
    this.seasonNumber,
    this.episodeNumber,
    this.year,
    this.matchScore = 0.0,
    this.isRecommended = false,
  });

  OpenSubtitleItem copyWith({
    String? id,
    int? fileId,
    String? fileName,
    String? language,
    String? languageName,
    String? release,
    int? downloadCount,
    double? rating,
    String? downloadUrl,
    int? seasonNumber,
    int? episodeNumber,
    int? year,
    double? matchScore,
    bool? isRecommended,
  }) {
    return OpenSubtitleItem(
      id: id ?? this.id,
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      language: language ?? this.language,
      languageName: languageName ?? this.languageName,
      release: release ?? this.release,
      downloadCount: downloadCount ?? this.downloadCount,
      rating: rating ?? this.rating,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      year: year ?? this.year,
      matchScore: matchScore ?? this.matchScore,
      isRecommended: isRecommended ?? this.isRecommended,
    );
  }

  factory OpenSubtitleItem.fromJson(Map<String, dynamic> json) {
    // 1. Check rest.opensubtitles.org schema
    if (json.containsKey('IDSubtitle') || json.containsKey('SubFileName')) {
      final subFileName = json['SubFileName']?.toString() ?? 'Subtitle.srt';
      final release =
          (json['MovieReleaseName']?.toString() ?? subFileName).trim();
      final id = json['IDSubtitle']?.toString() ??
          json['IDSubtitleFile']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final fileId = int.tryParse(json['IDSubtitleFile']?.toString() ?? '');
      final lang = json['ISO639']?.toString() ??
          json['SubLanguageID']?.toString() ??
          'en';
      final langName = json['LanguageName']?.toString() ?? 'English';
      final dlCnt =
          int.tryParse(json['SubDownloadsCnt']?.toString() ?? '0') ?? 0;
      final rating =
          double.tryParse(json['SubRating']?.toString() ?? '0.0') ?? 0.0;
      final dlUrl = json['SubDownloadLink']?.toString() ??
          json['ZipDownloadLink']?.toString();
      final season = int.tryParse(json['SeriesSeason']?.toString() ?? '');
      final episode = int.tryParse(json['SeriesEpisode']?.toString() ?? '');
      final year = int.tryParse(json['MovieYear']?.toString() ?? '');

      return OpenSubtitleItem(
        id: id,
        fileId: fileId,
        fileName: subFileName.isNotEmpty ? subFileName : release,
        language: lang,
        languageName: langName,
        release: release.isNotEmpty ? release : subFileName,
        downloadCount: dlCnt,
        rating: rating,
        downloadUrl: dlUrl,
        seasonNumber: (season != null && season > 0) ? season : null,
        episodeNumber: (episode != null && episode > 0) ? episode : null,
        year: (year != null && year > 1900) ? year : null,
      );
    }

    // 2. Fallback to api.opensubtitles.com schema
    final attributes = json['attributes'] as Map<String, dynamic>? ?? json;

    final filesList = attributes['files'] as List<dynamic>? ?? [];
    int? fileId;
    String fileName = attributes['release']?.toString() ?? 'Subtitle';

    if (filesList.isNotEmpty && filesList.first is Map) {
      final firstFile = filesList.first as Map<String, dynamic>;
      fileId = firstFile['file_id'] as int?;
      if (firstFile['file_name'] != null) {
        fileName = firstFile['file_name'].toString();
      }
    }

    final featureDetails =
        attributes['feature_details'] as Map<String, dynamic>? ?? {};

    return OpenSubtitleItem(
      id: json['id']?.toString() ??
          attributes['subtitle_id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      fileId: fileId,
      fileName: fileName,
      language: attributes['language']?.toString() ?? 'en',
      languageName: attributes['language_name']?.toString() ??
          attributes['language']?.toString() ??
          'English',
      release: attributes['release']?.toString() ?? fileName,
      downloadCount: (attributes['download_count'] as num?)?.toInt() ?? 0,
      rating: (attributes['ratings'] as num?)?.toDouble() ??
          (attributes['rating'] as num?)?.toDouble() ??
          0.0,
      downloadUrl: attributes['url']?.toString(),
      seasonNumber: (featureDetails['season_number'] as num?)?.toInt() ??
          (attributes['season_number'] as num?)?.toInt(),
      episodeNumber: (featureDetails['episode_number'] as num?)?.toInt() ??
          (attributes['episode_number'] as num?)?.toInt(),
      year: (featureDetails['year'] as num?)?.toInt() ??
          (attributes['year'] as num?)?.toInt(),
    );
  }

  String get formattedEpisodeInfo {
    if (seasonNumber != null && episodeNumber != null) {
      return 'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
    } else if (year != null) {
      return '($year)';
    }
    return '';
  }
}
