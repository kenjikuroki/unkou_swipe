import 'package:shared_preferences/shared_preferences.dart';

class PrefsHelper {
  static const String _keyWeakQuestions = 'weak_questions';
  static const String _keyAdCounter = 'ad_counter';
  static const String _keyOfferShownV1 = 'special_offer_shown_v1';
  static const String _keyTutorialShown = 'tutorial_shown_v1';
  static const String _keyAppData = 'cached_app_data';

  static Future<void> saveAppDataCache(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppData, json);
  }

  static Future<String?> getAppDataCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAppData);
  }

  static Future<bool> shouldShowInterstitial() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt(_keyAdCounter) ?? 0;
    current++;
    await prefs.setInt(_keyAdCounter, current);
    return (current % 2 == 0);
  }
  
  static Future<void> saveHighScore(String categoryKey, int score) async {
    final prefs = await SharedPreferences.getInstance();
    final currentHigh = prefs.getInt(categoryKey) ?? 0;
    if (score > currentHigh) {
      await prefs.setInt(categoryKey, score);
    }
  }

  static Future<int> getHighScore(String categoryKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(categoryKey) ?? 0;
  }

  static Future<void> addWeakQuestions(List<String> questions) async {
    if (questions.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final List<String> current = prefs.getStringList(_keyWeakQuestions) ?? [];
    
    bool changed = false;
    for (final q in questions) {
      if (!current.contains(q)) {
        current.add(q);
        changed = true;
      }
    }
    
    if (changed) {
      await prefs.setStringList(_keyWeakQuestions, current);
    }
  }

  static Future<void> removeWeakQuestions(List<String> questions) async {
    if (questions.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final List<String> current = prefs.getStringList(_keyWeakQuestions) ?? [];
    
    bool changed = false;
    for (final q in questions) {
       if (current.remove(q)) {
         changed = true;
       }
    }
    
    if (changed) {
      await prefs.setStringList(_keyWeakQuestions, current);
    }
  }

  static Future<List<String>> getWeakQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyWeakQuestions) ?? [];
  }

  // --- Special Offer Persistence ---

  static Future<bool> isSpecialOfferShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOfferShownV1) ?? false;
  }

  static Future<void> markSpecialOfferShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOfferShownV1, true);
  }

  static Future<bool> isTutorialShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyTutorialShown) ?? false;
  }

  static Future<void> markTutorialShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTutorialShown, true);
  }
  static const String _keyQuizCompletionCount = 'quiz_completion_count';

  static Future<int> incrementQuizCompletionCount() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt(_keyQuizCompletionCount) ?? 0;
    current++;
    await prefs.setInt(_keyQuizCompletionCount, current);
    return current;
  }

  static Future<int> getQuizCompletionCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyQuizCompletionCount) ?? 0;
  }

  static Future<bool> shouldShowReviewPrompt() async {
    final count = await getQuizCompletionCount();
    return count == 3;
  }
}
