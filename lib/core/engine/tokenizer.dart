/// A token produced by the engine tokenizer, mirroring the Python TokenInfo.
class EngineTokenInfo {
  final String token;
  final String lemma;
  final String pos;
  final String spacyPos;
  final int startChar;
  final int endChar;
  final int tokenIndex;

  const EngineTokenInfo({
    required this.token,
    required this.lemma,
    required this.pos,
    required this.spacyPos,
    required this.startChar,
    required this.endChar,
    required this.tokenIndex,
  });

  @override
  String toString() =>
      'EngineTokenInfo("$token", lemma="$lemma", pos=$pos, spacyPos=$spacyPos, '
      '[$startChar:$endChar], idx=$tokenIndex)';
}

/// Maps Universal Dependencies POS tags to Wiktionary-style POS.
const Map<String, String> posMap = {
  'NOUN': 'noun',
  'PROPN': 'noun',
  'VERB': 'verb',
  'AUX': 'verb',
  'ADJ': 'adj',
  'ADV': 'adv',
  'PRON': 'pronoun',
  'ADP': 'preposition',
  'CONJ': 'conjunction',
  'CCONJ': 'conjunction',
  'SCONJ': 'conjunction',
  'NUM': 'numeral',
  'INTJ': 'interjection',
  'DET': 'determiner',
  'PART': 'particle',
  'PUNCT': 'punctuation',
  'SYM': 'symbol',
  'X': 'other',
};

/// Common English verbs mapped to their base forms for lemmatization.
const Map<String, String> verbLemmas = {
  'is': 'be',
  'are': 'be',
  'was': 'be',
  'were': 'be',
  'been': 'be',
  'being': 'be',
  'am': 'be',
  'has': 'have',
  'had': 'have',
  'having': 'have',
  'does': 'do',
  'did': 'do',
  'done': 'do',
  'doing': 'do',
  'says': 'say',
  'said': 'say',
  'saying': 'say',
  'goes': 'go',
  'went': 'go',
  'gone': 'go',
  'going': 'go',
  'gets': 'get',
  'got': 'get',
  'gotten': 'get',
  'getting': 'get',
  'makes': 'make',
  'made': 'make',
  'making': 'make',
  'takes': 'take',
  'took': 'take',
  'taken': 'take',
  'taking': 'take',
  'comes': 'come',
  'came': 'come',
  'coming': 'come',
  'sees': 'see',
  'saw': 'see',
  'seen': 'see',
  'seeing': 'see',
  'knows': 'know',
  'knew': 'know',
  'known': 'know',
  'knowing': 'know',
  'thinks': 'think',
  'thought': 'think',
  'thinking': 'think',
  'wants': 'want',
  'wanted': 'want',
  'wanting': 'want',
  'looks': 'look',
  'looked': 'look',
  'looking': 'look',
  'uses': 'use',
  'used': 'use',
  'using': 'use',
  'finds': 'find',
  'found': 'find',
  'finding': 'find',
  'gives': 'give',
  'gave': 'give',
  'given': 'give',
  'giving': 'give',
  'tells': 'tell',
  'told': 'tell',
  'telling': 'tell',
  'works': 'work',
  'worked': 'work',
  'working': 'work',
  'calls': 'call',
  'called': 'call',
  'calling': 'call',
  'tries': 'try',
  'tried': 'try',
  'trying': 'try',
  'asks': 'ask',
  'asked': 'ask',
  'asking': 'ask',
  'needs': 'need',
  'needed': 'need',
  'needing': 'need',
  'feels': 'feel',
  'felt': 'feel',
  'feeling': 'feel',
  'becomes': 'become',
  'became': 'become',
  'becoming': 'become',
  'leaves': 'leave',
  'left': 'leave',
  'leaving': 'leave',
  'puts': 'put',
  'putting': 'put',
  'means': 'mean',
  'meant': 'mean',
  'meaning': 'mean',
  'keeps': 'keep',
  'kept': 'keep',
  'keeping': 'keep',
  'lets': 'let',
  'letting': 'let',
  'begins': 'begin',
  'began': 'begin',
  'begun': 'begin',
  'beginning': 'begin',
  'seems': 'seem',
  'seemed': 'seem',
  'seeming': 'seem',
  'helps': 'help',
  'helped': 'help',
  'helping': 'help',
  'shows': 'show',
  'showed': 'show',
  'shown': 'show',
  'showing': 'show',
  'hears': 'hear',
  'heard': 'hear',
  'hearing': 'hear',
  'plays': 'play',
  'played': 'play',
  'playing': 'play',
  'runs': 'run',
  'ran': 'run',
  'running': 'run',
  'moves': 'move',
  'moved': 'move',
  'moving': 'move',
  'lives': 'live',
  'lived': 'live',
  'living': 'live',
  'believes': 'believe',
  'believed': 'believe',
  'believing': 'believe',
  'holds': 'hold',
  'held': 'hold',
  'holding': 'hold',
  'brings': 'bring',
  'brought': 'bring',
  'bringing': 'bring',
  'happens': 'happen',
  'happened': 'happen',
  'happening': 'happen',
  'writes': 'write',
  'wrote': 'write',
  'written': 'write',
  'writing': 'write',
  'sits': 'sit',
  'sat': 'sit',
  'sitting': 'sit',
  'stands': 'stand',
  'stood': 'stand',
  'standing': 'stand',
  'loses': 'lose',
  'lost': 'lose',
  'losing': 'lose',
  'pays': 'pay',
  'paid': 'pay',
  'paying': 'pay',
  'meets': 'meet',
  'met': 'meet',
  'meeting': 'meet',
  'includes': 'include',
  'included': 'include',
  'including': 'include',
  'continues': 'continue',
  'continued': 'continue',
  'continuing': 'continue',
  'sets': 'set',
  'setting': 'set',
  'learns': 'learn',
  'learned': 'learn',
  'learnt': 'learn',
  'learning': 'learn',
  'changes': 'change',
  'changed': 'change',
  'changing': 'change',
  'leads': 'lead',
  'led': 'lead',
  'leading': 'lead',
  'understands': 'understand',
  'understood': 'understand',
  'understanding': 'understand',
  'watches': 'watch',
  'watched': 'watch',
  'watching': 'watch',
  'follows': 'follow',
  'followed': 'follow',
  'following': 'follow',
  'stops': 'stop',
  'stopped': 'stop',
  'stopping': 'stop',
  'creates': 'create',
  'created': 'create',
  'creating': 'create',
  'speaks': 'speak',
  'spoke': 'speak',
  'spoken': 'speak',
  'speaking': 'speak',
  'reads': 'read',
  'reading': 'read',
  'spends': 'spend',
  'spent': 'spend',
  'spending': 'spend',
  'grows': 'grow',
  'grew': 'grow',
  'grown': 'grow',
  'growing': 'grow',
  'opens': 'open',
  'opened': 'open',
  'opening': 'open',
  'walks': 'walk',
  'walked': 'walk',
  'walking': 'walk',
  'wins': 'win',
  'won': 'win',
  'winning': 'win',
  'offers': 'offer',
  'offered': 'offer',
  'offering': 'offer',
  'remembers': 'remember',
  'remembered': 'remember',
  'remembering': 'remember',
  'loves': 'love',
  'loved': 'love',
  'loving': 'love',
  'considers': 'consider',
  'considered': 'consider',
  'considering': 'consider',
  'appears': 'appear',
  'appeared': 'appear',
  'appearing': 'appear',
  'buys': 'buy',
  'bought': 'buy',
  'buying': 'buy',
  'waits': 'wait',
  'waited': 'wait',
  'waiting': 'wait',
  'serves': 'serve',
  'served': 'serve',
  'serving': 'serve',
  'dies': 'die',
  'died': 'die',
  'dying': 'die',
  'sends': 'send',
  'sent': 'send',
  'sending': 'send',
  'expects': 'expect',
  'expected': 'expect',
  'expecting': 'expect',
  'falls': 'fall',
  'fell': 'fall',
  'fallen': 'fall',
  'falling': 'fall',
  'cuts': 'cut',
  'cutting': 'cut',
  'reaches': 'reach',
  'reached': 'reach',
  'reaching': 'reach',
  'kills': 'kill',
  'killed': 'kill',
  'killing': 'kill',
  'stays': 'stay',
  'stayed': 'stay',
  'staying': 'stay',
  'returns': 'return',
  'returned': 'return',
  'returning': 'return',
  'eats': 'eat',
  'ate': 'eat',
  'eaten': 'eat',
  'eating': 'eat',
};

/// Common English nouns and their singular forms.
const Map<String, String> nounLemmas = {
  'men': 'man',
  'women': 'woman',
  'children': 'child',
  'people': 'person',
  'mice': 'mouse',
  'geese': 'goose',
  'feet': 'foot',
  'teeth': 'tooth',
  'lights': 'light',
  'lives': 'life',
  'wives': 'wife',
  'knives': 'knife',
  'thieves': 'thief',
  'leaves': 'leaf',
  'wolves': 'wolf',
  'halves': 'half',
  'calves': 'calf',
  'shelves': 'shelf',
  'classes': 'class',
  'buses': 'bus',
  'dishes': 'dish',
  'watches': 'watch',
  'boxes': 'box',
  'foxes': 'fox',
  'churches': 'church',
  'branches': 'branch',
  'sandwiches': 'sandwich',
  'potatoes': 'potato',
  'tomatoes': 'tomato',
  'heroes': 'hero',
  'torpedoes': 'torpedo',
  'volcanoes': 'volcano',
  'analyses': 'analysis',
  'bases': 'basis',
  'crises': 'crisis',
  'diagnoses': 'diagnosis',
  'oases': 'oasis',
  'theses': 'thesis',
  'phenomena': 'phenomenon',
  'criteria': 'criterion',
  'data': 'datum',
  'alumni': 'alumnus',
  'fungi': 'fungus',
  'nuclei': 'nucleus',
  'stimuli': 'stimulus',
  'syllabi': 'syllabus',
  'termini': 'terminus',
  'virtues': 'virtue',
  'values': 'value',
  'things': 'thing',
  'times': 'time',
  'days': 'day',
  'years': 'year',
  'worlds': 'world',
  'ways': 'way',
  'works': 'work',
  'words': 'word',
  'places': 'place',
  'cases': 'case',
  'problems': 'problem',
  'points': 'point',
  'groups': 'group',
  'companies': 'company',
  'numbers': 'number',
  'systems': 'system',
  'programs': 'program',
  'questions': 'question',
  'government': 'government',
  'countries': 'country',
  'stories': 'story',
  'facts': 'fact',
  'months': 'month',
  'lot': 'lot',
  'bits': 'bit',
  'cities': 'city',
  'members': 'member',
  'players': 'player',
  'teams': 'team',
  'games': 'game',
  'schools': 'school',
  'students': 'student',
  'teachers': 'teacher',
  'books': 'book',
  'movies': 'movie',
  'songs': 'song',
  'ideas': 'idea',
  'parts': 'part',
  'hands': 'hand',
  'eyes': 'eye',
  'heads': 'head',
  'faces': 'face',
  'bodies': 'body',
  'minds': 'mind',
  'hearts': 'heart',
  'doors': 'door',
  'windows': 'window',
  'tables': 'table',
  'chairs': 'chair',
  'rooms': 'room',
  'houses': 'house',
  'cars': 'car',
  'trees': 'tree',
  'flowers': 'flower',
  'dogs': 'dog',
  'cats': 'cat',
  'birds': 'bird',
  'fish': 'fish',
  'horses': 'horse',
};

/// Common irregular adjectives.
const Map<String, String> adjLemmas = {
  'better': 'good',
  'best': 'good',
  'worse': 'bad',
  'worst': 'bad',
  'bigger': 'big',
  'biggest': 'big',
  'smaller': 'small',
  'smallest': 'small',
  'faster': 'fast',
  'fastest': 'fast',
  'slower': 'slow',
  'slowest': 'slow',
  'stronger': 'strong',
  'strongest': 'strong',
  'weaker': 'weak',
  'weakest': 'weak',
  'longer': 'long',
  'longest': 'long',
  'shorter': 'short',
  'shortest': 'short',
  'higher': 'high',
  'highest': 'high',
  'lower': 'low',
  'lowest': 'low',
  'older': 'old',
  'oldest': 'old',
  'newer': 'new',
  'newest': 'new',
  'younger': 'young',
  'youngest': 'young',
  'easier': 'easy',
  'easiest': 'easy',
  'harder': 'hard',
  'hardest': 'hard',
  'happier': 'happy',
  'happiest': 'happy',
  'sadder': 'sad',
  'saddest': 'sad',
  'hotter': 'hot',
  'hottest': 'hot',
  'colder': 'cold',
  'coldest': 'cold',
  'brighter': 'bright',
  'brightest': 'bright',
  'darker': 'dark',
  'darkest': 'dark',
  'deeper': 'deep',
  'deepest': 'deep',
  'clearer': 'clear',
  'clearest': 'clear',
  'louder': 'loud',
  'loudest': 'loud',
  'quieter': 'quiet',
  'quietest': 'quiet',
  'richer': 'rich',
  'richest': 'rich',
  'poorer': 'poor',
  'poorest': 'poor',
  'heavier': 'heavy',
  'heaviest': 'heavy',
  'lighter': 'light',
  'lightest': 'light',
  'nicer': 'nice',
  'nicest': 'nice',
  'rare': 'rare',
};

/// Simple English POS tagger using word patterns and common word lists.
///
/// This is a heuristic-based tagger sufficient for subtitle text. It uses:
/// 1. Common word lists for closed-class words (determiners, prepositions, etc.)
/// 2. Suffix rules for open-class words (-ing, -ed, -ly, -tion, etc.)
/// 3. Capitalization heuristic for proper nouns
class SimplePosTagger {
  // Closed-class word sets for reliable POS assignment
  static final Set<String> _determiners = {
    'the',
    'a',
    'an',
    'this',
    'that',
    'these',
    'those',
    'my',
    'your',
    'his',
    'her',
    'its',
    'our',
    'their',
    'some',
    'any',
    'no',
    'every',
    'each',
    'all',
    'both',
    'few',
    'more',
    'most',
    'much',
    'many',
    'such',
    'what',
    'which',
    'whose',
    'whatever',
    'whichever',
  };

  static final Set<String> _pronouns = {
    'i',
    'me',
    'my',
    'mine',
    'myself',
    'you',
    'your',
    'yours',
    'yourself',
    'he',
    'him',
    'his',
    'himself',
    'she',
    'her',
    'hers',
    'herself',
    'it',
    'its',
    'itself',
    'we',
    'us',
    'our',
    'ours',
    'ourselves',
    'they',
    'them',
    'their',
    'theirs',
    'themselves',
    'who',
    'whom',
    'whose',
    'which',
    'that',
    'what',
    'whatever',
    'whoever',
    'whomever',
    'this',
    'that',
    'these',
    'those',
    'myself',
    'yourself',
    'himself',
    'herself',
    'itself',
    'ourselves',
    'themselves',
  };

  static final Set<String> _prepositions = {
    'in',
    'on',
    'at',
    'to',
    'for',
    'with',
    'by',
    'from',
    'of',
    'about',
    'into',
    'through',
    'during',
    'before',
    'after',
    'above',
    'below',
    'between',
    'under',
    'over',
    'up',
    'down',
    'out',
    'off',
    'near',
    'behind',
    'beside',
    'beyond',
    'against',
    'along',
    'among',
    'around',
    'before',
    'behind',
    'below',
    'beneath',
    'beside',
    'besides',
    'beyond',
    'concerning',
    'despite',
    'during',
    'except',
    'excluding',
    'following',
    'inside',
    'into',
    'like',
    'minus',
    'near',
    'onto',
    'outside',
    'over',
    'past',
    'pending',
    'per',
    'plus',
    'regarding',
    'round',
    'since',
    'through',
    'throughout',
    'till',
    'toward',
    'towards',
    'under',
    'underneath',
    'until',
    'unto',
    'upon',
    'using',
    'via',
    'within',
    'without',
  };

  static final Set<String> _conjunctions = {
    'and',
    'or',
    'but',
    'nor',
    'yet',
    'so',
    'for',
    'although',
    'because',
    'since',
    'unless',
    'until',
    'while',
    'after',
    'before',
    'when',
    'where',
    'how',
    'if',
    'whether',
    'than',
    'though',
    'even',
    'once',
    'as',
    'whereas',
    'whereby',
  };

  static final Set<String> _auxiliaries = {
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'being',
    'am',
    'has',
    'have',
    'had',
    'having',
    'does',
    'do',
    'did',
    'will',
    'would',
    'shall',
    'should',
    'can',
    'could',
    'may',
    'might',
    'must',
    'need',
    'dare',
    'ought',
    'used',
  };

  static final Set<String> _adverbs = {
    'not',
    'also',
    'very',
    'often',
    'never',
    'always',
    'sometimes',
    'really',
    'already',
    'just',
    'still',
    'even',
    'only',
    'almost',
    'quite',
    'too',
    'here',
    'there',
    'now',
    'then',
    'soon',
    'today',
    'yesterday',
    'tomorrow',
    'ago',
    'later',
    'earlier',
    'probably',
    'certainly',
    'definitely',
    'perhaps',
    'maybe',
    'actually',
    'basically',
    'simply',
    'quickly',
    'slowly',
    'easily',
    'hardly',
    'barely',
    'recently',
    'finally',
    'suddenly',
    'immediately',
    'eventually',
    'usually',
    'generally',
    'normally',
    'typically',
    'apparently',
    'obviously',
    'clearly',
    'simply',
    'highly',
    'extremely',
    'really',
    'enough',
    'rather',
    'pretty',
    'fairly',
    'mostly',
    'entirely',
    'completely',
    'absolutely',
    'totally',
    'utterly',
  };

  static final Set<String> _interjections = {
    'oh',
    'wow',
    'hey',
    'hi',
    'hello',
    'goodbye',
    'bye',
    'yes',
    'no',
    'okay',
    'ok',
    'well',
    'alas',
    'ouch',
    'hmm',
    'huh',
    'ah',
    'ugh',
    'phew',
    'oops',
  };

  /// Tags a word with a universal POS tag.
  ///
  /// Uses closed-class word lists first, then suffix heuristics.
  /// Handles contractions (isn't, don't, I'm, etc.) as special cases.
  /// [atSentenceStart] suppresses the PROPN heuristic for capitalized words
  /// at the beginning of a sentence.
  static String tagWord(String word,
      {bool atSentenceStart = false, String? nextWord}) {
    final lower = word.toLowerCase();

    // Contraction handling (must come before closed-class lists)
    final contractionPos = _contractionPos(lower);
    if (contractionPos != null) return contractionPos;

    // Closed-class words (most reliable)
    if (_determiners.contains(lower)) return 'DET';
    if (_pronouns.contains(lower)) return 'PRON';
    if (_auxiliaries.contains(lower)) return 'AUX';
    if (_prepositions.contains(lower)) return 'ADP';
    if (_conjunctions.contains(lower)) return 'CCONJ';
    if (_adverbs.contains(lower)) return 'ADV';
    if (_interjections.contains(lower)) return 'INTJ';

    // Punctuation
    if (RegExp(r'^[^\w]+$').hasMatch(word)) return 'PUNCT';

    // Numbers
    if (RegExp(r'^\d+\.?\d*$').hasMatch(word)) return 'NUM';

    // Capitalized word — proper noun heuristic, but NOT at sentence start
    // (where capitalized words are just normal English sentence capitalization).
    if (!atSentenceStart &&
        word.length > 1 &&
        word[0] == word[0].toUpperCase() &&
        word[0] != word[0].toLowerCase()) {
      return 'PROPN';
    }

    // Suffix-based heuristics for open-class words
    return _suffixTag(lower);
  }

  /// Returns the POS for a contraction, or null if not a contraction.
  static String? _contractionPos(String lower) {
    // Verb negation contractions: isn't, don't, can't, won't, etc.
    if (_verbNegationContractions.contains(lower)) return 'AUX';
    // Modal/verb contractions: 'll, 've, 'd after pronouns
    if (_verbModalContractions.contains(lower)) return 'AUX';
    // Pronoun contractions: I'm, you're, he's, she's, etc.
    if (_pronounContractions.contains(lower)) return 'PRON';
    // "let's" is a verb + pronoun
    if (lower == "let's") return 'VERB';
    return null;
  }

  // Verb negation contractions: word + 't
  static final Set<String> _verbNegationContractions = {
    "isn't",
    "aren't",
    "wasn't",
    "weren't",
    "don't",
    "doesn't",
    "didn't",
    "can't",
    "couldn't",
    "won't",
    "wouldn't",
    "shouldn't",
    "hasn't",
    "haven't",
    "hadn't",
    "mustn't",
    "needn't",
    "ain't",
  };

  // Verb/modal contractions: pronoun + 've, 'll, 'd, 're, 's (verb forms)
  static final Set<String> _verbModalContractions = {
    "we've",
    "they've",
    "you've",
    "we'll",
    "they'll",
    "you'll",
    "we'd",
    "they'd",
    "you'd",
  };

  // Pronoun contractions: I'm, I've, I'll, I'd, he's, she's, it's, etc.
  static final Set<String> _pronounContractions = {
    "i'm",
    "i've",
    "i'll",
    "i'd",
    "he's",
    "she's",
    "it's",
    "he'll",
    "she'll",
    "it'll",
    "he'd",
    "she'd",
    "it'd",
    "that's",
    "who's",
    "what's",
    "there's",
  };

  static String _suffixTag(String word) {
    // Hyphenated compound words ending in -ed (near-sighted, well-known, etc.) are Adjectives
    if (word.contains('-') && word.endsWith('ed')) return 'ADJ';

    // Verbs
    if (word.endsWith('ing') && word.length > 4) return 'VERB';
    if (word.endsWith('ed') && word.length > 3) return 'VERB';
    if (word.endsWith('ize') || word.endsWith('ise')) return 'VERB';
    if (word.endsWith('ify')) return 'VERB';
    if (word.endsWith('ate') && word.length > 4) return 'VERB';

    // Adjectives
    if (word.endsWith('ful') || word.endsWith('less')) return 'ADJ';
    if (word.endsWith('ous') || word.endsWith('ive')) return 'ADJ';
    if (word.endsWith('able') || word.endsWith('ible')) return 'ADJ';
    if (word.endsWith('al') && word.length > 4) return 'ADJ';
    if (word.endsWith('ish') && word.length > 4) return 'ADJ';
    if (word.endsWith('ic') && word.length > 3) return 'ADJ';

    // Adverbs
    if (word.endsWith('ly') && word.length > 3) return 'ADV';

    // Nouns (default fallback for most suffixes)
    if (word.endsWith('tion') || word.endsWith('sion')) return 'NOUN';
    if (word.endsWith('ment') || word.endsWith('ness')) return 'NOUN';
    if (word.endsWith('ity') || word.endsWith('ty')) return 'NOUN';
    if (word.endsWith('ence') || word.endsWith('ance')) return 'NOUN';
    if (word.endsWith('er') && word.length > 3) return 'NOUN';
    if (word.endsWith('or') && word.length > 3) return 'NOUN';
    if (word.endsWith('ist') && word.length > 4) return 'NOUN';
    if (word.endsWith('ism') && word.length > 4) return 'NOUN';
    if (word.endsWith('age') && word.length > 4) return 'NOUN';

    // Default: noun
    return 'NOUN';
  }
}

/// Engine tokenizer that produces tokens with POS, lemma, and char offsets.
///
/// Dart port of the Python `EngineTokenizer` from `core/tokenizer.py`.
/// Uses regex-based tokenization + heuristic POS tagging + suffix-based
/// lemmatization (no spaCy dependency).
class EngineTokenizer {
  /// Regex that splits text into word and separator tokens with char offsets.
  static final RegExp _tokenPattern = RegExp(r"([\w'-]+)|([^\w'-]+)");

  /// Tokenizes [text] into a list of [EngineTokenInfo]s.
  ///
  /// Each token has a character offset relative to the input text.
  /// Tracks sentence boundaries to avoid tagging sentence-start words as PROPN.
  List<EngineTokenInfo> tokenize(String text) {
    final tokens = <EngineTokenInfo>[];
    int tokenIndex = 0;
    bool atSentenceStart = true;

    for (final match in _tokenPattern.allMatches(text)) {
      final word = match.group(1);
      final sep = match.group(2);

      if (word != null) {
        final startChar = match.start;
        final endChar = match.end;
        final spacyPos = SimplePosTagger.tagWord(
          word,
          atSentenceStart: atSentenceStart,
        );
        final wiktionaryPos = posMap[spacyPos] ?? spacyPos.toLowerCase();
        final lemma = _lemmatize(word, spacyPos);

        tokens.add(EngineTokenInfo(
          token: word,
          lemma: lemma,
          pos: wiktionaryPos,
          spacyPos: spacyPos,
          startChar: startChar,
          endChar: endChar,
          tokenIndex: tokenIndex,
        ));
        tokenIndex++;
        atSentenceStart = false;
      } else if (sep != null) {
        // Track sentence boundaries: after . ! ? or at start
        final trimmed = sep.trim();
        if (trimmed == '.' ||
            trimmed == '!' ||
            trimmed == '?' ||
            trimmed == '…' ||
            trimmed == '...') {
          atSentenceStart = true;
        }
      }
    }

    return tokens;
  }

  /// Filters tokens to only those whose character range falls within
  /// [targetStartChar] and [targetEndChar].
  List<EngineTokenInfo> filterTargetTokens(
    List<EngineTokenInfo> tokens,
    int targetStartChar,
    int targetEndChar,
  ) {
    return tokens
        .where(
            (t) => t.startChar >= targetStartChar && t.endChar <= targetEndChar)
        .toList();
  }

  /// Contraction-to-lemma map: maps contraction forms to their base word.
  /// Used so contractions can be looked up in the dictionary by lemma.
  static final Map<String, String> _contractionLemmas = {
    // Verb negation contractions → base verb
    "isn't": "be", "aren't": "be", "wasn't": "be", "weren't": "be",
    "don't": "do", "doesn't": "do", "didn't": "do",
    "can't": "can", "couldn't": "can",
    "won't": "will", "wouldn't": "would",
    "shouldn't": "should",
    "hasn't": "have", "haven't": "have", "hadn't": "have",
    "mustn't": "must", "needn't": "need",
    "ain't": "be",
    // Pronoun + be contractions
    "i'm": "be", "he's": "be", "she's": "be", "it's": "be",
    "that's": "be", "who's": "be", "what's": "be", "there's": "be",
    // Pronoun + have contractions
    "i've": "have", "you've": "have", "we've": "have", "they've": "have",
    // Pronoun + will contractions
    "i'll": "will", "you'll": "will", "he'll": "will", "she'll": "will",
    "it'll": "will", "we'll": "will", "they'll": "will",
    // Pronoun + would contractions
    "i'd": "would", "you'd": "would", "he'd": "would", "she'd": "would",
    "it'd": "would", "we'd": "would", "they'd": "would",
    // Special cases
    "let's": "let",
    "here's": "be", "there's": "be",
  };

  /// Lemmatizes a word based on its POS tag.
  String _lemmatize(String word, String spacyPos) {
    final lower = word.toLowerCase();

    // Contraction lemmatization (highest priority)
    if (_contractionLemmas.containsKey(lower)) {
      return _contractionLemmas[lower]!;
    }

    // Check lookup tables first
    if (spacyPos == 'VERB' || spacyPos == 'AUX') {
      if (verbLemmas.containsKey(lower)) return verbLemmas[lower]!;
    }
    if (spacyPos == 'NOUN' || spacyPos == 'PROPN') {
      if (nounLemmas.containsKey(lower)) return nounLemmas[lower]!;
    }
    if (spacyPos == 'ADJ') {
      if (adjLemmas.containsKey(lower)) return adjLemmas[lower]!;
    }

    // Suffix-based lemmatization
    return _suffixLemma(lower, spacyPos);
  }

  /// Rule-based suffix lemmatization.
  String _suffixLemma(String word, String pos) {
    if (word.length <= 3) return word;

    if (pos == 'VERB' || pos == 'AUX') {
      // -ing: running -> run, making -> make
      if (word.endsWith('ing') && word.length > 4) {
        final stem = word.substring(0, word.length - 3);
        if (stem.isNotEmpty) {
          // doubling consonant: running -> runn -> run
          if (stem.length >= 2 &&
              stem[stem.length - 1] == stem[stem.length - 2]) {
            return stem.substring(0, stem.length - 1);
          }
          // -ying: dying -> die
          if (stem.endsWith('y'))
            return '${stem.substring(0, stem.length - 1)}ie';
          // -e dropping: making -> mak -> make
          if (!stem.endsWith('e')) return '${stem}e';
          return stem;
        }
      }
      // -ed: walked -> walk, agreed -> agree, scurried -> scurry
      if (word.endsWith('ied') && word.length > 4) {
        return '${word.substring(0, word.length - 3)}y';
      }
      if (word.endsWith('ed') && word.length > 3) {
        final stem = word.substring(0, word.length - 2);
        if (stem.isNotEmpty) {
          // doubling: stopped -> stopp -> stop
          if (stem.length >= 2 &&
              stem[stem.length - 1] == stem[stem.length - 2]) {
            return stem.substring(0, stem.length - 1);
          }
          // -e dropping: agreed -> agre -> agree
          if (!stem.endsWith('e')) return '${stem}e';
          return stem;
        }
      }
      // -s: walks -> walk, runs -> run
      if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) {
        return word.substring(0, word.length - 1);
      }
    }

    if (pos == 'NOUN' || pos == 'PROPN') {
      // -ies -> -y
      if (word.endsWith('ies') && word.length > 4) {
        return '${word.substring(0, word.length - 3)}y';
      }
      // -es -> -e or -s
      if (word.endsWith('es') && word.length > 3) {
        final stem = word.substring(0, word.length - 2);
        if (stem.endsWith('s') ||
            stem.endsWith('x') ||
            stem.endsWith('z') ||
            stem.endsWith('sh') ||
            stem.endsWith('ch')) {
          return stem; // buses -> bus
        }
        return '${stem}e'; // boxes -> boxe? no... boxes -> box
      }
      // -s (not -ss, -us, -is)
      if (word.endsWith('s') &&
          !word.endsWith('ss') &&
          !word.endsWith('us') &&
          !word.endsWith('is') &&
          word.length > 3) {
        return word.substring(0, word.length - 1);
      }
    }

    if (pos == 'ADJ') {
      // -er -> base
      if (word.endsWith('er') && word.length > 4) {
        final stem = word.substring(0, word.length - 2);
        if (stem.endsWith('i')) return '${stem.substring(0, stem.length - 1)}y';
        if (!stem.endsWith('e')) return '${stem}e';
        return stem;
      }
      // -est -> base
      if (word.endsWith('est') && word.length > 5) {
        final stem = word.substring(0, word.length - 3);
        if (stem.endsWith('i')) return '${stem.substring(0, stem.length - 1)}y';
        if (!stem.endsWith('e')) return '${stem}e';
        return stem;
      }
      // -ly -> (adjective from adverb, rare)
      if (word.endsWith('ly') && word.length > 4) {
        return word.substring(0, word.length - 2);
      }
    }

    if (pos == 'ADV') {
      // -ly -> adjective
      if (word.endsWith('ly') && word.length > 4) {
        return word.substring(0, word.length - 2);
      }
    }

    return word;
  }
}

/// Sliding window context for a subtitle line, matching the Python
/// `SlidingWindowContext` from `parser/subtitle_parser.py`.
class SlidingWindowContext {
  final int subtitleId;
  final String timestamp;
  final String targetSentence;
  final String slidingContextWindow;
  final int targetStartChar;
  final int targetEndChar;

  const SlidingWindowContext({
    required this.subtitleId,
    required this.timestamp,
    required this.targetSentence,
    required this.slidingContextWindow,
    required this.targetStartChar,
    required this.targetEndChar,
  });
}

/// Creates a sliding window context from a list of subtitle items.
///
/// Concatenates prev + target + next subtitle texts with spaces,
/// and tracks the character offsets of the target sentence within
/// that combined window. This is critical for WSD and MWE detection
/// as it provides surrounding context.
///
/// Port of `SubtitleParser.create_sliding_window_context()` from
/// `parser/subtitle_parser.py`.
SlidingWindowContext createSlidingWindowContext({
  required int subtitleId,
  required String timestamp,
  required String targetText,
  String? prevText,
  String? nextText,
}) {
  final prefix = (prevText != null && prevText.isNotEmpty) ? '$prevText ' : '';
  final suffix = (nextText != null && nextText.isNotEmpty) ? ' $nextText' : '';

  final targetStartChar = prefix.length;
  final targetEndChar = targetStartChar + targetText.length;
  final slidingContext = '$prefix$targetText$suffix';

  return SlidingWindowContext(
    subtitleId: subtitleId,
    timestamp: timestamp,
    targetSentence: targetText,
    slidingContextWindow: slidingContext,
    targetStartChar: targetStartChar,
    targetEndChar: targetEndChar,
  );
}
