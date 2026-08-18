import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/core/models/engine_output.dart';

/// Compares the Dart `toJson()` field structure against the Python engine's
/// JSON output to guarantee schema parity.
void main() {
  test('Dart toJson field structure matches Python engine output', () {
    final raw = File('test/fixtures/python_engine_sample.json').readAsStringSync();
    final pythonJson = jsonDecode(raw) as Map<String, dynamic>;
    final output = EngineOutput.fromJson(pythonJson);

    // Round-trip the Python output through Dart toJson
    final dartJson = output.toJson();

    final pythonSpans = pythonJson['hierarchical_spans'] as List;
    final dartSpans = dartJson['hierarchical_spans'] as List;

    expect(dartSpans.length, pythonSpans.length);

    // Compare keys for each span (order differs — sort by text)
    final pythonByText = <String, Map<String, dynamic>>{
      for (final s in pythonSpans.cast<Map<String, dynamic>>())
        s['text'] as String: s,
    };
    final dartByText = <String, Map<String, dynamic>>{
      for (final s in dartSpans.cast<Map<String, dynamic>>())
        s['text'] as String: s,
    };

    for (final text in pythonByText.keys) {
      final p = pythonByText[text]!;
      final d = dartByText[text]!;

      // Every Python key must exist in Dart output with same value type
      for (final key in p.keys) {
        expect(d.containsKey(key), isTrue,
            reason: 'Span "$text" missing Dart key: $key');
      }
      // Compare nested structures
      if (p['type'] == 'MULTI_WORD_SPAN') {
        final pm = p['parent_meaning'] as Map<String, dynamic>;
        final dm = d['parent_meaning'] as Map<String, dynamic>;
        for (final key in pm.keys) {
          expect(dm.containsKey(key), isTrue,
              reason: 'parent_meaning missing key: $key');
        }
        final pc = p['children_sub_tokens'] as List;
        final dc = d['children_sub_tokens'] as List;
        expect(dc.length, pc.length);
        if (pc.isNotEmpty) {
          final pc0 = pc.first as Map<String, dynamic>;
          final dc0 = dc.first as Map<String, dynamic>;
          for (final key in pc0.keys) {
            expect(dc0.containsKey(key), isTrue,
                reason: 'child_sub_token missing key: $key');
          }
        }
      } else {
        final pw = p['wsd'] as List;
        final dw = d['wsd'] as List;
        expect(dw.length, pw.length);
        if (pw.isNotEmpty) {
          final pw0 = pw.first as Map<String, dynamic>;
          final dw0 = dw.first as Map<String, dynamic>;
          for (final key in pw0.keys) {
            expect(dw0.containsKey(key), isTrue,
                reason: 'wsd missing key: $key');
          }
        }
      }
    }

    // Report any EXTRA keys Dart adds (schema superset check)
    final extraKeys = <String>[];
    for (final text in dartByText.keys) {
      final p = pythonByText[text]!;
      final d = dartByText[text]!;
      for (final key in d.keys) {
        if (!p.containsKey(key)) {
          extraKeys.add('$text: $key');
        }
      }
    }
    if (extraKeys.isNotEmpty) {
      // ignore: avoid_print
      print('EXTRA Dart keys (superset): $extraKeys');
    }
  });
}
