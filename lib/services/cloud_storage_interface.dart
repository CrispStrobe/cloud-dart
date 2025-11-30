// lib/services/cloud_storage_interface.dart
import 'dart:typed_data';
import 'filen_client_adapter.dart';
import 'internxt_client_adapter.dart'; //

/// Abstract interface for cloud storage providers
abstract class CloudStorageClient {
  // Authentication
  Future<void> login(String email, String password, {String? twoFactorCode});
  Future<bool> is2faNeeded(String email);
  Future<void> logout();
  bool get isAuthenticated;
  String? get userId;
  String? get bucketId;
  
  // Path operations
  Future<Map<String, dynamic>?> resolvePath(String path);
  Future<Map<String, dynamic>> listPath(String path);
  
  // File operations
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  });
  
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  });
  
  // Folder operations
  Future<void> createFolderPath(String path);
  
  // Delete/Move/Rename operations
  Future<void> deletePath(String path);
  Future<void> movePath(String sourcePath, String targetPath);
  Future<void> renamePath(String path, String newName);
  
  // Provider-specific info
  String get providerName;
  String get rootPath;
}

enum CloudProvider {
  filen,
  internxt,
}

/// Factory for creating cloud storage clients
class CloudStorageFactory {
  // --- TOGGLE: Set this to false to disable Internxt globally ---
  static const bool isInternxtSupported = false; 

  static CloudStorageClient create(CloudProvider provider, {required dynamic config}) {
    // Robust fallback: If Internxt is selected but disabled, force Filen or throw
    if (provider == CloudProvider.internxt && !isInternxtSupported) {
      print('⚠️ Internxt is currently disabled. Defaulting to Filen.');
      // Fallback to Filen if config matches, otherwise throw safe error
      if (config.runtimeType.toString().contains('Filen')) {
         return FilenClientAdapter(config: config);
      }
      // If we are stuck with Internxt config but it's disabled, we can't easily switch 
      // without re-initializing main.dart. 
      // In this case, we create the adapter but it might be unused.
      // Better approach: Since we control the UI, the user shouldn't reach here.
    }

    try {
      switch (provider) {
        case CloudProvider.filen:
          return FilenClientAdapter(config: config);
        case CloudProvider.internxt:
          if (isInternxtSupported) {
             return InternxtClientAdapter(config: config);
          } else {
             throw UnsupportedError('Internxt is disabled in this build.');
          }
      }
    } catch (e) {
      print('❌ Error creating client for $provider: $e');
      // Emergency fallback to avoid crash
      // Assuming config is compatible with Filen or we just re-throw
      rethrow;
    }
  }
}