// lib/services/filen_client_adapter.dart
import 'cloud_storage_interface.dart';
import 'filen.dart';
import 'filen_config_service.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // for kIsWeb

class FilenClientAdapter implements CloudStorageClient {
  final FilenClient _client;
  final FilenConfigService filenConfig;
  
  FilenClientAdapter({required FilenConfigService config}) 
      : filenConfig = config,
        _client = FilenClient(config: ConfigService(configPath: config.configPath));
  
  @override
  String get providerName => 'Filen';
  
  @override
  String get rootPath => '/';
  
  @override
  bool get isAuthenticated => _client.apiKey != null && _client.apiKey!.isNotEmpty;
  
  @override
  String? get userId => _client.email;
  
  @override
  String? get bucketId => null; // Filen doesn't use buckets in the same way Internxt does
  
  // Expose for AppState to use
  bool debugMode = false;
  
  // Expose client for direct access when needed
  FilenClient get client => _client;
  
  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {
    // Authenticate
    final credentials = await _client.login(email, password, twoFactorCode: twoFactorCode ?? "XXXXXX");
    
    // Set auth on the client instance immediately
    _client.setAuth(credentials);
    
    // Ensure we have the base folder UUID
    if (credentials['baseFolderUUID'] == null || credentials['baseFolderUUID'].isEmpty) {
      final rootUUID = await _client.fetchBaseFolderUUID();
      credentials['baseFolderUUID'] = rootUUID;
      _client.baseFolderUUID = rootUUID;
    }

    // Save using the ConfigService
    await filenConfig.saveCredentials({
      'email': email,
      'apiKey': credentials['apiKey'] ?? '',
      'masterKeys': credentials['masterKeys'] ?? '',
      'baseFolderUUID': credentials['baseFolderUUID'] ?? '',
      'userId': credentials['userId'] ?? '',
    });
  }
  
  @override
  Future<bool> is2faNeeded(String email) async {
    // Filen API doesn't have a specific pre-check for 2FA status without attempting login
    return false; 
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    // 1. Resolve remote path to UUID
    final resolved = await _client.resolvePath(remotePath);
    if (resolved['type'] != 'file') {
      throw Exception('Remote path is not a file');
    }
    final uuid = resolved['uuid'];

    // 2. Download bytes directly
    // Note: FilenClient needs a method for this.
    // Assuming you have added `downloadFileBytes(uuid)` to FilenClient as discussed, 
    // or use the internal HTTP client logic here.
    
    // If FilenClient doesn't support this yet, you must add it there.
    // Here is how you would call it:
    return await _client.downloadFileBytes(uuid, onProgress: onProgress);
  }
  
  @override
  Future<void> logout() async {
    _client.apiKey = '';
    _client.masterKeys = [];
    await filenConfig.clearCredentials();
  }
  
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    try {
      // FilenClient has a resolvePath method
      final resolved = await _client.resolvePath(path);
      return resolved;
    } catch (e) {
      // Return null if not found (standardize behavior)
      if (e.toString().contains('not found')) return null;
      print('⚠️ Error resolving path: $e');
      return null;
    }
  }
  
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    try {
      // 1. Resolve path to get the UUID
      final resolved = await _client.resolvePath(path);
      
      if (resolved['type'] != 'folder') {
        throw Exception('Path is not a folder');
      }

      final uuid = resolved['uuid'];

      // 2. Fetch folders and files using the UUID
      // FilenClient separates these into two calls
      final folders = await _client.listFoldersAsync(uuid, detailed: true);
      final files = await _client.listFolderFiles(uuid, detailed: true);
      
      return {
        'folders': folders,
        'files': files,
      };
    } catch (e) {
      print('⚠️ Error listing path: $e');
      // Return empty structure on error to prevent UI crash
      return {
        'folders': <Map<String, dynamic>>[],
        'files': <Map<String, dynamic>>[],
      };
    }
  }
  
  @override
  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    // Resolve Target
    final resolvedFolder = await _client.resolvePath(targetPath);
    if (resolvedFolder['type'] != 'folder') {
      throw Exception('Target path is not a folder');
    }
    final parentUuid = resolvedFolder['uuid'];

    // --- WEB SUPPORT ---
    if (kIsWeb) {
      // Use the memory-based upload
      await _client.uploadBytes(
        Uint8List.fromList(fileData),
        fileName,
        parentUuid,
        onProgress: onProgress,
      );
      return;
    }
    // --- END WEB Logic ---

    // Desktop/Mobile Logic (Write to Temp File)
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(fileData);
    
    try {
      await _client.uploadFile(
        tempFile,
        parentUuid,
      );
      if (onProgress != null) {
        onProgress(fileData.length, fileData.length);
      }
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
  
  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    // 1. Resolve remote path to UUID
    final resolved = await _client.resolvePath(remotePath);
    if (resolved['type'] != 'file') {
      throw Exception('Remote path is not a file');
    }
    final uuid = resolved['uuid'];

    // 2. Download using UUID to specific destination
    // FilenClient.downloadFile signature: 
    // Future<Map<String, dynamic>> downloadFile(String uuid, {String? savePath, Function(int, int)? onProgress})
    await _client.downloadFile(
      uuid,
      savePath: localPath,
      onProgress: onProgress,
    );
  }
  
  @override
  Future<void> createFolderPath(String path) async {
    // Map to createFolderRecursive in FilenClient
    await _client.createFolderRecursive(path);
  }
  
  @override
  Future<void> deletePath(String path) async {
    // 1. Resolve path to get UUID
    final resolved = await resolvePath(path);
    if (resolved != null) {
      final uuid = resolved['uuid'] as String;
      final type = resolved['type'] as String;
      
      // 2. Call trashItem
      await _client.trashItem(uuid, type);
    } else {
      throw Exception('Could not resolve path: $path');
    }
  }
  
  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    // 1. Resolve Source
    final sourceResolved = await resolvePath(sourcePath);
    if (sourceResolved == null) {
      throw Exception('Could not resolve source path: $sourcePath');
    }

    // 2. Resolve Target (Parent folder)
    // Filen moveItem expects the UUID of the *destination folder*
    // If targetPath is the full new path (e.g. /Docs/NewName), we might need logic.
    // Usually move interface implies moving INTO targetPath.
    
    final targetResolved = await resolvePath(targetPath);
    if (targetResolved == null || targetResolved['type'] != 'folder') {
       throw Exception('Target path must be an existing folder: $targetPath');
    }
    
    final sourceUuid = sourceResolved['uuid'] as String;
    final sourceType = sourceResolved['type'] as String;
    final targetUuid = targetResolved['uuid'] as String;
    
    await _client.moveItem(sourceUuid, targetUuid, sourceType);
  }
  
  @override
  Future<void> renamePath(String path, String newName) async {
    // 1. Resolve path to UUID
    final resolved = await resolvePath(path);
    
    if (resolved == null) {
      throw Exception('Could not resolve path: $path');
    }
    
    final uuid = resolved['uuid'] as String;
    final type = resolved['type'] as String;
    
    // 2. Call renameItem
    await _client.renameItem(uuid, newName, type);
  }
}