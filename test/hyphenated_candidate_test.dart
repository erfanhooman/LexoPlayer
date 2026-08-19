import 'package:flutter_test/flutter_test.dart';
import 'package:lexo_player/core/engine/tokenizer.dart';

void main() {
  group('Hyphenated and Compound Word Lookup Tests', () {
    test('Tokenizer tags hyphenated compound -ed words as ADJ', () {
      final tokenizer = EngineTokenizer();
      final tokens = tokenizer.tokenize('The future was too near-sighted');
      final nearSightedToken =
          tokens.firstWhere((t) => t.token == 'near-sighted');

      expect(nearSightedToken.spacyPos, 'ADJ');
      expect(nearSightedToken.pos, 'adj');
      expect(nearSightedToken.lemma, 'near-sighted');
    });
  });
}
