import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/utils/word_tokenizer.dart';
import 'package:lexo_player/features/dictionary/data/dictionary_providers.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

/// Renders a single [TokenSpan] inside the subtitle overlay.
///
/// **Non-word tokens** (punctuation, whitespace) are displayed as plain styled
/// text with no interaction.
///
/// **Word tokens** respond to user input in a platform-aware way:
/// - **Desktop (macOS / Windows / Linux):** A [MouseRegion] provides hover
///   highlighting, and a [GestureDetector] handles taps. A
///   [CompositedTransformTarget] is attached so a popup overlay can be
///   positioned next to the tapped word.
/// - **Mobile (Android / iOS):** A [GestureDetector] with transparent ink
///   padding gives a larger touch target.
///
/// On tap the widget:
/// 1. Pauses the video player.
/// 2. Writes the selected token string, its [LayerLink], and [BuildContext]
///    into the corresponding Riverpod providers, which in turn trigger the
///    dictionary look-up flow.
class WordTokenWidget extends ConsumerStatefulWidget {
  /// The token this widget represents.
  final TokenSpan token;

  /// Creates a [WordTokenWidget] for the given [token].
  const WordTokenWidget({
    super.key,
    required this.token,
  });

  @override
  ConsumerState<WordTokenWidget> createState() => _WordTokenWidgetState();
}

class _WordTokenWidgetState extends ConsumerState<WordTokenWidget> {
  /// Whether the pointer is currently hovering over this widget (desktop only).
  bool _isHovered = false;

  /// A [LayerLink] used by [CompositedTransformFollower] to anchor the
  /// dictionary popup to this token.
  final LayerLink _layerLink = LayerLink();

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final token = widget.token;

    // Watch subtitle customization providers
    final size = ref.watch(subtitleSizeProvider);
    final colorVal = ref.watch(subtitleColorProvider);
    final outlineWidth = ref.watch(subtitleOutlineWidthProvider);
    final font = ref.watch(subtitleFontFamilyProvider);

    final baseStyle = TextStyle(
      color: Color(colorVal),
      fontSize: size,
      fontWeight: FontWeight.bold,
      fontFamily: font == 'System' ? null : font,
      fontFamilyFallback: font == 'Menlo' || font == 'Courier New'
          ? const ['Monaco', 'Consolas', 'Courier New', 'monospace']
          : (font == 'Georgia' || font == 'Times New Roman'
              ? const ['Times New Roman', 'Times', 'serif']
              : const ['Helvetica Neue', 'Arial', 'sans-serif']),
      shadows: outlineWidth > 0
          ? [
              Shadow(offset: Offset(-outlineWidth, -outlineWidth), color: Colors.black),
              Shadow(offset: Offset(outlineWidth, -outlineWidth), color: Colors.black),
              Shadow(offset: Offset(outlineWidth, outlineWidth), color: Colors.black),
              Shadow(offset: Offset(-outlineWidth, outlineWidth), color: Colors.black),
              const Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black),
            ]
          : const [
              Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black),
              Shadow(offset: Offset(-1, -1), blurRadius: 3, color: Colors.black),
            ],
    );

    // Non-word tokens (punctuation, whitespace) — plain text, no interaction.
    if (!token.isWord) {
      return Text(token.text, style: baseStyle);
    }

    // Word tokens — interactive, with hover/tap feedback.
    final effectiveStyle = _isHovered
        ? baseStyle.copyWith(
            backgroundColor: const Color(0xFFFF5500).withValues(alpha: 0.25),
          )
        : baseStyle;

    final textWidget = Text(token.text, style: effectiveStyle);

    // Determine platform category.
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    if (isDesktop) {
      return _buildDesktopToken(textWidget);
    } else {
      return _buildMobileToken(textWidget);
    }
  }

  // ---------------------------------------------------------------------------
  // Desktop variant
  // ---------------------------------------------------------------------------

  /// Wraps the token in [MouseRegion] (hover) + [GestureDetector] (tap) and
  /// attaches a [CompositedTransformTarget] so popups can anchor to it.
  Widget _buildDesktopToken(Widget child) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        _setHovered(true);
        ref.read(hoverPlaybackTimerProvider).onHoverEnter(
              widget.token.text,
              _layerLink,
              context,
            );
      },
      onExit: (_) {
        _setHovered(false);
        ref.read(hoverPlaybackTimerProvider).onHoverExit();
      },
      child: GestureDetector(
        onTap: _onTap,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: child,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile variant
  // ---------------------------------------------------------------------------

  /// Wraps the token in a [GestureDetector] with extra padding for a larger
  /// touch target.
  Widget _buildMobileToken(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: CompositedTransformTarget(
          link: _layerLink,
          child: child,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  void _setHovered(bool value) {
    if (_isHovered != value) {
      setState(() => _isHovered = value);
    }
  }

  /// Pauses the player (with no auto-resume) and pushes the selected token
  /// into the dictionary providers so the look-up flow is triggered reactively.
  void _onTap() {
    ref.read(hoverPlaybackTimerProvider).onTap(
          widget.token.text,
          _layerLink,
          context,
        );
  }
}
