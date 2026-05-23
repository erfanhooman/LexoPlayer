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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF070709), // Ultra-dark charcoal
      body: Stack(
        children: [
          // ── Background Grid ──────────────────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _EditorialGridPainter(),
              ),
            ),
          ),

          // ── Glowing Radial Blur (Top Left) ──────────────────────────
          Positioned(
            left: -150,
            top: -150,
            child: IgnorePointer(
              child: Container(
                width: 450,
                height: 450,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF5500).withValues(alpha: 0.04),
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            ),
          ),

          // ── Glowing Radial Blur (Bottom Right) ──────────────────────
          Positioned(
            right: -100,
            bottom: -100,
            child: IgnorePointer(
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF5500).withValues(alpha: 0.03),
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            ),
          ),
          
          // ── Massive Watermark ──────────────────────────────────────────
          Positioned(
            right: -size.width * 0.04,
            bottom: -size.height * 0.03,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'LEXO',
                    style: TextStyle(
                      fontSize: size.width * 0.22,
                      fontWeight: FontWeight.w900,
                      color: const Color(0x02FFFFFF), // 2% opacity
                      height: 0.8,
                      letterSpacing: -12,
                      fontFamily: 'Helvetica Neue',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 32),
                    child: Text(
                      'THE ART OF READING MEDIA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0x06FFFFFF),
                        letterSpacing: 10,
                        fontFamily: 'Helvetica Neue',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // ── Main Content Layout ───────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 54, vertical: 48),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column (History & Main Nav)
                  Expanded(
                    flex: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Library.',
                          style: TextStyle(
                            fontSize: 68,
                            fontWeight: FontWeight.w300,
                            color: Colors.white,
                            fontFamily: 'Georgia',
                            letterSpacing: -2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: 44,
                          height: 2,
                          color: const Color(0xFFFF5500),
                        ),
                        const SizedBox(height: 48),
                        
                        // Recent Videos Title Bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'RECENT LOGS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white30,
                                letterSpacing: 4,
                              ),
                            ),
                            if (recentVideos.isNotEmpty)
                              TextButton.icon(
                                onPressed: () {
                                  ref.read(recentVideosProvider.notifier).clearHistory();
                                },
                                icon: const Icon(Icons.delete_sweep_rounded, size: 14, color: Colors.white30),
                                label: const Text(
                                  'CLEAR ALL',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white30,
                                    letterSpacing: 2,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (recentVideos.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                              'No recent media playback detected.',
                              style: TextStyle(
                                color: Colors.white24,
                                fontStyle: FontStyle.italic,
                                fontFamily: 'Georgia',
                                fontSize: 15,
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.builder(
                              itemCount: recentVideos.length,
                              physics: const BouncingScrollPhysics(),
                              itemBuilder: (context, index) {
                                final uri = recentVideos[index];
                                return _HistoryItemWidget(
                                  index: index + 1,
                                  uri: uri,
                                  onTap: () => _openVideoScreen(uri),
                                  onDelete: () {
                                    ref.read(recentVideosProvider.notifier).removeMedia(uri);
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Asymmetric spacing
                  const Spacer(flex: 2),

                  // Right Column (Actions Index)
                  Expanded(
                    flex: 10,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'INDEX OF OPERATIONS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white30,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          _EditorialActionButton(
                            number: '01',
                            title: 'OPEN LOCAL FILE',
                            onTap: _pickLocalFile,
                          ),
                          
                          _EditorialActionButton(
                            number: '02',
                            title: 'STREAM FROM LINK',
                            onTap: () {
                              setState(() {
                                _isShowingUrlInput = !_isShowingUrlInput;
                              });
                            },
                          ),
                          
                          // Custom Slide/Fade URL Input Panel
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            height: _isShowingUrlInput ? 64 : 0,
                            margin: EdgeInsets.only(
                              top: _isShowingUrlInput ? 16 : 0,
                              bottom: _isShowingUrlInput ? 16 : 0,
                            ),
                            clipBehavior: Clip.hardEdge,
                            decoration: const BoxDecoration(),
                            child: AnimatedOpacity(
                              opacity: _isShowingUrlInput ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: const Color(0xFFFF5500).withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF5500).withValues(alpha: 0.05),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _urlController,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontFamily: 'Helvetica Neue',
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: 'Enter media streaming link...',
                                          hintStyle: TextStyle(color: Colors.white24),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 16),
                                        ),
                                        onSubmitted: (_) => _submitUrl(),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _submitUrl,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF5500),
                                          borderRadius: BorderRadius.circular(18),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFF5500).withValues(alpha: 0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Text(
                                          'STREAM',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          _EditorialActionButton(
                            number: '03',
                            title: 'DICTIONARY HUB',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const DownloadHubScreen()),
                              );
                            },
                          ),
                          
                          const Spacer(),
                          
                          // Premium layout description footer
                          const Text(
                            'LexoPlayer / Structural Reading Framework.\nOptimised for vocabulary acquisition through media exploration.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white24,
                              height: 1.5,
                              fontFamily: 'Georgia',
                              fontStyle: FontStyle.italic,
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
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Background Grid Painter (Magazine Grid Layout)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _EditorialGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 1.0;

    // Draw vertical columns (magazine grid lines)
    const columns = 6;
    final spacing = size.width / columns;
    for (var i = 1; i < columns; i++) {
      canvas.drawLine(
        Offset(i * spacing, 0),
        Offset(i * spacing, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Editorial Action Button Widget
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _EditorialActionButton extends StatefulWidget {
  final String number;
  final String title;
  final VoidCallback onTap;

  const _EditorialActionButton({
    required this.number,
    required this.title,
    required this.onTap,
  });

  @override
  State<_EditorialActionButton> createState() => _EditorialActionButtonState();
}

class _EditorialActionButtonState extends State<_EditorialActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: _isHovered ? const Color(0xFFFF5500) : Colors.white.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                widget.number,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _isHovered ? const Color(0xFFFF5500) : Colors.white24,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontFamily: 'Helvetica Neue',
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: _isHovered ? Colors.white : Colors.white54,
                  ),
                  child: Text(widget.title),
                ),
              ),
              AnimatedRotation(
                turns: _isHovered ? 0.125 : 0.0, // Slight rotation on hover
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.arrow_outward_rounded,
                  color: _isHovered ? const Color(0xFFFF5500) : Colors.white24,
                  size: 20,
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
//  Detailed History Log Item Widget
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _HistoryItemWidget extends StatefulWidget {
  final int index;
  final String uri;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryItemWidget({
    required this.index,
    required this.uri,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_HistoryItemWidget> createState() => _HistoryItemWidgetState();
}

class _HistoryItemWidgetState extends State<_HistoryItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final fileName = widget.uri.split(Platform.pathSeparator).last;
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _isHovered ? Colors.white.withValues(alpha: 0.02) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Text(
              widget.index.toString().padLeft(2, '0'),
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 14,
                fontWeight: FontWeight.w300,
                color: _isHovered ? const Color(0xFFFF5500) : Colors.white24,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: GestureDetector(
                onTap: widget.onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Helvetica Neue',
                        fontSize: 15,
                        fontWeight: _isHovered ? FontWeight.bold : FontWeight.normal,
                        color: _isHovered ? Colors.white : Colors.white70,
                      ),
                    ),
                    if (_isHovered) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.uri,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Helvetica Neue',
                          fontSize: 11,
                          color: Colors.white24,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_isHovered) ...[
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                color: Colors.white24,
                hoverColor: Colors.redAccent.withValues(alpha: 0.15),
                tooltip: 'Remove from history',
                onPressed: widget.onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
