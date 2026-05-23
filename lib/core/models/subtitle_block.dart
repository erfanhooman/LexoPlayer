/// Represents a single subtitle cue in a video.
///
/// Each [SubtitleBlock] maps to one timed text entry in an SRT or WebVTT
/// subtitle file. The [startTime] and [endTime] delimit the window during
/// which the [text] should be displayed on screen.
class SubtitleBlock {
  /// Timestamp at which this subtitle should appear.
  final Duration startTime;

  /// Timestamp at which this subtitle should disappear.
  final Duration endTime;

  /// The displayed subtitle text (may span multiple lines, joined by spaces).
  final String text;

  /// Creates an immutable [SubtitleBlock].
  const SubtitleBlock({
    required this.startTime,
    required this.endTime,
    required this.text,
  });

  @override
  String toString() => 'SubtitleBlock($startTime -> $endTime: "$text")';
}
