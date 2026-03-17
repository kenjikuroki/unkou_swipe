import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_data.dart';
import 'prefs_helper.dart';

class ApiService {
  static const String _baseUrl = 'https://script.google.com/macros/s/AKfycbxK_LaasUY5sgqXD7k_nrth8nXORYhlEHXo_hoYH1PECD6qG2q3arGyld5psRz8NiXT2A/exec';
  Future<AppData?> loadAppData(String appId) async {
    // 1. Try to fetch from network
    try {
      final url = Uri.parse('$_baseUrl?id=$appId');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final jsonString = response.body;
        // Save to cache
        await PrefsHelper.saveAppDataCache(jsonString);
        return AppData.fromJson(json.decode(jsonString));
      }
    } catch (e) {
      debugPrint('ApiService: Network error - $e');
    }

    // 2. If network fails, try to load from cache
    final cachedJson = await PrefsHelper.getAppDataCache();
    if (cachedJson != null) {
      try {
        return AppData.fromJson(json.decode(cachedJson));
      } catch (e) {
        debugPrint('ApiService: Cache error - $e');
      }
    }

    // 3. Fallback to asset if cache is also null
    if (kDebugMode) {
      debugPrint('ApiService: Using fallback asset data for $appId');
    }
    try {
      final fallbackString = await rootBundle.loadString('assets/fallback_data.json');
      return AppData.fromJson(json.decode(fallbackString));
    } catch (e) {
      debugPrint('ApiService: Fallback asset error - $e');
    }

    return null;
  }
}
