// lib/services/webdav_config_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class WebDavConfigService {
  final String configPath;

  WebDavConfigService({required this.configPath});

  Future<Map<String, String>?> readCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('webdav_credentials');
    if (jsonStr == null) return null;
    return Map<String, String>.from(json.decode(jsonStr));
  }

  Future<void> saveCredentials(Map<String, String> creds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webdav_credentials', json.encode(creds));
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('webdav_credentials');
  }
}