import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/core/models/engine_output.dart';

/// Verifies that the Dart engine models consume the EXACT JSON structure
/// produced by the Python LexoEngine (`cli.py` sample output).
void main() {
  test('Dart models parse the real Python engine JSON output', () {
    final raw =
        File('test/fixtures/python_engine_sample.json').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final output = EngineOutput.fromJson(json);

    // Top-level fields
    expect(output.subtitleId, 1);
    expect(output.targetSentence,
        'John decided to bite the proverbial bullet yesterday.');
    expect(output.hierarchicalSpans.length, 5);

    // Span types present
    final types = output.hierarchicalSpans.map((s) => s.type).toSet();
    expect(types, contains(SpanType.singleWord));
    expect(types, contains(SpanType.multiWordSpan));

    // Single-word span (John)
    final john = output.hierarchicalSpans.firstWhere((s) => s.text == 'John');
    expect(john.type, SpanType.singleWord);
    expect(john.lemma, 'john');
    expect(john.pos, 'NOUN');
    expect(john.startChar, 0);
    expect(john.endChar, 4);
    expect(john.wsd.length, 5);
    expect(john.wsd.first.rank, 1);
    expect(john.wsd.first.definitionEn, contains('john'));
    expect(john.childrenSubTokens, isEmpty);

    // Multi-word span (idiom)
    final idiom = output.hierarchicalSpans
        .firstWhere((s) => s.type == SpanType.multiWordSpan);
    expect(idiom.category, 'IDIOM');
    expect(idiom.canonicalForm, 'bite the bullet');
    expect(idiom.parentMeaning, isNotNull);
    expect(idiom.parentMeaning!.definitionEn, isNotEmpty);
    expect(idiom.parentMeaning!.translationFa, contains('سختی'));
    expect(idiom.childrenSubTokens.length, 4);

    final bite = idiom.childrenSubTokens.first;
    expect(bite.token, 'bite');
    expect(bite.pos, 'VERB');
    expect(bite.wsd.length, 5);

    // Round-trip: toJson must reproduce the same field structure
    final roundTrip = output.toJson();
    expect(roundTrip['subtitle_id'], 1);
    expect(roundTrip['timestamp'], isA<String>());
    expect(roundTrip['target_sentence'], output.targetSentence);
    expect(roundTrip['sliding_context_window'], output.slidingContextWindow);
    expect(roundTrip['execution_time_ms'], isA<num>());
    expect(roundTrip['hierarchical_spans'], isA<List>());
    expect((roundTrip['hierarchical_spans'] as List).length, 5);
  });
}
