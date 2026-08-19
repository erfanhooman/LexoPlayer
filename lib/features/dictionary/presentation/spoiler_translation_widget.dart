import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';

/// A widget that parses comma/newline-separated bilingual translation text
/// into individual interactive chips/pills, hiding them behind a spoiler blur
/// effect until clicked by the user.
class SpoilerTranslationWidget extends ConsumerStatefulWidget {
  /// The raw translation string (e.g. comma-separated words/phrases).
  final String rawTranslation;

  /// Maximum number of translation chips to display before showing an expansion button.
  final int initialMaxItems;

  /// Whether the alignment should be right-aligned for header areas.
  final bool compactHeaderMode;

  const SpoilerTranslationWidget({
    super.key,
    required this.rawTranslation,
    this.initialMaxItems = 3,
    this.compactHeaderMode = false,
  });

  @override
  ConsumerState<SpoilerTranslationWidget> createState() =>
      _SpoilerTranslationWidgetState();
}

class _SpoilerTranslationWidgetState
    extends ConsumerState<SpoilerTranslationWidget> {
  final Set<int> _revealedIndices = {};
  bool _revealAll = false;
  bool _isExpanded = false;

  List<String> _parseItems(String raw) {
    if (raw.trim().isEmpty) return const [];
    return raw
        .split(RegExp(r'[,،;\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = ref.watch(appLanguageProvider) == 'fa';
    final items = _parseItems(widget.rawTranslation);
    if (items.isEmpty) return const SizedBox.shrink();

    final visibleCount = (_isExpanded || items.length <= widget.initialMaxItems)
        ? items.length
        : widget.initialMaxItems;
    final remainingCount = items.length - visibleCount;

    return Column(
      crossAxisAlignment: widget.compactHeaderMode
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reveal / Hide All Header Bar
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: widget.compactHeaderMode
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _revealAll = !_revealAll;
                  if (!_revealAll) {
                    _revealedIndices.clear();
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _revealAll
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 13,
                      color: const Color(0xFFFF5500),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _revealAll
                          ? (isPersian ? 'مخفی کردن ترجمه' : 'Hide translation')
                          : (isPersian ? 'نمایش ترجمه' : 'Reveal translation'),
                      style: const TextStyle(
                        color: Color(0xFFFF5500),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Translation Chips
        Directionality(
          textDirection: TextDirection.rtl,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: widget.compactHeaderMode
                ? WrapAlignment.end
                : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < visibleCount; i++) ...[
                _SpoilerChip(
                  text: items[i],
                  isRevealed: _revealAll || _revealedIndices.contains(i),
                  onTap: () {
                    setState(() {
                      if (_revealedIndices.contains(i)) {
                        _revealedIndices.remove(i);
                      } else {
                        _revealedIndices.add(i);
                      }
                    });
                  },
                ),
              ],
              if (remainingCount > 0)
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = true),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25252E),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF3F3F4C)),
                    ),
                    child: Text(
                      isPersian
                          ? '+$remainingCount مورد دیگر'
                          : '+$remainingCount more',
                      style: const TextStyle(
                        color: Color(0xFFA1A1AA),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (_isExpanded && items.length > widget.initialMaxItems)
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = false),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25252E),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF3F3F4C)),
                    ),
                    child: Text(
                      isPersian ? 'نمایش کمتر' : 'Show less',
                      style: const TextStyle(
                        color: Color(0xFFA1A1AA),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpoilerChip extends StatelessWidget {
  final String text;
  final bool isRevealed;
  final VoidCallback onTap;

  const _SpoilerChip({
    required this.text,
    required this.isRevealed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isRevealed
              ? const Color(0xFFFF5500).withOpacity(0.14)
              : const Color(0xFF1E1E24),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isRevealed
                ? const Color(0xFFFF5500).withOpacity(0.4)
                : const Color(0xFF33333F),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ImageFiltered(
                imageFilter: isRevealed
                    ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
                    : ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
                child: Text(
                  text,
                  style: TextStyle(
                    color: isRevealed
                        ? const Color(0xFFFF7733)
                        : Colors.white.withOpacity(0.8),
                    fontSize: 13,
                    fontWeight: isRevealed ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              if (!isRevealed)
                const Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.visibility_rounded,
                      size: 12,
                      color: Colors.white70,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
