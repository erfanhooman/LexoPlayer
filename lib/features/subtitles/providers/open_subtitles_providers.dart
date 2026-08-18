import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexo_player/features/subtitles/models/open_subtitle_item.dart';
import 'package:lexo_player/features/subtitles/services/open_subtitles_service.dart';
import 'package:lexo_player/features/subtitles/logic/video_filename_parser.dart';

const String _kOpenSubtitlesLangKey = 'opensubtitles_language';

/// Provider for the [OpenSubtitlesService] instance.
final openSubtitlesServiceProvider = Provider<OpenSubtitlesService>((ref) {
  return OpenSubtitlesService();
});

/// Currently selected OpenSubtitles target language code (e.g. 'fa', 'en', 'es').
final openSubtitlesLanguageProvider = StateProvider<String>((ref) => 'fa');

/// Hydrates saved OpenSubtitles language preference from storage.
Future<void> hydrateOpenSubtitlesLanguage(WidgetRef ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString(_kOpenSubtitlesLangKey);
    if (lang != null && lang.isNotEmpty) {
      ref.read(openSubtitlesLanguageProvider.notifier).state = lang;
    }
  } catch (_) {}
}

/// Saves chosen OpenSubtitles language preference to storage.
Future<void> saveOpenSubtitlesLanguage(String code) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOpenSubtitlesLangKey, code);
  } catch (_) {}
}

/// Current search query string.
final openSubtitlesQueryProvider = StateProvider<String>((ref) => '');

/// Current video file's parsed metadata.
final openSubtitlesParsedMetadataProvider =
    StateProvider<ParsedVideoMetadata?>((ref) => null);

/// ID of subtitle item currently being downloaded (or `null` if idle).
final openSubtitlesDownloadingIdProvider = StateProvider<String?>((ref) => null);

/// Search state model for OpenSubtitles search results dialog.
class OpenSubtitlesSearchState {
  final bool isLoading;
  final String? errorMessage;
  final List<OpenSubtitleItem> items;

  const OpenSubtitlesSearchState({
    this.isLoading = false,
    this.errorMessage,
    this.items = const [],
  });

  OpenSubtitleItem? get recommendedItem {
    final found = items.where((i) => i.isRecommended);
    return found.isNotEmpty ? found.first : (items.isNotEmpty ? items.first : null);
  }
}

/// StateNotifier managing OpenSubtitles search executions.
class OpenSubtitlesSearchNotifier extends StateNotifier<OpenSubtitlesSearchState> {
  final Ref _ref;

  OpenSubtitlesSearchNotifier(this._ref) : super(const OpenSubtitlesSearchState());

  Future<void> search({String? customQuery, String? customLang}) async {
    final service = _ref.read(openSubtitlesServiceProvider);
    final String? rawQuery = customQuery ?? _ref.read(openSubtitlesQueryProvider);
    final String query = (rawQuery ?? '').trim();
    final String lang = customLang ?? _ref.read(openSubtitlesLanguageProvider);
    final metadata = _ref.read(openSubtitlesParsedMetadataProvider);

    if (query.isEmpty) {
      state = const OpenSubtitlesSearchState(items: []);
      return;
    }

    state = const OpenSubtitlesSearchState(isLoading: true);

    try {
      final results = await service.searchSubtitles(
        query: query,
        languageCode: lang,
        metadata: metadata,
      );

      state = OpenSubtitlesSearchState(
        isLoading: false,
        items: results,
      );
    } catch (e) {
      state = OpenSubtitlesSearchState(
        isLoading: false,
        errorMessage: 'Failed to search OpenSubtitles: $e',
        items: const [],
      );
    }
  }
}

/// Provider for managing OpenSubtitles search execution state.
final openSubtitlesSearchProvider =
    StateNotifierProvider.autoDispose<OpenSubtitlesSearchNotifier, OpenSubtitlesSearchState>(
  (ref) => OpenSubtitlesSearchNotifier(ref),
);
