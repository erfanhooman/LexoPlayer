import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lexo_player/core/engine/engine_providers.dart';
import 'package:lexo_player/core/services/auto_update_service.dart';
import 'package:lexo_player/core/theme/app_colors.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

const _kOverlayBg = Color(0xE6141418); // 90% Midnight Charcoal
const _kScaffoldBg = Color(0xFF0C0C0E); // Midnight Charcoal Scaffold
const _kBorder = Color(0xFF25252B); // Sleek card border
Color get _kAccent => AppColors.primary; // Accent orange

/// Main Application Settings Overlay (Separate from Subtitle Settings).
///
/// Controls app-wide options: Language, Smart Subtitle Seek, Auto Update App, Auto Update Dictionaries.
///
/// Call [AppSettingsOverlay.show] to present adaptively:
/// - Desktop (macOS / Windows / Linux): Centered glass dialog
/// - Mobile (Android / iOS): Modal bottom sheet
class AppSettingsOverlay extends ConsumerWidget {
  const AppSettingsOverlay({super.key});

  /// Presents the application settings panel adaptively.
  static void show(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS || MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _MobileSheetWrapper(
          child: AppSettingsOverlay(),
        ),
      );
    } else {
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => const Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 80, vertical: 60),
          child: AppSettingsOverlay(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appLanguageProvider);
    final isPersian = lang == 'fa';

    final isSmartSeekEnabled = ref.watch(smartSubtitleSeekProvider);
    final isAutoUpdateAppEnabled = ref.watch(autoUpdateAppProvider);
    final isAutoUpdateDictEnabled = ref.watch(autoUpdateDictProvider);

    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      decoration: BoxDecoration(
        color: _kOverlayBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 36,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Title & Close Button ─────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _kAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _kAccent.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            color: _kAccent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isPersian ? 'تنظیمات برنامه' : 'Application Settings',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 1. General & Language Section ───────────────────
                        _buildSectionHeader(
                          isPersian ? 'زبان و رابط کاربری' : 'Language & Interface',
                          Icons.language_rounded,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: _kScaffoldBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isPersian ? 'زبان برنامه' : 'App Language',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isPersian ? 'زبان نمایش منوها و رابط کاربری' : 'Interface language for menus and labels',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),

                              // Language switch segment
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Row(
                                  children: [
                                    _buildLangChip(
                                      label: 'EN',
                                      flag: '🇺🇸',
                                      isSelected: !isPersian,
                                      onTap: () {
                                        ref.read(appLanguageProvider.notifier).state = 'en';
                                      },
                                    ),
                                    _buildLangChip(
                                      label: 'FA',
                                      flag: '🇮🇷',
                                      isSelected: isPersian,
                                      onTap: () {
                                        ref.read(appLanguageProvider.notifier).state = 'fa';
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── 2. Playback Options Section ─────────────────────
                        _buildSectionHeader(
                          isPersian ? 'تنظیمات پخش‌کننده' : 'Player Preferences',
                          Icons.play_circle_outline_rounded,
                        ),
                        const SizedBox(height: 10),
                        _buildSettingTile(
                          title: isPersian ? 'پریش هوشمند زیرنویس' : 'Smart Subtitle Seek',
                          subtitle: isPersian
                              ? 'پریش بر اساس زمان خطوط زیرنویس به جای ۱۰ ثانیه ثابت'
                              : 'Jump directly to subtitle timestamps instead of fixed 10s',
                          value: isSmartSeekEnabled,
                          onChanged: (val) {
                            ref.read(smartSubtitleSeekProvider.notifier).state = val;
                            saveSmartSubtitleSeek(val);
                          },
                        ),

                        const SizedBox(height: 20),

                        // ── 3. Auto Updates Section ────────────────────────
                        _buildSectionHeader(
                          isPersian ? 'بروزرسانی‌های خودکار' : 'Automatic Updates',
                          Icons.system_update_rounded,
                        ),
                        const SizedBox(height: 10),
                        _buildSettingTile(
                          title: isPersian ? 'بروزرسانی خودکار برنامه' : 'Auto Update App',
                          subtitle: isPersian
                              ? 'دریافت خودکار آخرین نسخه برنامه از گیت‌هاب'
                              : 'Automatically check & download new app releases from GitHub',
                          value: isAutoUpdateAppEnabled,
                          onChanged: (val) {
                            AutoUpdateService.setAutoUpdateApp(ref, val);
                          },
                        ),
                        const SizedBox(height: 10),
                        _buildSettingTile(
                          title: isPersian ? 'بروزرسانی خودکار واژه‌نامه‌ها' : 'Auto Update Dictionaries',
                          subtitle: isPersian
                              ? 'دانلود و بروزرسانی خودکار پایگاه‌داده از گیت‌هاب'
                              : 'Auto-download & replace dictionary database from GitHub',
                          value: isAutoUpdateDictEnabled,
                          onChanged: (val) {
                            AutoUpdateService.setAutoUpdateDict(ref, val);
                          },
                        ),

                        const SizedBox(height: 20),

                        // ── 4. App Info Section ─────────────────────────────
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    isPersian ? 'نسخه برنامه' : 'App Version',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _kAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'v1.0.0',
                                  style: TextStyle(
                                    color: _kAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _kAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildLangChip({
    required String label,
    required String flag,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kScaffoldBg,
        borderRadius: BorderRadius.circular(12),
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
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: _kAccent,
            onChanged: onChanged,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
