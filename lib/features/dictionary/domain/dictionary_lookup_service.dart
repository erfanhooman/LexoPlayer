import 'package:lexo_player/core/models/dictionary_result.dart';
import 'package:lexo_player/features/dictionary/data/dual_dictionary_repository.dart';
import 'package:lexo_player/features/dictionary/domain/word_candidate_generator.dart';
import 'package:lexo_player/core/utils/word_tokenizer.dart';

/// Orchestrates dictionary lookup requests by generating candidate phrases
/// via [IWordCandidateGenerator] and querying the underlying [DualDictionaryRepository].
class DictionaryLookupService {
  final DualDictionaryRepository _repository;
  final IWordCandidateGenerator _candidateGenerator;

  /// Creates a [DictionaryLookupService] with the given [_repository] and optional [_candidateGenerator].
  const DictionaryLookupService({
    required DualDictionaryRepository repository,
    IWordCandidateGenerator candidateGenerator = const WordCandidateGenerator(),
  })  : _repository = repository,
        _candidateGenerator = candidateGenerator;

  /// Performs a multi-candidate dictionary lookup for a given line of tokens and target word index.
  ///
  /// Returns an empty list if the repository is not ready or no candidates are found.
  Future<List<DictionaryResult>> lookupToken({
    required List<TokenSpan> lineTokens,
    required int targetIndex,
  }) async {
    if (!_repository.isReady) {
      return const [];
    }

    final candidates = _candidateGenerator.generateCandidates(lineTokens, targetIndex);
    if (candidates.isEmpty) {
      return const [];
    }

    return _repository.lookupMultiple(candidates);
  }
}
