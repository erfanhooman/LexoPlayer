import 'package:lexo_player/core/models/subtitle_block.dart';

/// Provides O(log N) lookup into a sorted [SubtitleBlock] list.
///
/// Subtitle blocks are expected to be sorted by [SubtitleBlock.startTime] in
/// ascending order (the output of [SubtitleParser.parseSrt] / [parseVtt]).
class BinarySearchSync {
  BinarySearchSync._();

  /// Returns the index of the [SubtitleBlock] that contains [position], or
  /// `null` if the position falls in a gap between blocks (or the list is
  /// empty).
  ///
  /// A block is considered *active* when:
  /// ```
  /// block.startTime <= position <= block.endTime
  /// ```
  ///
  /// **Complexity:** O(log N) where N = `blocks.length`.
  static int? findActiveIndex(
    List<SubtitleBlock> blocks,
    Duration position,
  ) {
    if (blocks.isEmpty) return null;

    int low = 0;
    int high = blocks.length - 1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final block = blocks[mid];

      if (position < block.startTime) {
        // Position is before this block — search left.
        high = mid - 1;
      } else if (position > block.endTime) {
        // Position is after this block — search right.
        low = mid + 1;
      } else {
        // position >= startTime && position <= endTime → active block.
        return mid;
      }
    }

    // Position is in a gap between two blocks.
    return null;
  }

  /// Returns the index of the first [SubtitleBlock] whose [startTime] is at
  /// or after [position].
  ///
  /// Useful after a seek operation to find the next upcoming subtitle. If all
  /// blocks are before [position], returns `blocks.length` (one past the end).
  ///
  /// **Complexity:** O(log N).
  static int findInsertionPoint(
    List<SubtitleBlock> blocks,
    Duration position,
  ) {
    int low = 0;
    int high = blocks.length;

    while (low < high) {
      final mid = (low + high) ~/ 2;

      if (blocks[mid].startTime < position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    return low;
  }
}
