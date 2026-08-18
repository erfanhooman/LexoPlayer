import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/core/engine/idiom_explainer.dart';
import 'package:lexo_player/core/models/engine_output.dart';

void main() {
  group('Inflection Redirect Resolution Tests', () {
    test('parseInflectionRedirect extracts base form and note correctly', () {
      const def = 'simple past and past participle of make quick work of';
      final redirect = parseInflectionRedirect(def);

      expect(redirect, isNotNull);
      expect(redirect!.baseForm, 'make quick work of');
      expect(redirect.inflectionNote, def);
    });

    test('parseInflectionRedirect handles clean targets with trailing periods or notes', () {
      const def = 'simple past of polish off (to remove polish)';
      final redirect = parseInflectionRedirect(def);

      expect(redirect, isNotNull);
      expect(redirect!.baseForm, 'polish off');
      expect(redirect.inflectionNote, def);
    });

    test('SpanModel and ParentMeaning preserve inflectionNote and baseForm', () {
      const parent = ParentMeaning(
        definitionEn: 'To complete or consume something quickly.',
        translationFa: 'به سرعت کار چیزی را تمام کردن',
        inflectionNote: 'simple past and past participle of make quick work of',
        baseForm: 'make quick work of',
      );

      final span = SpanModel(
        spanId: 'span_01',
        type: SpanType.multiWordSpan,
        category: 'IDIOM',
        text: 'made quick work of',
        startChar: 0,
        endChar: 18,
        parentMeaning: parent,
        inflectionNote: parent.inflectionNote,
        baseForm: parent.baseForm,
      );

      expect(span.inflectionNote, 'simple past and past participle of make quick work of');
      expect(span.baseForm, 'make quick work of');
      expect(span.parentMeaning!.definitionEn, 'To complete or consume something quickly.');

      // Test JSON round-trip
      final jsonMap = span.toJson();
      final roundTripSpan = SpanModel.fromJson(jsonMap);

      expect(roundTripSpan.inflectionNote, span.inflectionNote);
      expect(roundTripSpan.baseForm, span.baseForm);
      expect(roundTripSpan.parentMeaning!.definitionEn, span.parentMeaning!.definitionEn);
    });
  });
}
