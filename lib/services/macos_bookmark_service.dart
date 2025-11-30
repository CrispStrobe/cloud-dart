// services/macos_bookmark_service.dart
import 'dart:io';
import 'dart:convert'; // Import for base64
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';

class MacOSBookmarkService {
  static const String _bookmarkDataKey = 'macos_bookmark_data_v2';
  static const String _bookmarkPathKey = 'macos_bookmark_path_v2'; 
  static final _bookmarks = SecureBookmarks();

  // Request access to a directory and save the bookmark
  static Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    if (!Platform.isMacOS) return null;

    try {
      final String? directoryPath = await getDirectoryPath(
        initialDirectory: initialDirectory,
        confirmButtonText: 'Grant Access',
      );

      if (directoryPath != null) {
        // bookmark() returns a String (base64)
        final String bookmarkData = await _bookmarks.bookmark(File(directoryPath));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_bookmarkDataKey, bookmarkData);
        await prefs.setString(_bookmarkPathKey, directoryPath); 
        
        print('✅ User granted access and saved bookmark for: $directoryPath');
        return directoryPath;
      }

      return null;
    } catch (e) {
      print('❌ Error requesting directory access: $e');
      return null;
    }
  }

  // Get the last granted directory path (fast, no I/O)
  static Future<String?> getLastGrantedDirectory() async {
    if (!Platform.isMacOS) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_bookmarkPathKey);
    } catch (e) {
      print('⚠️ Could not retrieve last granted directory path: $e');
      return null;
    }
  }

  // Helper for LocalFileService to get the resolved bookmark
  static Future<FileSystemEntity?> getResolvedBookmark() async {
     if (!Platform.isMacOS) return null;
     try {
        final prefs = await SharedPreferences.getInstance();
        final bookmarkBase64 = prefs.getString(_bookmarkDataKey);
        
        if (bookmarkBase64 == null) {
          print('📂 No saved bookmark found.');
          return null;
        }

        // --- FIX: resolveBookmark returns a FileSystemEntity ---
        // There is no .isStale or .file property.
        final resolvedFile = await _bookmarks.resolveBookmark(bookmarkBase64);
        return resolvedFile;
        // --- END FIX ---

     } catch (e) {
        print('⚠️ Could not retrieve or resolve last granted directory: $e');
        await clearBookmarks(); // Clear bad bookmark
        return null;
     }
  }


  // Check if we have access to a directory (by checking if it's under a granted path)
  static Future<bool> hasAccessToPath(String path) async {
    final grantedPath = await getLastGrantedDirectory();
    if (grantedPath == null) return false;

    // Check if path is under the granted directory
    return path.startsWith(grantedPath);
  }

  // Clear saved bookmarks
  static Future<void> clearBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bookmarkDataKey);
    await prefs.remove(_bookmarkPathKey);
  }
}