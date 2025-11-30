// services/share_service.dart
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'dart:io';

class ShareService {
  static Future<void> shareFiles(List<String> filePaths) async {
    if (filePaths.isEmpty) return;
    
    // Check if sharing is supported on this platform
    if (!Platform.isAndroid && !Platform.isIOS) {
      print('⚠️ File sharing not fully supported on ${Platform.operatingSystem}');
      // On desktop, we can still try share_plus but it might open default app
    }
    
    try {
      final files = filePaths.map((path) => XFile(path)).toList();
      
      if (files.length == 1) {
        await Share.shareXFiles(files, text: 'Shared from Internxt');
      } else {
        await Share.shareXFiles(files, text: 'Shared ${files.length} files from Internxt');
      }
    } catch (e) {
      print('Error sharing files: $e');
      rethrow;
    }
  }

  static Future<void> shareFile(String filePath, {String? text}) async {
    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        text: text ?? 'Shared from Internxt',
      );
    } catch (e) {
      print('Error sharing file: $e');
      rethrow;
    }
  }

  static Future<void> shareText(String text) async {
    try {
      await Share.share(text);
    } catch (e) {
      print('Error sharing text: $e');
      rethrow;
    }
  }
}