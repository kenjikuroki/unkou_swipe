import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_data.dart';
import 'prefs_helper.dart';
import '../config/gas_config.dart';

class ApiService {
  static String get _baseUrl => GasConfig.baseUrl;

  // キャッシュ優先で即座に返す（ネットワーク不使用）
  Future<AppData?> loadFromCacheOrFallback(String appId) async {
    final cachedJson = await PrefsHelper.getAppDataCache();
    if (cachedJson != null) {
      try {
        final data = AppData.fromJson(json.decode(cachedJson));
        if (_hasValidQuestions(data)) return data;
        debugPrint('ApiService: Cache has empty questions, falling back to asset');
      } catch (e) {
        debugPrint('ApiService: Cache parse error - $e');
      }
    }

    // キャッシュなし or 無効データ → バンドルされたassetを使用
    if (kDebugMode) debugPrint('ApiService: Using bundled fallback for $appId');
    try {
      final url = Uri.parse('$_baseUrl?id=$appId');
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = _parseUsableAppData(response.body, appId);
        if (data != null) {
          await PrefsHelper.saveAppDataCache(response.body);
          debugPrint('ApiService: Network fetch successful for $appId');
          return data;
        }
      }
    } catch (e) {
      debugPrint('ApiService: Network fetch failed - $e');
    }

    return null;
  }

  // バックグラウンドでGASから取得しキャッシュを更新（次回起動に反映）
  void refreshInBackground(String appId) {
    _fetchAndCache(appId);
  }

  Future<void> _fetchAndCache(String appId) async {
    try {
      final url = Uri.parse('$_baseUrl?id=$appId');
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        // questionsが空のレスポンスはキャッシュしない（GAS側の不具合対策）
        final data = AppData.fromJson(json.decode(response.body));
        if (_hasValidQuestions(data)) {
          await PrefsHelper.saveAppDataCache(response.body);
          debugPrint('ApiService: Background refresh successful');
        } else {
          debugPrint('ApiService: Background refresh returned empty questions, cache not updated');
        }
      }
    } catch (e) {
      debugPrint('ApiService: Background refresh failed - $e');
    }
  }

  bool _hasValidQuestions(AppData data) {
    return data.questions.values.any((list) => list.isNotEmpty);
  }
}
