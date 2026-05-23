import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHistoryKey = 'lexo_recent_videos_v1';
const _kMaxHistoryItems = 10;

/// Provider that exposes the list of recently played media (paths or URLs).
final recentVideosProvider = StateNotifierProvider<HistoryNotifier, List<String>>((ref) {
  return HistoryNotifier();
});

class HistoryNotifier extends StateNotifier<List<String>> {
  HistoryNotifier() : super([]) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_kHistoryKey) ?? [];
    state = items;
  }

  Future<void> addMedia(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Create a new list, removing the item if it already exists to move it to the top
    final updatedList = List<String>.from(state)..remove(uri);
    updatedList.insert(0, uri);
    
    // Truncate to max items
    if (updatedList.length > _kMaxHistoryItems) {
      updatedList.removeRange(_kMaxHistoryItems, updatedList.length);
    }
    
    await prefs.setStringList(_kHistoryKey, updatedList);
    state = updatedList;
  }

  Future<void> removeMedia(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedList = List<String>.from(state)..remove(uri);
    await prefs.setStringList(_kHistoryKey, updatedList);
    state = updatedList;
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHistoryKey);
    state = [];
  }
}
