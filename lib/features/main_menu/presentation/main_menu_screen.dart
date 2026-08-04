import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:window_manager/window_manager.dart';

import 'package:lexo_player/core/widgets/glass_container.dart';
import 'package:lexo_player/core/services/history_service.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/video_player/presentation/video_screen.dart';
import 'package:lexo_player/features/dictionary/presentation/download_hub_screen.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';
import 'package:lexo_player/features/subtitles/presentation/subtitle_settings_overlay.dart';

import 'package:lexo_player/core/theme/app_colors.dart';

// ── Centralized Palette Tokens (Linked to AppColors.primary) ───────────────
Color get kNeutralAccent => AppColors.primary;
Color get kNeutralAccentDark => AppColors.primaryDark;
Color get kNeutralAccentSoft => AppColors.primaryLight;

class MainMenuScreen extends ConsumerStatefulWidget {
  const MainMenuScreen({super.key});

  @override
  ConsumerState<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends ConsumerState<MainMenuScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isDraggingFile = false;
  String _activeNav = 'Home';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _openVideoScreen(String uri) {
    ref.read(recentVideosProvider.notifier).addMedia(uri);

    // Reset subtitles
    ref.read(selectedSubtitleProvider.notifier).state = const SubtitleTrackOption(
      id: 'none',
      name: 'Off',
      isExternal: false,
    );
    ref.read(externalSubtitleOptionsProvider.notifier).state = const [];
    ref.read(isVideoLoadedProvider.notifier).state = true;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoScreen(videoUri: uri),
      ),
    );
  }

  Future<void> _pickLocalFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4', 'MP4', 'mkv', 'MKV', 'avi', 'AVI', 'webm', 'WEBM',
        'mov', 'MOV', 'flv', 'FLV', 'm4v', 'M4V', '3gp', '3GP',
        'ts', 'TS', 'wmv', 'WMV', 'mpg', 'MPG', 'mpeg', 'MPEG'
      ],
      dialogTitle: 'Open Video File',
    );

    if (result != null && result.files.single.path != null) {
      _openVideoScreen(result.files.single.path!);
    }
  }

  Future<void> _pickLocalFolder() async {
    final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Folder containing Video Files',
    );

    if (selectedDirectory != null) {
      final dir = Directory(selectedDirectory);
      try {
        final List<FileSystemEntity> entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            final path = entity.path;
            final lower = path.toLowerCase();
            if (lower.endsWith('.mp4') ||
                lower.endsWith('.mkv') ||
                lower.endsWith('.avi') ||
                lower.endsWith('.mov') ||
                lower.endsWith('.webm')) {
              _openVideoScreen(path);
              return;
            }
          }
        }
      } catch (_) {}
    }
  }

  void _showStreamUrlDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16151E).withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          title: Row(
            children: [
              Icon(Icons.link_rounded, color: kNeutralAccent),
              const SizedBox(width: 10),
              const Text(
                'Stream from Link',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Paste video stream URL (http, https, hls)...',
              hintStyle: const TextStyle(color: Color(0xFF8E8D94)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: kNeutralAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8D94))),
            ),
            ElevatedButton(
              onPressed: () {
                final url = _urlController.text.trim();
                if (url.isNotEmpty) {
                  Navigator.of(context).pop();
                  _openVideoScreen(url);
                  _urlController.clear();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kNeutralAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Stream', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final recentVideos = ref.watch(recentVideosProvider);

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingFile = true),
      onDragExited: (_) => setState(() => _isDraggingFile = false),
      onDragDone: (details) {
        setState(() => _isDraggingFile = false);
        if (details.files.isNotEmpty) {
          final file = details.files.first;
          final path = file.path;
          final lower = path.toLowerCase();
          if (lower.endsWith('.mp4') ||
              lower.endsWith('.mkv') ||
              lower.endsWith('.avi') ||
              lower.endsWith('.mov') ||
              lower.endsWith('.webm') ||
              lower.endsWith('.flv') ||
              lower.endsWith('.m4v') ||
              lower.endsWith('.3gp') ||
              lower.endsWith('.ts')) {
            _openVideoScreen(path);
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F12),
        body: Stack(
          children: [
            // ── Layer 1: Subtle Non-Glowing Canvas Background Light ────────────
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 550,
                height: 550,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      kNeutralAccent.withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),

            // ── Layer 2: Floating Glass UI ──────────────────────────────────────
            Row(
              children: [
                // Floating Left Navigation Sidebar
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: _SidebarWidget(
                    activeNav: _activeNav,
                    onNavSelect: (nav) {
                      setState(() => _activeNav = nav);
                      if (nav == 'Dictionaries') {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DownloadHubScreen()),
                        );
                      } else if (nav == 'Settings') {
                        SubtitleSettingsOverlay.show(context);
                      }
                    },
                    onOpenFile: _pickLocalFile,
                    onOpenFolder: _pickLocalFolder,
                    onStreamLink: _showStreamUrlDialog,
                  ),
                ),

                // Main Right Workspace
                Expanded(
                  child: Column(
                    children: [
                      // Header Navigation Bar
                      _MainHeaderWidget(
                        onOpenSettings: () => SubtitleSettingsOverlay.show(context),
                      ),

                      // Main Scrollable Dashboard Area
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Featured Continue Watching Hero Card
                              _HeroContinueWatchingCard(
                                recentVideos: recentVideos,
                                onResume: (uri) => _openVideoScreen(uri),
                              ),

                              const SizedBox(height: 28),

                              // Quick Actions Section Header
                              const Text(
                                'Quick Actions',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _QuickActionsGrid(
                                onOpenFile: _pickLocalFile,
                                onOpenFolder: _pickLocalFolder,
                                onStreamLink: _showStreamUrlDialog,
                              ),

                              const SizedBox(height: 32),

                              // Recent Files Section Header
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Recent Files',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  if (recentVideos.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        ref.read(recentVideosProvider.notifier).clearHistory();
                                      },
                                      child: Text(
                                        'Clear All',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: kNeutralAccent,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _RecentFilesList(
                                recentVideos: recentVideos,
                                onPlay: (uri) => _openVideoScreen(uri),
                                onDelete: (uri) {
                                  ref.read(recentVideosProvider.notifier).removeMedia(uri);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Drag & Drop Video File Overlay
            if (_isDraggingFile)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.8),
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 320),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1923),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: kNeutralAccent.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: kNeutralAccent.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: kNeutralAccent.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.video_library_rounded,
                                size: 48,
                                color: kNeutralAccent,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Drop Video File to Play',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'Supports MP4, MKV, AVI, WEBM, MOV, FLV',
                                style: TextStyle(
                                  color: Color(0xFF9E9D9F),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 1. Floating Sidebar Navigation Widget
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SidebarWidget extends StatelessWidget {
  final String activeNav;
  final ValueChanged<String> onNavSelect;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onStreamLink;

  const _SidebarWidget({
    required this.activeNav,
    required this.onNavSelect,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onStreamLink,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      width: 250,
      borderRadius: BorderRadius.circular(24),
      color: Colors.grey.withValues(alpha: 0.10),
      borderColor: Colors.grey.shade300.withValues(alpha: 0.14),
      blur: 10.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),

          // LexoPlayer Brand Logo & Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: [kNeutralAccent, kNeutralAccentDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'LexoPlayer',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Primary Navigation Links
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SidebarNavItem(
                    title: 'Home',
                    icon: Icons.home_rounded,
                    isActive: activeNav == 'Home',
                    onTap: () => onNavSelect('Home'),
                  ),
                  _SidebarNavItem(
                    title: 'Dictionaries',
                    icon: Icons.menu_book_rounded,
                    isActive: activeNav == 'Dictionaries',
                    onTap: () => onNavSelect('Dictionaries'),
                  ),
                  _SidebarNavItem(
                    title: 'Library',
                    icon: Icons.folder_copy_outlined,
                    isActive: activeNav == 'Library',
                    onTap: () => onNavSelect('Library'),
                  ),
                  _SidebarNavItem(
                    title: 'Continue Watching',
                    icon: Icons.access_time_rounded,
                    isActive: activeNav == 'Continue Watching',
                    onTap: () => onNavSelect('Continue Watching'),
                  ),

                  const SizedBox(height: 24),

                  // Section: PLAYBACK
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      'PLAYBACK',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kNeutralAccent,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  _SidebarSubItem(
                    title: 'Open File',
                    icon: Icons.folder_open_outlined,
                    onTap: onOpenFile,
                  ),
                  _SidebarSubItem(
                    title: 'Open Folder',
                    icon: Icons.folder_outlined,
                    onTap: onOpenFolder,
                  ),
                  _SidebarSubItem(
                    title: 'Stream from Link',
                    icon: Icons.link_rounded,
                    onTap: onStreamLink,
                  ),

                  const SizedBox(height: 24),

                  // Section: TOOLS
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      'TOOLS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kNeutralAccent,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  _SidebarSubItem(
                    title: 'Settings',
                    icon: Icons.settings_outlined,
                    onTap: () => onNavSelect('Settings'),
                  ),
                ],
              ),
            ),
          ),

          // User Profile Bar at bottom
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: kNeutralAccent,
                  child: const Text(
                    'E',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'erfanhooman',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.unfold_more_rounded,
                  color: Color(0xFF9E9D9F),
                  size: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF221B16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? Border.all(color: kNeutralAccent.withValues(alpha: 0.25))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? kNeutralAccent : const Color(0xFF9E9D9F),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive ? kNeutralAccent : const Color(0xFFD1D1D6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarSubItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _SidebarSubItem({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: kNeutralAccent,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFD1D1D6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 2. Main Header Bar
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _MainHeaderWidget extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _MainHeaderWidget({
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 24, 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Greeting & Subtitle
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good evening, erfanhooman',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Let's continue watching",
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9E9D9F),
                  ),
                ),
              ],
            ),

            // Header Right Action Controls
            Row(
              children: [
                // Language Selector Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'EN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF9E9D9F),
                        size: 18,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Notification Bell Icon with Badge
                Stack(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    Positioned(
                      right: 9,
                      top: 9,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: kNeutralAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 12),

                // Settings / Equalizer Icon Button
                IconButton(
                  onPressed: onOpenSettings,
                  tooltip: 'Settings',
                  icon: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 3. Featured Hero Continue Watching Banner
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _HeroContinueWatchingCard extends StatelessWidget {
  final List<String> recentVideos;
  final ValueChanged<String> onResume;

  const _HeroContinueWatchingCard({
    required this.recentVideos,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final String heroUri = recentVideos.isNotEmpty
        ? recentVideos.first
        : '/Users/erfanhooman/Videos/House.of.the.Dragon.S02E05.mp4';
    final String heroTitle = recentVideos.isNotEmpty
        ? formatMediaTitle(heroUri)
        : 'House of the Dragon - S02E05';

    return GlassContainer(
      width: double.infinity,
      height: 190,
      borderRadius: BorderRadius.circular(24),
      color: Colors.grey.withValues(alpha: 0.10),
      borderColor: Colors.grey.shade300.withValues(alpha: 0.14),
      blur: 10.0,
      child: Stack(
        children: [
          // Ambient neutral wave backdrop art
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CustomPaint(
                painter: _HeroCardGlowPainter(),
              ),
            ),
          ),

          // Content Row
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                // Left Circular Progress Ring
                _CircularProgressWidget(
                  percentage: 78,
                  onTap: () => onResume(heroUri),
                ),

                const SizedBox(width: 24),

                // Right Details & Actions
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              heroTitle,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.more_vert_rounded,
                              color: Color(0xFF9E9D9F),
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '42 min left',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9E9D9F),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Neutral Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: 0.78,
                          minHeight: 6,
                          backgroundColor: const Color(0xFF2F2A38),
                          valueColor: AlwaysStoppedAnimation<Color>(kNeutralAccent),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Action Buttons Row
                      Row(
                        children: [
                          // Neutral Amber Resume Button
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [kNeutralAccent, kNeutralAccentDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => onResume(heroUri),
                                borderRadius: BorderRadius.circular(20),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                      SizedBox(width: 6),
                                      Text(
                                        'Resume',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Translucent Details Button
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.info_outline_rounded, size: 18),
                            label: const Text(
                              'Details',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircularProgressWidget extends StatelessWidget {
  final int percentage;
  final VoidCallback onTap;

  const _CircularProgressWidget({
    required this.percentage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 110,
        height: 110,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Circular Ring Arc Painter
            CustomPaint(
              size: const Size(110, 110),
              painter: _RingProgressPainter(progress: percentage / 100.0),
            ),

            // Inner Play Circle Button
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [kNeutralAccent, kNeutralAccentDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),

            // Percentage Label below play icon
            Positioned(
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF16141D),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$percentage%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingProgressPainter extends CustomPainter {
  final double progress;

  _RingProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 12) / 2;

    // Track circle
    final trackPaint = Paint()
      ..color = const Color(0xFF2B2635)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    canvas.drawCircle(center, radius, trackPaint);

    // Active Neutral progress arc
    final activePaint = Paint()
      ..color = kNeutralAccent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;

    const startAngle = -1.5708; // -90 degrees
    final sweepAngle = 6.28318 * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _HeroCardGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final path = Path();
    path.moveTo(size.width * 0.45, size.height);
    path.cubicTo(
      size.width * 0.65,
      size.height * 0.35,
      size.width * 0.8,
      size.height * 0.85,
      size.width,
      size.height * 0.25,
    );
    path.lineTo(size.width, size.height);
    path.close();

    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          kNeutralAccent.withValues(alpha: 0.15),
          kNeutralAccentDark.withValues(alpha: 0.02),
        ],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(rect);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 4. Quick Actions Grid
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _QuickActionsGrid extends StatelessWidget {
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onStreamLink;

  const _QuickActionsGrid({
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onStreamLink,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            title: 'Open File',
            subtitle: 'Play a video file',
            icon: Icons.folder_open_rounded,
            onTap: onOpenFile,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _QuickActionCard(
            title: 'Open Folder',
            subtitle: 'Play from a folder',
            icon: Icons.folder_rounded,
            onTap: onOpenFolder,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _QuickActionCard(
            title: 'Stream from Link',
            subtitle: 'Play from a URL',
            icon: Icons.link_rounded,
            onTap: onStreamLink,
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        hoverColor: Colors.white.withValues(alpha: 0.02),
        splashColor: Colors.white.withValues(alpha: 0.05),
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          borderRadius: BorderRadius.circular(20),
          color: Colors.grey.withValues(alpha: 0.10),
          borderColor: Colors.grey.shade300.withValues(alpha: 0.14),
          blur: 10.0,
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: kNeutralAccent.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  icon,
                  color: kNeutralAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9D9F),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF75747C),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 5. Recent Files List
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _RecentFilesList extends StatelessWidget {
  final List<String> recentVideos;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onDelete;

  const _RecentFilesList({
    required this.recentVideos,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (recentVideos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No recent files',
          style: TextStyle(
            color: Color(0xFF8E8D94),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    }

    return Column(
      children: recentVideos.map((uri) {
        final title = formatMediaTitle(uri);
        final fileSpecs = _generateMockSpecs(uri);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: GlassContainer(
            borderRadius: BorderRadius.circular(16),
            color: Colors.grey.withValues(alpha: 0.10),
            borderColor: Colors.grey.shade300.withValues(alpha: 0.14),
            blur: 10.0,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onPlay(uri),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      // Video Thumbnail Badge with Soft Neutral Border
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFF1F1D27),
                          border: Border.all(
                            color: kNeutralAccent.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: kNeutralAccent,
                          size: 24,
                        ),
                      ),

                      const SizedBox(width: 16),

                      // File Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$fileSpecs • $uri',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8E8D94),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Play Button Icon
                      IconButton(
                        onPressed: () => onPlay(uri),
                        icon: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: kNeutralAccent,
                            size: 20,
                          ),
                        ),
                      ),

                      // Remove Button Icon
                      IconButton(
                        onPressed: () => onDelete(uri),
                        icon: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF9E9D9F),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _generateMockSpecs(String uri) {
    final lower = uri.toLowerCase();
    String ext = 'MKV';
    if (lower.endsWith('.mp4')) ext = 'MP4';
    if (lower.endsWith('.avi')) ext = 'AVI';
    if (lower.endsWith('.mov')) ext = 'MOV';
    return '$ext • 1080p • 1.2 GB';
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 6. Media Title Parser/Formatter Utility
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

String formatMediaTitle(String uri) {
  if (uri.isEmpty) return 'Unknown Title';

  String fileName = uri.split(Platform.pathSeparator).last;
  if (uri.startsWith('http://') || uri.startsWith('https://')) {
    fileName = uri.split('/').last;
    if (fileName.contains('?')) {
      fileName = fileName.split('?').first;
    }
  }

  try {
    fileName = Uri.decodeFull(fileName);
  } catch (_) {}

  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex != -1 && dotIndex > 0) {
    fileName = fileName.substring(0, dotIndex);
  }

  String title = fileName.replaceAll(RegExp(r'[\._\-]'), ' ');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

  final seasonEpisodeRegex = RegExp(
    r'\b(S\d+E\d+|S\d+|E\d+)\b',
    caseSensitive: false,
  );
  final seasonEpisodeMatch = seasonEpisodeRegex.firstMatch(title);

  if (seasonEpisodeMatch != null) {
    final matchText = seasonEpisodeMatch.group(0)!;
    final matchIndex = seasonEpisodeMatch.start;
    String mainTitle = title.substring(0, matchIndex).trim();
    String formattedSeasonEpisode = matchText.toUpperCase();

    if (mainTitle.isNotEmpty) {
      return '$mainTitle - $formattedSeasonEpisode';
    }
  }

  final yearRegex = RegExp(r'\b(19|20)\d{2}\b');
  final yearMatch = yearRegex.firstMatch(title);
  if (yearMatch != null) {
    final matchText = yearMatch.group(0)!;
    final matchIndex = yearMatch.start;
    String mainTitle = title.substring(0, matchIndex).trim();
    if (mainTitle.isNotEmpty) {
      return '$mainTitle ($matchText)';
    }
  }

  final tagsToRemove = RegExp(
    r'\b(1080p|720p|4k|2160p|480p|360p|x264|x265|h264|h265|hevc|vp9|av1|bluray|brrip|webrip|web\-dl|dvdrip|hdtv|bdrip|rip|aac|mp3|ac3|dts|dd5\.1)\b',
    caseSensitive: false,
  );
  title = title.replaceAll(tagsToRemove, '');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

  return title.isNotEmpty ? title : fileName;
}
