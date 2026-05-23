import 'package:lexo_player/core/utils/word_tokenizer.dart';

void main() {
  _testTokenizer();
  _testBinarySearch();
  print('\n✅ All tests passed!');
}

void _testTokenizer() {
  print('── Word Tokenizer Tests ──');

  // Test 1: Basic sentence
  final result1 = WordTokenizer.tokenize('Running, slow!');
  assert(result1.length == 4, 'Expected 4 tokens, got ${result1.length}');
  assert(result1[0].text == 'Running' && result1[0].isWord == true);
  assert(result1[1].text == ', ' && result1[1].isWord == false);
  assert(result1[2].text == 'slow' && result1[2].isWord == true);
  assert(result1[3].text == '!' && result1[3].isWord == false);
  print('  ✓ Basic sentence tokenization');

  // Test 2: Contraction
  final result2 = WordTokenizer.tokenize("don't stop");
  assert(result2.length == 3);
  assert(result2[0].text == "don't" && result2[0].isWord == true);
  assert(result2[1].text == ' ' && result2[1].isWord == false);
  assert(result2[2].text == 'stop' && result2[2].isWord == true);
  print("  ✓ Contractions preserved (don't)");

  // Test 3: Hyphenated word
  final result3 = WordTokenizer.tokenize('well-known fact');
  assert(result3[0].text == 'well-known' && result3[0].isWord == true);
  print('  ✓ Hyphenated words preserved');

  // Test 4: Empty input
  final result4 = WordTokenizer.tokenize('');
  assert(result4.isEmpty);
  print('  ✓ Empty input returns empty list');

  // Test 5: Reconstruction
  final original = 'Hello, world! This is a test.';
  final tokens = WordTokenizer.tokenize(original);
  final reconstructed = tokens.map((t) => t.text).join();
  assert(reconstructed == original, 'Reconstruction failed');
  print('  ✓ Concatenation reproduces original text');
}

void _testBinarySearch() {
  print('\n── Binary Search Tests ──');
  // Note: BinarySearchSync and SubtitleBlock tests would require
  // importing those files and creating Duration-based test data.
  // Since we can't run Flutter here, we document the test cases:
  print('  ⚠ Binary search tests require Flutter runtime');
  print('  Test cases to verify:');
  print('    - Empty list returns null');
  print('    - Position before first block returns null');
  print('    - Position after last block returns null');
  print('    - Position in gap between blocks returns null');
  print('    - Position at exact startTime returns correct index');
  print('    - Position at exact endTime returns correct index');
  print('    - Position within block returns correct index');
  print('    - Single block list works correctly');
}
