import 'dart:collection';

/// Aho-Corasick multi-pattern string matching automaton.
///
/// Port of the `pyahocorasick` library used in `core/mwe_fast.py`.
/// Builds a trie with failure links for O(n) substring matching.
///
/// Usage:
/// ```dart
/// final automaton = AhoCorasick();
/// automaton.addWord('bite the bullet', 'bite the bullet');
/// automaton.addWord('kick the bucket', 'kick the bucket');
/// automaton.build();
///
/// for (final match in automaton.iter('he decided to bite the bullet')) {
///   print('Match at ${match.index}: ${match.value}');
/// }
/// ```
class AhoCorasick<T> {
  final _root = _Node<T>();
  bool _isBuilt = false;

  /// Adds a word with an associated value to the automaton.
  ///
  /// Must be called before [build].
  void addWord(String word, T value) {
    assert(!_isBuilt, 'Cannot add words after build()');
    var node = _root;
    for (final ch in word.codeUnits) {
      node = node.children.putIfAbsent(ch, () => _Node<T>());
    }
    node.output = value;
    node.isEnd = true;
    node.depth = word.length;
  }

  /// Builds failure links for the automaton.
  ///
  /// Must be called after all [addWord] calls and before [iter].
  void build() {
    if (_isBuilt) return;

    final queue = Queue<_Node<T>>();

    // Initialize depth-1 children of root with root as failure link
    for (final entry in _root.children.entries) {
      entry.value.failure = _root;
      queue.add(entry.value);
    }

    // BFS to build failure links
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();

      for (final entry in current.children.entries) {
        final ch = entry.key;
        final child = entry.value;

        var fail = current.failure;
        while (fail != null && !fail.children.containsKey(ch)) {
          fail = fail.failure;
        }

        child.failure = fail?.children[ch] ?? _root;

        // Merge output from failure link (for pattern overlaps)
        if (child.failure!.isEnd && child.output == null) {
          child.output = child.failure!.output;
        }

        queue.add(child);
      }
    }

    _isBuilt = true;
  }

  /// Iterates over all matches in [text].
  ///
  /// Returns an iterable of [AhoMatch] objects, each containing:
  /// - `index`: the end index of the match in [text]
  /// - `value`: the value associated with the matched pattern
  Iterable<AhoMatch<T>> iter(String text) sync* {
    assert(_isBuilt, 'Call build() before iter()');

    var node = _root;

    for (int i = 0; i < text.length; i++) {
      final ch = text.codeUnitAt(i);

      while (node != _root && !node.children.containsKey(ch)) {
        node = node.failure!;
      }

      node = node.children[ch] ?? _root;

      // Follow failure chain to find all matching patterns
      var temp = node;
      while (temp != _root) {
        if (temp.isEnd && temp.output != null) {
          yield AhoMatch<T>(
            index: i,
            length: temp.depth,
            value: temp.output as T,
          );
        }
        temp = temp.failure!;
      }
    }
  }

  /// Clears the automaton, removing all words and resetting state.
  void clear() {
    _root.children.clear();
    _isBuilt = false;
  }
}

/// A match found by the Aho-Corasick automaton.
class AhoMatch<T> {
  /// End index of the match in the text.
  final int index;

  /// Length of the matched pattern.
  final int length;

  /// The value associated with the matched pattern.
  final T value;

  const AhoMatch({
    required this.index,
    required this.length,
    required this.value,
  });

  /// Start index of the match in the text.
  int get startIndex => index - length + 1;

  @override
  String toString() =>
      'AhoMatch(start=$startIndex, end=$index, length=$length, value=$value)';
}

/// Internal trie node for the Aho-Corasick automaton.
class _Node<T> {
  final Map<int, _Node<T>> children = {};
  _Node<T>? failure;
  T? output;
  bool isEnd = false;
  int depth = 0;
}
