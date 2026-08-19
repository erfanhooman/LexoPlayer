import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/models/engine_output.dart';
import 'package:lexo_player/features/dictionary/data/span_providers.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

/// Renders a single word inside the subtitle overlay with the legacy
/// interaction pattern:
///
/// - **Hover** pauses the video and opens the engine definition popup for
///   the span that contains this word. Exiting resumes playback (debounced).
/// - **Tap** pins the popup open (no auto-resume).
///
/// Words belonging to a MULTI_WORD_SPAN are rendered with a subtle
/// underline so the user can see the idiom/MWE grouping.
class SubtitleWordWidget extends ConsumerStatefulWidget {
  /// The surface text of this word.
  final String text;

  /// The engine span that contains this word, or `null` if the engine
  /// produced no span for it (renders as a plain non-interactive word).
  final SpanModel? span;

  const SubtitleWordWidget({
    super.key,
    required this.text,
    required this.span,
  });

  @override
  ConsumerState<SubtitleWordWidget> createState() => _SubtitleWordWidgetState();
}

class _SubtitleWordWidgetState extends ConsumerState<SubtitleWordWidget> {
  bool _isHovered = false;
  final LayerLink _layerLink = LayerLink();

  @override
  Widget build(BuildContext context) {
    final size = ref.watch(subtitleSizeProvider);
    final colorVal = ref.watch(subtitleColorProvider);
    final outlineWidth = ref.watch(subtitleOutlineWidthProvider);
    final font = ref.watch(subtitleFontFamilyProvider);

    final baseStyle = TextStyle(
      color: Color(colorVal),
      fontSize: size,
      fontWeight: FontWeight.bold,
      fontFamily: font == 'System' ? null : font,
      // Always include Persian/Arabic-capable fonts in the fallback chain so
      // subtitles like "سلام چطوری" render with visible glyphs on every platform.
      fontFamilyFallback: font == 'Menlo' || font == 'Courier New'
          ? const [
              'Monaco',
              'Consolas',
              'Courier New',
              'Vazirmatn',
              'Tahoma',
              'monospace'
            ]
          : (font == 'Georgia' || font == 'Times New Roman'
              ? const [
                  'Times New Roman',
                  'Times',
                  'Vazirmatn',
                  'Tahoma',
                  'serif'
                ]
              : const [
                  'Vazirmatn',
                  'IRANSans',
                  'Tahoma',
                  'Arial',
                  'Helvetica Neue',
                  'sans-serif'
                ]),
      shadows: outlineWidth > 0
          ? [
              Shadow(
                  offset: Offset(-outlineWidth, -outlineWidth),
                  color: Colors.black),
              Shadow(
                  offset: Offset(outlineWidth, -outlineWidth),
                  color: Colors.black),
              Shadow(
                  offset: Offset(outlineWidth, outlineWidth),
                  color: Colors.black),
              Shadow(
                  offset: Offset(-outlineWidth, outlineWidth),
                  color: Colors.black),
              const Shadow(
                  offset: Offset(1, 1), blurRadius: 3, color: Colors.black),
            ]
          : const [
              Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black),
              Shadow(
                  offset: Offset(-1, -1), blurRadius: 3, color: Colors.black),
            ],
    );

    // No engine span for this word — render as plain text (no interaction).
    if (widget.span == null) {
      return Text(widget.text, style: baseStyle);
    }

    final effectiveStyle = _isHovered
        ? baseStyle.copyWith(
            backgroundColor: const Color(0xFFFF5500).withValues(alpha: 0.25),
          )
        : baseStyle;

    // Multi-word spans get a subtle underline so the user sees the grouping.
    final textStyle = widget.span!.isMultiWord
        ? effectiveStyle.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFFFF5500).withOpacity(0.5),
            decorationThickness: 2,
          )
        : effectiveStyle;

    final textWidget = Text(widget.text, style: textStyle);

    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    if (isDesktop) {
      return _buildDesktopToken(textWidget);
    } else {
      return _buildMobileToken(textWidget);
    }
  }

  Widget _buildDesktopToken(Widget child) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        _setHovered(true);
        ref.read(spanHoverControllerProvider).onHoverEnter(
              span: widget.span!,
              layerLink: _layerLink,
              context: context,
            );
      },
      onExit: (_) {
        _setHovered(false);
        ref.read(spanHoverControllerProvider).onHoverExit();
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

  void _setHovered(bool value) {
    if (_isHovered != value) {
      setState(() => _isHovered = value);
    }
  }

  void _onTap() {
    if (widget.span == null) return;
    ref.read(spanHoverControllerProvider).onTap(
          span: widget.span!,
          layerLink: _layerLink,
          context: context,
        );
  }
}
