import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/core/widgets/glass_container.dart';
import 'package:lexo_player/core/services/saved_review_service.dart';
import 'package:lexo_player/core/services/tts_service.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/features/review_later/presentation/mini_clip_player.dart';

/// The main "Review Later" panel displayed in the Main Menu dashboard area.
class ReviewLaterPanel extends ConsumerStatefulWidget {
  const ReviewLaterPanel({super.key});

  @override
  ConsumerState<ReviewLaterPanel> createState() => _ReviewLaterPanelState();
}

class _ReviewLaterPanelState extends ConsumerState<ReviewLaterPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _activePlayingSentenceId;
  final Set<String> _collapsedGroups = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    final allSentences = ref.watch(savedSentencesProvider);

    // Filter by search query
    final filtered = allSentences.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.sentenceText.toLowerCase().contains(q) ||
          s.targetWord.toLowerCase().contains(q) ||
          s.videoTitle.toLowerCase().contains(q) ||
          (s.translation?.toLowerCase().contains(q) ?? false);
    }).toList();

    // Group filtered sentences by video title
    final grouped = <String, List<SavedSentence>>{};
    for (final s in filtered) {
      final title = s.videoTitle.isNotEmpty ? s.videoTitle : (isPersian ? 'ویدیوی نامشخص' : 'Unknown Video');
      grouped.putIfAbsent(title, () => []).add(s);
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Title & Search ─────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.bookmark_added_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 10),
              Text(
                isPersian ? 'مرور جملات برای تمرین' : 'Review Sentences Later',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${allSentences.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isPersian
                ? 'جملاتی که هنگام تماشای فیلم برای تمرین، تکرار و تلفظ ذخیره کرده‌اید.'
                : 'Movie sentences you saved to practice listening, shadowing, and vocabulary.',
            style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 13),
          ),
          const SizedBox(height: 18),

          // ── Search bar ───────────────────────────────────────────────────
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF141318),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2C2C35)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: isPersian ? 'جستجو در جملات یا واژه‌ها...' : 'Search sentences, words, or movies...',
                hintStyle: const TextStyle(color: Color(0xFF6B6A75), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF8A8A93), size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Color(0xFF8A8A93), size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Content List / Empty State ────────────────────────────────────
          if (allSentences.isEmpty)
            _buildEmptyState(isPersian)
          else if (grouped.isEmpty)
            _buildNoSearchResultsState(isPersian)
          else
            for (final entry in grouped.entries)
              _buildVideoSection(
                videoTitle: entry.key,
                sentences: entry.value,
                isPersian: isPersian,
              ),
        ],
      ),
    );
  }

  Widget _buildVideoSection({
    required String videoTitle,
    required List<SavedSentence> sentences,
    required bool isPersian,
  }) {
    final isCollapsed = _collapsedGroups.contains(videoTitle);
    final videoPath = sentences.first.videoPath;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(16),
        borderColor: Colors.white.withValues(alpha: 0.08),
        color: Colors.white.withValues(alpha: 0.03),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Row(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isCollapsed) {
                        _collapsedGroups.remove(videoTitle);
                      } else {
                        _collapsedGroups.add(videoTitle);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCollapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.movie_rounded, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Text(
                            videoTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${sentences.length}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),

                // Batch Actions Button (Delete all for this video)
                IconButton(
                  tooltip: isPersian ? 'حذف تمام جملات این ویدیو' : 'Delete all for this movie',
                  icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white38, size: 20),
                  onPressed: () => _confirmBatchDelete(videoTitle, videoPath, isPersian),
                ),
              ],
            ),

            if (!isCollapsed) ...[
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF2C2C35), height: 1),
              const SizedBox(height: 12),

              // Sentences Cards List
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sentences.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final s = sentences[index];
                  final isPlaying = _activePlayingSentenceId == s.id;
                  return _buildSentenceCard(s, isPlaying, isPersian);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSentenceCard(SavedSentence sentence, bool isPlaying, bool isPersian) {
    final startTimeStr = _formatDuration(sentence.startTime);
    final endTimeStr = _formatDuration(sentence.endTime);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16151C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPlaying ? AppColors.primary.withValues(alpha: 0.6) : const Color(0xFF282732),
          width: isPlaying ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Row: Timeframe, Word Tag, Mastery & Delete ────────────────
          Row(
            children: [
              // Timeframe Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF22202C),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time_rounded, color: Colors.white60, size: 12),
                    const SizedBox(width: 5),
                    Text(
                      '$startTimeStr → $endTimeStr',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Highlighted Target Word Pill with TTS
              InkWell(
                onTap: () {
                  ref.read(ttsServiceProvider).speak(sentence.targetWord);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sentence.targetWord,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.volume_up_rounded, color: AppColors.primary, size: 13),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Mastery Toggle
              IconButton(
                tooltip: sentence.isMastered
                    ? (isPersian ? 'علامت به عنوان نیاز به تمرین' : 'Mark as in-progress')
                    : (isPersian ? 'علامت به عنوان یاد گرفته شده' : 'Mark as mastered'),
                icon: Icon(
                  sentence.isMastered ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                  color: sentence.isMastered ? Colors.greenAccent : Colors.white38,
                  size: 20,
                ),
                onPressed: () {
                  if (sentence.id != null) {
                    ref.read(savedSentencesProvider.notifier).toggleMastered(sentence.id!);
                  }
                },
              ),

              // Delete Sentence
              IconButton(
                tooltip: isPersian ? 'حذف جمله' : 'Delete sentence',
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                onPressed: () {
                  if (sentence.id != null) {
                    ref.read(savedSentencesProvider.notifier).removeSentence(sentence.id!);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Main Sentence Text with Target Word Highlighted ───────────────
          _buildSentenceText(sentence.sentenceText, sentence.targetWord),

          // ── Optional Translation ──────────────────────────────────────────
          if (sentence.translation != null && sentence.translation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1D26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                sentence.translation!,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  color: Color(0xFFB5B4BE),
                  fontSize: 13,
                  fontFamily: 'Parastoo',
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Bottom Action / Mini Video Clip Player ────────────────────────
          if (isPlaying) ...[
            MiniClipPlayer(
              videoPath: sentence.videoPath,
              startTime: sentence.startTime,
              endTime: sentence.endTime,
              onClose: () {
                setState(() => _activePlayingSentenceId = null);
              },
            ),
          ] else ...[
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(
                    isPersian ? 'پخش برش ویدیو' : 'Play Video Clip',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () {
                    setState(() => _activePlayingSentenceId = sentence.id);
                  },
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: Text(
                    isPersian ? 'تلفظ کلمه' : 'Hear Word',
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF383745)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    ref.read(ttsServiceProvider).speak(sentence.targetWord);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Renders sentence text with the target word visually highlighted in accent color.
  Widget _buildSentenceText(String fullSentence, String targetWord) {
    if (targetWord.isEmpty || !fullSentence.toLowerCase().contains(targetWord.toLowerCase())) {
      return Text(
        fullSentence,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      );
    }

    final lowerSentence = fullSentence.toLowerCase();
    final lowerTarget = targetWord.toLowerCase();
    final startIndex = lowerSentence.indexOf(lowerTarget);
    final endIndex = startIndex + targetWord.length;

    final before = fullSentence.substring(0, startIndex);
    final match = fullSentence.substring(startIndex, endIndex);
    final after = fullSentence.substring(endIndex);

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primary,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isPersian) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        margin: const EdgeInsets.only(top: 40),
        decoration: BoxDecoration(
          color: const Color(0xFF141318),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF282732)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bookmark_add_outlined,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isPersian ? 'هیچ جمله‌ای ذخیره نشده است' : 'No saved sentences yet',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isPersian
                  ? 'هنگام تماشای فیلم، روی هر کلمه در زیرنویس کلیک کنید و گزینه "ذخیره جمله" را انتخاب نمایید تا برای تمرین و یادگیری در این بخش قرار گیرد.'
                  : 'While watching a movie, click any word in the subtitles and tap "Save Sentence" to collect clips for listening and practice here.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8A8A93), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState(bool isPersian) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white38, size: 40),
            const SizedBox(height: 12),
            Text(
              isPersian ? 'موردی با این عبارت یافت نشد' : 'No sentences matching your search',
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmBatchDelete(String videoTitle, String videoPath, bool isPersian) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1923),
        title: Text(
          isPersian ? 'حذف تمام جملات؟' : 'Delete all saved sentences?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          isPersian
              ? 'آیا مایلید تمام جملات ذخیره شده مربوط به "$videoTitle" را حذف کنید؟'
              : 'Are you sure you want to delete all sentences saved for "$videoTitle"?',
          style: const TextStyle(color: Color(0xFFB5B4BE), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(isPersian ? 'انصراف' : 'Cancel', style: const TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              ref.read(savedSentencesProvider.notifier).removeSentencesForVideo(videoPath);
              Navigator.pop(dialogCtx);
            },
            child: Text(isPersian ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
  }
}
