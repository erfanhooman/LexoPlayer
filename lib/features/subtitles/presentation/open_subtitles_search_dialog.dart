import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/features/subtitles/models/open_subtitle_item.dart';
import 'package:lexo_player/features/subtitles/services/open_subtitles_service.dart';
import 'package:lexo_player/features/subtitles/providers/open_subtitles_providers.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/subtitles/logic/subtitle_parser.dart';
import 'package:lexo_player/features/subtitles/logic/video_filename_parser.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';

const _kOverlayBg = Color(0xE6141418); // 90% Midnight Charcoal
const _kScaffoldBg = Color(0xFF0C0C0E); // Midnight Charcoal Scaffold
const _kBorder = Color(0xFF25252B); // Sleek card border
const _kAccent = Color(0xFFFF5500); // Burnt Tangerine orange

class OpenSubtitlesSearchDialog extends ConsumerStatefulWidget {
  final String? initialUri;

  const OpenSubtitlesSearchDialog({super.key, this.initialUri});

  /// Presents the OpenSubtitles search panel adaptively.
  static void show(BuildContext context, {String? mediaUri}) {
    final isMobile = Platform.isAndroid ||
        Platform.isIOS ||
        MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _MobileSheetWrapper(
          child: OpenSubtitlesSearchDialog(initialUri: mediaUri),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          child: OpenSubtitlesSearchDialog(initialUri: mediaUri),
        ),
      );
    }
  }

  @override
  ConsumerState<OpenSubtitlesSearchDialog> createState() =>
      _OpenSubtitlesSearchDialogState();
}

class _OpenSubtitlesSearchDialogState
    extends ConsumerState<OpenSubtitlesSearchDialog> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await hydrateOpenSubtitlesLanguage(ref);

      // Determine media URI from argument or active player state
      String? uri = widget.initialUri;
      if (uri == null || uri.isEmpty) {
        final player = ref.read(playerProvider);
        final playlist = player.state.playlist;
        if (playlist.index >= 0 && playlist.index < playlist.medias.length) {
          uri = playlist.medias[playlist.index].uri;
        }
      }

      if (uri != null && uri.isNotEmpty) {
        final parsed = VideoFilenameParser.parse(uri);
        ref.read(openSubtitlesParsedMetadataProvider.notifier).state = parsed;
        ref.read(openSubtitlesQueryProvider.notifier).state = parsed.cleanTitle;
        _searchController.text = parsed.cleanTitle;
      }

      // Execute auto-search
      ref.read(openSubtitlesSearchProvider.notifier).search();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleDownload(OpenSubtitleItem item) async {
    final isPersian = ref.read(appLanguageProvider) == 'fa';
    ref.read(openSubtitlesDownloadingIdProvider.notifier).state = item.id;

    try {
      final service = ref.read(openSubtitlesServiceProvider);
      final localFilePath = await service.downloadSubtitle(item);

      // Parse downloaded SRT / VTT
      final blocks = await SubtitleParser.parseFile(localFilePath);

      if (blocks.isEmpty) {
        if (mounted) {
          ref.read(openSubtitlesDownloadingIdProvider.notifier).state = null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isPersian
                    ? 'هشدار: هیچ خط زیرنویسی در این فایل یافت نشد'
                    : 'Warning: Could not parse any subtitle cues from this file.',
              ),
              backgroundColor: Colors.amber.shade900,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final newOption = SubtitleTrackOption(
        id: 'opensub_${item.id}',
        name: '${item.fileName} (${item.languageName})',
        isExternal: true,
        filePath: localFilePath,
        externalBlocks: blocks,
      );

      // Add to external options list & select appropriately
      final currentExternal = ref.read(externalSubtitleOptionsProvider);
      ref.read(externalSubtitleOptionsProvider.notifier).state = [
        ...currentExternal,
        newOption,
      ];

      final currentPrimary = ref.read(selectedSubtitleProvider);
      final currentSecondary = ref.read(selectedSecondarySubtitleProvider);
      if (currentPrimary == null || currentPrimary.id == 'none') {
        ref.read(selectedSubtitleProvider.notifier).state = newOption;
      } else if (currentSecondary != null &&
          currentSecondary.id != 'none' &&
          currentSecondary.id == currentPrimary.id) {
        // Both slots currently show the same track. A newly downloaded track
        // should become the new primary while preserving the old track as the
        // secondary translation (the common Persian-primary/Persian-secondary
        // -> English-primary/Persian-secondary workflow).
        ref.read(selectedSubtitleProvider.notifier).state = newOption;
      } else {
        ref.read(selectedSecondarySubtitleProvider.notifier).state = newOption;
      }

      if (mounted) {
        ref.read(openSubtitlesDownloadingIdProvider.notifier).state = null;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isPersian
                        ? 'زیرنویس با موفقیت دریافت و فعال شد'
                        : 'Subtitle downloaded and applied successfully!',
                  ),
                ),
              ],
            ),
            backgroundColor: _kAccent,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ref.read(openSubtitlesDownloadingIdProvider.notifier).state = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPersian
                  ? 'خطا در دریافت زیرنویس: $e'
                  : 'Failed to download subtitle: $e',
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    final searchState = ref.watch(openSubtitlesSearchProvider);
    final selectedLangCode = ref.watch(openSubtitlesLanguageProvider);
    final metadata = ref.watch(openSubtitlesParsedMetadataProvider);
    final downloadingId = ref.watch(openSubtitlesDownloadingIdProvider);

    return Container(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
      decoration: BoxDecoration(
        color: _kOverlayBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Row ─────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _kAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _kAccent.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: _kAccent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isPersian
                              ? 'جستجوی خودکار زیرنویس (OpenSubtitles)'
                              : 'OpenSubtitles Auto Search',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Metadata Badge (Detected Show / Movie info) ────────────
                if (metadata != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kScaffoldBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          metadata.isTVShow
                              ? Icons.tv_rounded
                              : Icons.movie_rounded,
                          color: _kAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            metadata.toString(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (metadata.isTVShow)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: _kAccent.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              metadata.formattedEpisodeStr,
                              style: const TextStyle(
                                color: _kAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                // ── Language Dropdown & Search Query Input Row ────────────
                Row(
                  children: [
                    // Language Selector
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _kScaffoldBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedLangCode,
                          dropdownColor: _kOverlayBg,
                          borderRadius: BorderRadius.circular(12),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: _kAccent, size: 18),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          items: kSupportedSubtitleLanguages.map((lang) {
                            return DropdownMenuItem<String>(
                              value: lang.code,
                              child: Text(isPersian
                                  ? lang.nativeName
                                  : lang.englishName),
                            );
                          }).toList(),
                          onChanged: (newLang) {
                            if (newLang != null) {
                              ref
                                  .read(openSubtitlesLanguageProvider.notifier)
                                  .state = newLang;
                              saveOpenSubtitlesLanguage(newLang);
                              ref
                                  .read(openSubtitlesSearchProvider.notifier)
                                  .search();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Query Search Input
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: isPersian
                                ? 'نام فیلم یا سریال...'
                                : 'Movie or series title...',
                            hintStyle: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                            filled: true,
                            fillColor: _kScaffoldBg,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _kBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _kAccent),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search_rounded,
                                  color: _kAccent, size: 20),
                              onPressed: () {
                                ref
                                    .read(openSubtitlesQueryProvider.notifier)
                                    .state = _searchController.text;
                                ref
                                    .read(openSubtitlesSearchProvider.notifier)
                                    .search();
                              },
                            ),
                          ),
                          onSubmitted: (val) {
                            ref
                                .read(openSubtitlesQueryProvider.notifier)
                                .state = val;
                            ref
                                .read(openSubtitlesSearchProvider.notifier)
                                .search();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Results Body ───────────────────────────────────────────
                Expanded(
                  child: _buildResultsBody(
                      context, searchState, isPersian, downloadingId),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsBody(
    BuildContext context,
    OpenSubtitlesSearchState state,
    bool isPersian,
    String? downloadingId,
  ) {
    if (state.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(_kAccent),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isPersian
                  ? 'در حال جستجو در OpenSubtitles...'
                  : 'Searching OpenSubtitles...',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 36),
              const SizedBox(height: 10),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh_rounded,
                    size: 16, color: Colors.white),
                label: Text(isPersian ? 'تلاش مجدد' : 'Retry',
                    style: const TextStyle(color: Colors.white)),
                onPressed: () {
                  ref.read(openSubtitlesSearchProvider.notifier).search();
                },
              ),
            ],
          ),
        ),
      );
    }

    if (state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.subtitles_off_rounded,
                color: Colors.white.withValues(alpha: 0.3), size: 48),
            const SizedBox(height: 12),
            Text(
              isPersian ? 'زیرنویسی یافت نشد' : 'No subtitles found',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              isPersian
                  ? 'لطفا زبان یا کلمات کلیدی جستجو را تغییر دهید'
                  : 'Try changing the language or query above.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final recommended = state.recommendedItem;
    final otherItems =
        state.items.where((i) => i.id != recommended?.id).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Recommended Best Match Card ─────────────────────────
          if (recommended != null) ...[
            Text(
              isPersian ? 'بهترین تطبیق پیشنهادی' : 'Recommended Match',
              style: const TextStyle(
                color: _kAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            _buildSubtitleCard(context, recommended,
                isRecommended: true, downloadingId: downloadingId),
            const SizedBox(height: 16),
          ],

          // ── Other Results List ───────────────────────────────────
          if (otherItems.isNotEmpty) ...[
            Text(
              isPersian
                  ? 'سایر نتایج (${otherItems.length})'
                  : 'All Candidates (${otherItems.length})',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: otherItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _buildSubtitleCard(context, otherItems[index],
                    isRecommended: false, downloadingId: downloadingId);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubtitleCard(
    BuildContext context,
    OpenSubtitleItem item, {
    required bool isRecommended,
    required String? downloadingId,
  }) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    final isDownloading = downloadingId == item.id;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isRecommended ? _kAccent.withValues(alpha: 0.08) : _kScaffoldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRecommended ? _kAccent.withValues(alpha: 0.6) : _kBorder,
          width: isRecommended ? 1.4 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Subtitle Icon / Recommendation badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isRecommended ? _kAccent : Colors.white10,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRecommended ? Icons.star_rounded : Icons.subtitles_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Title & release details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight:
                              isRecommended ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (item.formattedEpisodeInfo.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.formattedEpisodeInfo,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      item.languageName,
                      style: const TextStyle(
                          color: _kAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.download_rounded,
                        color: Colors.white38, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      '${item.downloadCount}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    if (item.rating > 0) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.star_half_rounded,
                          color: Colors.amber, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        item.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Download & Apply Action Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecommended
                  ? _kAccent
                  : Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: isRecommended ? 4 : 0,
            ),
            onPressed: isDownloading ? null : () => _handleDownload(item),
            child: isDownloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    isPersian
                        ? (isRecommended ? 'تایید و دانلود' : 'دانلود')
                        : (isRecommended ? 'Download & Apply' : 'Download'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MobileSheetWrapper extends StatelessWidget {
  final Widget child;
  const _MobileSheetWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: _kOverlayBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}
