// services/bookmark_service.dart
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class BookmarkService {
  static const String _lastPathKey = 'last_local_path';
  static const String _bookmarksKey = 'folder_bookmarks';

  // Save the last accessed path
  static Future<void> saveLastPath(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPathKey, path);
      print('💾 Saved last path: $path');
    } catch (e) {
      print('⚠️ Could not save last path: $e');
    }
  }

  // Get the last accessed path
  static Future<String?> getLastPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_lastPathKey);
      print('📂 Retrieved last path: $path');
      return path;
    } catch (e) {
      print('⚠️ Could not retrieve last path: $e');
      return null;
    }
  }

  // Get a safe starting directory that the app can access
  static Future<String> getSafeStartDirectory() async {
    if (Platform.isMacOS || Platform.isLinux) {
        // Get ACTUAL home directory, not sandbox
        final home = Platform.environment['HOME'];
        if (home == null) return '/';
        
        // These directories should be accessible with proper entitlements
        final candidates = [
        '$home/Downloads',
        '$home/Documents', 
        '$home/Desktop',
        '$home/Music',
        '$home/Pictures',
        home,
        ];

        for (final path in candidates) {
        // Make sure path doesn't contain 'Containers' (sandbox)
        if (path.contains('Containers')) continue;
        
        final dir = Directory(path);
        if (await dir.exists()) {
            try {
            // Test if we can actually list the directory
            await dir.list().first.timeout(const Duration(seconds: 1));
            print('✅ Found accessible directory: $path');
            return path;
            } catch (e) {
            print('⚠️ Cannot access $path: $e');
            continue;
            }
        }
        }
        
        // If nothing works, return home and let user browse
        return home;
    } else if (Platform.isWindows) {
        final home = Platform.environment['USERPROFILE'] ?? 'C:\\';
        return '$home\\Downloads';
    } else {
        return '/storage/emulated/0/Download';
    }
    }

  // Check if we can access a directory
  static Future<bool> canAccessDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return false;
      
      // Try to list contents
      await dir.list().first;
      return true;
    } catch (e) {
      return false;
    }
  }
}