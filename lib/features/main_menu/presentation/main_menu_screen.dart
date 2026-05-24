import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'package:lexo_player/core/services/history_service.dart';
import 'package:lexo_player/features/video_player/providers/player_provider.dart';
import 'package:lexo_player/features/video_player/presentation/video_screen.dart';
import 'package:lexo_player/features/dictionary/presentation/download_hub_screen.dart';
import 'package:lexo_player/features/subtitles/providers/subtitle_providers.dart';

class MainMenuScreen extends ConsumerStatefulWidget {
  const MainMenuScreen({super.key});

  @override
  ConsumerState<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends ConsumerState<MainMenuScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isShowingUrlInput = false;

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
      allowedExtensions: ['mp4', 'mkv', 'avi', 'webm', 'mov'],
      dialogTitle: 'Open Video File',
    );
    
    if (result != null && result.files.single.path != null) {
      _openVideoScreen(result.files.single.path!);
    }
  }

  void _submitUrl() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      _openVideoScreen(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentVideos = ref.watch(recentVideosProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Library',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'LEXOPLAYER',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: theme.colorScheme.primary,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // Responsive layout of primary operations
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 600;
                        if (isWide) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: _LibraryActionCard(
                                  title: 'Open Local File',
                                  icon: Icons.folder_open_rounded,
                                  onTap: _pickLocalFile,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _LibraryActionCard(
                                  title: 'Stream from Link',
                                  icon: Icons.link_rounded,
                                  onTap: () {
                                    setState(() {
                                      _isShowingUrlInput = !_isShowingUrlInput;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _LibraryActionCard(
                                  title: 'Dictionary Hub',
                                  icon: Icons.book_rounded,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const DownloadHubScreen()),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _LibraryActionCard(
                                title: 'Open Local File',
                                icon: Icons.folder_open_rounded,
                                onTap: _pickLocalFile,
                              ),
                              const SizedBox(height: 12),
                              _LibraryActionCard(
                                title: 'Stream from Link',
                                icon: Icons.link_rounded,
                                onTap: () {
                                  setState(() {
                                    _isShowingUrlInput = !_isShowingUrlInput;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              _LibraryActionCard(
                                title: 'Dictionary Hub',
                                icon: Icons.book_rounded,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const DownloadHubScreen()),
                                  );
                                },
                              ),
                            ],
                          );
                        }
                      },
                    ),
                    
                    // URL Input field panel with M3 Card style
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: _isShowingUrlInput
                          ? Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(top: 24),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: theme.colorScheme.outlineVariant,
                                  width: 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _urlController,
                                        style: theme.textTheme.bodyMedium,
                                        decoration: InputDecoration(
                                          hintText: 'Enter media streaming link...',
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                          hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
                                        ),
                                        onSubmitted: (_) => _submitUrl(),
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: _submitUrl,
                                      style: FilledButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text('STREAM'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Continue Watching Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Continue Watching',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (recentVideos.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              ref.read(recentVideosProvider.notifier).clearHistory();
                            },
                            icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                            label: const Text('CLEAR ALL'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    if (recentVideos.isEmpty)
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.movie_filter_outlined,
                                  size: 48,
                                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No recent media playback detected.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: recentVideos.length,
                        itemBuilder: (context, index) {
                          final uri = recentVideos[index];
                          return _ContinueWatchingItemWidget(
                            uri: uri,
                            onTap: () => _openVideoScreen(uri),
                            onDelete: () {
                              ref.read(recentVideosProvider.notifier).removeMedia(uri);
                            },
                          );
                        },
                      ),
                    
                    const SizedBox(height: 48),
                    
                    // Simple Footer
                    Center(
                      child: Text(
                        'LexoPlayer  •  Structural Reading Framework\nOptimised for vocabulary acquisition through media exploration.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                          height: 1.5,
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
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Library Action Card Widget
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _LibraryActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _LibraryActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width >= 600;

    Widget content;
    if (isWide) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    } else {
      content = Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            icon,
            size: 28,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 16),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 16),
        ],
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: isWide ? 220 : double.infinity,
          height: isWide ? 130 : 64,
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Continue Watching Item Widget
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _ContinueWatchingItemWidget extends StatelessWidget {
  final String uri;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ContinueWatchingItemWidget({
    required this.uri,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = formatMediaTitle(uri);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 80,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.surfaceVariant,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(
              Icons.play_circle_outline_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            uri,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.play_arrow_rounded,
                  color: theme.colorScheme.primary,
                ),
                tooltip: 'Play',
                onPressed: onTap,
              ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: theme.colorScheme.error,
                ),
                tooltip: 'Remove',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Media Title Parser/Formatter
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

String formatMediaTitle(String uri) {
  if (uri.isEmpty) return 'Unknown Title';
  
  // 1. Get last segment (filename)
  String fileName = uri.split(Platform.pathSeparator).last;
  // If it's a URL and Split by PathSeparator doesn't work well due to web format:
  if (uri.startsWith('http://') || uri.startsWith('https://')) {
    fileName = uri.split('/').last;
    // Remove query params
    if (fileName.contains('?')) {
      fileName = fileName.split('?').first;
    }
  }
  
  // 2. Decode percent encoding if any
  try {
    fileName = Uri.decodeFull(fileName);
  } catch (_) {
    // If decoding fails, just use fileName as is
  }
  
  // 3. Remove extension
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex != -1 && dotIndex > 0) {
    fileName = fileName.substring(0, dotIndex);
  }
  
  // 4. Clean up common release tags, resolutions, and codecs
  // Normalize separators (dots, underscores, dashes) to spaces
  String title = fileName.replaceAll(RegExp(r'[\._\-]'), ' ');
  
  // Remove multiple spaces
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  
  // 5. Look for Season/Episode patterns: S02, S02E03, etc.
  final seasonEpisodeRegex = RegExp(
    r'\b(S\d+E\d+|S\d+|E\d+)\b',
    caseSensitive: false,
  );
  final seasonEpisodeMatch = seasonEpisodeRegex.firstMatch(title);
  
  if (seasonEpisodeMatch != null) {
    final matchText = seasonEpisodeMatch.group(0)!;
    final matchIndex = seasonEpisodeMatch.start;
    
    // Everything before the match is the main title
    String mainTitle = title.substring(0, matchIndex).trim();
    
    // Format the match (e.g. S02 -> S02, s02e03 -> S02E03)
    String formattedSeasonEpisode = matchText.toUpperCase();
    
    if (mainTitle.isNotEmpty) {
      return '$mainTitle - $formattedSeasonEpisode';
    }
  }
  
  // 6. Look for Movie Year pattern: e.g. 1999, 2024
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
  
  // 7. General cleanup of common media tags if no season/year was matched (or for movies)
  final tagsToRemove = RegExp(
    r'\b(1080p|720p|4k|2160p|480p|360p|x264|x265|h264|h265|hevc|vp9|av1|bluray|brrip|webrip|web\-dl|dvdrip|hdtv|bdrip|rip|aac|mp3|ac3|dts|dd5\.1)\b',
    caseSensitive: false,
  );
  title = title.replaceAll(tagsToRemove, '');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  
  return title.isNotEmpty ? title : fileName;
}
