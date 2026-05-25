import 'package:lexo_player/core/utils/stemmer_utils.dart';

void main() {
  testCleanToken();
  print('\n✅ Dictionary Lookup Tests passed!');
}

void testCleanToken() {
  print('── Dictionary Lookup - cleanToken Tests ──');

  // Test 1: Simple word with punctuation
  final res1 = StemmerUtils.cleanToken('Funeral!');
  assert(res1 == 'funeral', 'Expected "funeral", got "$res1"');
  print('  ✓ Simple word with punctuation lowercased and stripped');

  // Test 2: Phrase with spaces and punctuation
  final res2 = StemmerUtils.cleanToken('I had no voice in that matter.');
  assert(res2 == 'i had no voice in that matter', 'Expected "i had no voice in that matter", got "$res2"');
  print('  ✓ Phrase with spaces and punctuation preserved');

  // Test 3: Hyphenated compound word
  final res3 = StemmerUtils.cleanToken('able-bodied');
  assert(res3 == 'able-bodied', 'Expected "able-bodied", got "$res3"');
  print('  ✓ Hyphenated compound word preserved');

  // Test 4: Compound word with spaces
  final res4 = StemmerUtils.cleanToken('able bodied');
  assert(res4 == 'able bodied', 'Expected "able bodied", got "$res4"');
  print('  ✓ Spaced compound word preserved');

  // Test 5: Extra spaces normalized
  final res5 = StemmerUtils.cleanToken('  able   bodied  ');
  assert(res5 == 'able bodied', 'Expected "able bodied", got "$res5"');
  print('  ✓ Extra spaces trimmed and collapsed');
  
  // Test 6: Word with apostrophe
  final res6 = StemmerUtils.cleanToken("it's okay");
  assert(res6 == "it's okay", "Expected \"it's okay\", got \"$res6\"");
  print('  ✓ Apostrophes preserved');
}
