import 'package:lexo_player/core/models/engine_output.dart';

/// Serializes engine output into the JSON format expected by the UI.
///
/// Port of `parser/serializer.py` from LexoEngine.
class EngineSerializer {
  /// Formats the engine output into a JSON-compatible map.
  static Map<String, dynamic> formatOutput({
    required int subtitleId,
    required String timestamp,
    required String targetSentence,
    required String slidingContextWindow,
    required double executionTimeMs,
    required List<SpanModel> hierarchicalSpans,
  }) {
    return {
      'subtitle_id': subtitleId,
      'timestamp': timestamp,
      'target_sentence': targetSentence,
      'sliding_context_window': slidingContextWindow,
      'execution_time_ms': double.parse(executionTimeMs.toStringAsFixed(2)),
      'hierarchical_spans': hierarchicalSpans.map((s) => s.toJson()).toList(),
    };
  }

  /// Creates an [EngineOutput] from the engine pipeline results.
  static EngineOutput createOutput({
    required int subtitleId,
    required String timestamp,
    required String targetSentence,
    required String slidingContextWindow,
    required double executionTimeMs,
    required List<SpanModel> hierarchicalSpans,
  }) {
    return EngineOutput(
      subtitleId: subtitleId,
      timestamp: timestamp,
      targetSentence: targetSentence,
      slidingContextWindow: slidingContextWindow,
      executionTimeMs: double.parse(executionTimeMs.toStringAsFixed(2)),
      hierarchicalSpans: hierarchicalSpans,
    );
  }
}
