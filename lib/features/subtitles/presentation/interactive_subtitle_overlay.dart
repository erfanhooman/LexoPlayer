import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/utils/word_tokenizer.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/subtitles/presentation/word_token_widget.dart';

/// Displays the active subtitle text at the bottom of the video player.
///
/// Each word is rendered as an independent [WordTokenWidget] so the user can
/// interact with individual tokens (tap / hover) for dictionary look-ups.
///
/// The overlay fades in and out smoothly using an [AnimatedSwitcher] and is
/// hidden entirely when [subtitleVisibilityProvider] is `false` or there is no
/// active subtitle text.
///
/// Usage — place inside a [Stack] that covers the video surface:
/// ```dart
/// Stack(
///   children: [
///     VideoWidget(...),
///     const InteractiveSubtitleOverlay(),
///   ],
/// )
/// ```
class InteractiveSubtitleOverlay extends ConsumerWidget {
  /// Creates an [InteractiveSubtitleOverlay].
  const InteractiveSubtitleOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleText = ref.watch(activeSubtitleTextProvider);
    final isVisible = ref.watch(subtitleVisibilityProvider);

    const bottomOffset = 120.0;

    // Nothing to show — return an empty box that still occupies the
    // Positioned slot so AnimatedSwitcher can animate out correctly.
    if (subtitleText == null || !isVisible) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        bottom: bottomOffset,
        left: 0,
        right: 0,
        child: const SizedBox.shrink(),
      );
    }

    // Tokenise the active line into word / punctuation spans.
    final tokens = WordTokenizer.tokenize(subtitleText);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      bottom: bottomOffset,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Container(
            // Use the subtitle text as key so the switcher animates on
            // every cue change.
            key: ValueKey<String>(subtitleText),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: Color(ref.watch(subtitleBgColorProvider)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: tokens
                  .asMap()
                  .entries
                  .map((entry) => WordTokenWidget(
                        token: entry.value,
                        lineTokens: tokens,
                        tokenIndex: entry.key,
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}
