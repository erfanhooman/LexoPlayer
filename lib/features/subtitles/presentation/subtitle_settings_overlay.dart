import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/features/subtitles/presentation/open_subtitles_search_dialog.dart';

const _kOverlayBg = Color(0xE6141418); // 90% Midnight Charcoal
const _kScaffoldBg = Color(0xFF0C0C0E); // Midnight Charcoal Scaffold
const _kBorder = Color(0xFF25252B); // Sleek card border
const _kAccent = Color(0xFFFF5500); // Burnt Tangerine orange

/// Settings panel specifically for configuring subtitle styling.
///
/// Call [SubtitleSettingsOverlay.show] to present it adaptively:
/// - **Desktop** (macOS / Windows / Linux): centred dialog
/// - **Mobile** (Android / iOS): modal bottom sheet
class SubtitleSettingsOverlay extends ConsumerWidget {
  const SubtitleSettingsOverlay({super.key});

  /// Presents the subtitle settings panel.
  static void show(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS || MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _MobileSheetWrapper(
          child: const SubtitleSettingsOverlay(),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => const Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 80, vertical: 60),
          child: SubtitleSettingsOverlay(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawSize = ref.watch(subtitleSizeProvider);
    final rawColor = ref.watch(subtitleColorProvider);
    final rawBgColor = ref.watch(subtitleBgColorProvider);
    final rawOutline = ref.watch(subtitleOutlineWidthProvider);
    final rawFont = ref.watch(subtitleFontFamilyProvider);

    // Validate and fall back to default options to prevent legacy storage assertion errors.
    final currentSize = const [16.0, 22.0, 28.0, 34.0].contains(rawSize) ? rawSize : 22.0;
    final currentColor = const [0xFFFFFFFF, 0xFFFFF176, 0xFF00E5FF, 0xFF69F0AE, 0xFFFF5500].contains(rawColor) ? rawColor : 0xFFFFFFFF;
    final currentBgColor = const [0x00000000, 0x40000000, 0x99000000, 0xD9000000, 0xFF000000].contains(rawBgColor) ? rawBgColor : 0xD9000000;
    final currentOutline = const [0.0, 0.6, 1.2, 2.2].contains(rawOutline) ? rawOutline : 1.2;
    final currentFont = const ['System', 'Georgia', 'Times New Roman', 'Menlo', 'Courier New', 'Helvetica Neue', 'Avenir'].contains(rawFont) ? rawFont : 'System';

    final isPersian = ref.watch(appLanguageProvider) == 'fa';

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: _kOverlayBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title row ──────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isPersian ? 'تنظیمات زیرنویس' : 'Subtitle Settings',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Subtitle Track Selection (Primary & Secondary) ──
                        () {
                          final availableOptions = ref.watch(availableSubtitlesProvider);
                          final currentPrimary = ref.watch(selectedSubtitleProvider);
                          final currentSecondary = ref.watch(selectedSecondarySubtitleProvider);

                          final primaryId = availableOptions.any((o) => o.id == currentPrimary?.id)
                              ? currentPrimary?.id ?? 'none'
                              : 'none';
                          final secondaryId = availableOptions.any((o) => o.id == currentSecondary?.id)
                              ? currentSecondary?.id ?? 'none'
                              : 'none';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSettingDropdown<String>(
                                label: isPersian ? 'زیرنویس اصلی (زبان اصلی)' : 'Primary Subtitle (Main)',
                                value: primaryId,
                                items: availableOptions.map((opt) {
                                  return DropdownMenuItem<String>(
                                    value: opt.id,
                                    child: Text(opt.name, overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (id) {
                                  if (id != null) {
                                    final selectedOpt = availableOptions.firstWhere((o) => o.id == id);
                                    ref.read(selectedSubtitleProvider.notifier).state = selectedOpt;
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildSettingDropdown<String>(
                                label: isPersian ? 'زیرنویس دوم (ترجمه)' : 'Secondary Subtitle (Translation)',
                                value: secondaryId,
                                items: availableOptions.map((opt) {
                                  return DropdownMenuItem<String>(
                                    value: opt.id,
                                    child: Text(opt.name, overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (id) {
                                  if (id != null) {
                                    final selectedOpt = availableOptions.firstWhere((o) => o.id == id);
                                    ref.read(selectedSecondarySubtitleProvider.notifier).state = selectedOpt;
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                          );
                        }(),

                        // Font Size
                        _buildSettingDropdown<double>(
                          label: isPersian ? 'اندازه متن' : 'Text Size',
                          value: currentSize,
                          items: [
                            DropdownMenuItem(value: 16.0, child: Text(isPersian ? 'کوچک' : 'Small')),
                            DropdownMenuItem(value: 22.0, child: Text(isPersian ? 'متوسط' : 'Medium')),
                            DropdownMenuItem(value: 28.0, child: Text(isPersian ? 'بزرگ' : 'Large')),
                            DropdownMenuItem(value: 34.0, child: Text(isPersian ? 'خیلی بزرگ' : 'Extra Large')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(subtitleSizeProvider.notifier).state = val;
                              saveSubtitleSize(val);
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // Text Color
                        _buildSettingDropdown<int>(
                          label: isPersian ? 'رنگ متن' : 'Text Color',
                          value: currentColor,
                          items: [
                            DropdownMenuItem(value: 0xFFFFFFFF, child: Text(isPersian ? 'سفید' : 'White')),
                            DropdownMenuItem(value: 0xFFFFF176, child: Text(isPersian ? 'زرد' : 'Yellow')),
                            DropdownMenuItem(value: 0xFF00E5FF, child: Text(isPersian ? 'فیروزه‌ای' : 'Cyan')),
                            DropdownMenuItem(value: 0xFF69F0AE, child: Text(isPersian ? 'سبز' : 'Green')),
                            DropdownMenuItem(value: 0xFFFF5500, child: Text(isPersian ? 'نارنجی' : 'Tangerine')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(subtitleColorProvider.notifier).state = val;
                              saveSubtitleColor(val);
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                    // Background
                    _buildSettingDropdown<int>(
                      label: isPersian ? 'پس‌زمینه زیرنویس' : 'Background Style',
                      value: currentBgColor,
                      items: [
                        DropdownMenuItem(value: 0x00000000, child: Text(isPersian ? 'بدون پس‌زمینه (شفاف)' : 'None (Transparent)')),
                        DropdownMenuItem(value: 0x40000000, child: Text(isPersian ? 'شفاف کم' : 'Translucent')),
                        DropdownMenuItem(value: 0x99000000, child: Text(isPersian ? 'نیمه‌شفاف' : 'Semi-transparent')),
                        DropdownMenuItem(value: 0xD9000000, child: Text(isPersian ? 'تیره' : 'Dark')),
                        DropdownMenuItem(value: 0xFF000000, child: Text(isPersian ? 'مشکی کامل' : 'Solid (Black)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(subtitleBgColorProvider.notifier).state = val;
                          saveSubtitleBgColor(val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Outline
                    _buildSettingDropdown<double>(
                      label: isPersian ? 'ضخامت حاشیه' : 'Outline Thickness',
                      value: currentOutline,
                      items: [
                        DropdownMenuItem(value: 0.0, child: Text(isPersian ? 'بدون حاشیه' : 'None')),
                        DropdownMenuItem(value: 0.6, child: Text(isPersian ? 'باریک' : 'Thin')),
                        DropdownMenuItem(value: 1.2, child: Text(isPersian ? 'متوسط' : 'Medium')),
                        DropdownMenuItem(value: 2.2, child: Text(isPersian ? 'پهن' : 'Thick')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(subtitleOutlineWidthProvider.notifier).state = val;
                          saveSubtitleOutlineWidth(val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Font Family
                    _buildSettingDropdown<String>(
                      label: isPersian ? 'فونت زیرنویس' : 'Font Family',
                      value: currentFont,
                      items: const [
                        DropdownMenuItem(value: 'System', child: Text('System (Default)')),
                        DropdownMenuItem(value: 'Georgia', child: Text('Georgia (Serif)')),
                        DropdownMenuItem(value: 'Times New Roman', child: Text('Times New Roman (Serif)')),
                        DropdownMenuItem(value: 'Menlo', child: Text('Menlo (Monospace)')),
                        DropdownMenuItem(value: 'Courier New', child: Text('Courier New (Monospace)')),
                        DropdownMenuItem(value: 'Helvetica Neue', child: Text('Helvetica Neue (Sans-serif)')),
                        DropdownMenuItem(value: 'Avenir', child: Text('Avenir (Sans-serif)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(subtitleFontFamilyProvider.notifier).state = val;
                          saveSubtitleFontFamily(val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── OpenSubtitles Auto Search Action Button ─────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text(
                          isPersian
                              ? 'جستجوی خودکار زیرنویس (OpenSubtitles)...'
                              : 'Auto Search OpenSubtitles...',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          OpenSubtitlesSearchDialog.show(context);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Smart Subtitle Seek Toggle ─────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _kScaffoldBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isPersian ? 'پریش هوشمند زیرنویس' : 'Smart Subtitle Seek',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isPersian ? 'پریش بر اساس خطوط زیرنویس به جای ۱۰ ثانیه' : 'Jump to subtitle lines vs fixed 10s',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: ref.watch(smartSubtitleSeekProvider),
                            activeTrackColor: _kAccent,
                            onChanged: (val) {
                              ref.read(smartSubtitleSeekProvider.notifier).state = val;
                              saveSmartSubtitleSeek(val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildSettingDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _kScaffoldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: _kOverlayBg,
              borderRadius: BorderRadius.circular(8),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _kAccent,
                size: 20,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              onChanged: onChanged,
              items: items,
            ),
          ),
        ),
      ],
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
        child: SingleChildScrollView(
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
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
