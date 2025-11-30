// lib/services/internxt_client.dart
// ⚠️ PLACEHOLDER FILE: Replace with actual implementation to enable Internxt support.

import 'dart:async';
import 'dart:typed_data';

class InternxtClient {
  // Static placeholders
  static const String networkUrl = 'https://placeholder.api';
  static const String driveApiUrl = 'https://placeholder.api';
  static const String appCryptoSecret = 'placeholder';

  final ConfigService config;
  bool debugMode = false;
  
  // --- ADDED: Public fields needed by Adapter/Extensions ---
  String? userId;
  String? bucketId;
  String? mnemonic; // Needed by some internals if referenced
  // --------------------------------------------------------

  // Constructor
  InternxtClient({required this.config});

  // --- Auth Stubs ---
  void setAuth(Map<String, dynamic> creds) {
    // In placeholder mode, we might just store them so checks pass
    userId = creds['userId'];
    bucketId = creds['bucketId'];
  }

  Future<bool> is2faNeeded(String email) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  Future<Map<String, String?>> login(String email, String password, {String? tfaCode}) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }
  
  Future<void> refreshToken() async {}

  // --- Path & List Stubs ---
  Future<Map<String, dynamic>> resolvePath(String path) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  Future<List<Map<String, dynamic>>> listFolders(String folderId, {bool detailed = false}) async {
    return [];
  }

  Future<List<Map<String, dynamic>>> listFolderFiles(String folderId, {bool detailed = false}) async {
    return [];
  }

  // --- File Operation Stubs ---
  Future<void> upload(
    List<String> sources,
    String targetPath, {
    required bool recursive,
    required String onConflict,
    required bool preserveTimestamps,
    required List<String> include,
    required List<String> exclude,
    required String bridgeUser,
    required String userIdForAuth,
    required String batchId,
    Map<String, dynamic>? initialBatchState,
    required Future<void> Function(Map<String, dynamic>) saveStateCallback,
  }) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  Future<void> downloadPath(
    String remotePath, {
    String? localDestination,
    required bool recursive,
    required String onConflict,
    required bool preserveTimestamps,
    required List<String> include,
    required List<String> exclude,
    required String bridgeUser,
    required String userIdForAuth,
    required String batchId,
    Map<String, dynamic>? initialBatchState,
    required Future<void> Function(Map<String, dynamic>) saveStateCallback,
  }) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  Future<Map<String, dynamic>> downloadFile(
    String fileUuid,
    String bridgeUser,
    String userIdForAuth, {
    bool preserveTimestamps = false,
  }) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  // --- Folder Management Stubs ---
  Future<Map<String, dynamic>> createFolderRecursive(String path) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  // --- Delete/Move/Rename Stubs ---
  Future<void> trashItems(String uuid, String type) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }
  
  Future<List<Map<String, dynamic>>> getTrashContent({int? limit}) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  Future<void> deletePermanently(String uuid, String type) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  Future<void> moveFile(String fileUuid, String destinationFolderUuid) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  Future<void> moveFolder(String folderUuid, String destinationFolderUuid) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  Future<void> renameFile(String fileUuid, String newPlainName, String? newType) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  Future<void> renameFolder(String folderUuid, String newName) async {
    throw UnsupportedError('Internxt support is currently disabled.');
  }

  // --- Search Stubs ---
  Future<Map<String, List<Map<String, dynamic>>>> search(String query, {bool detailed = false}) async {
    return {'folders': [], 'files': []};
  }

  Future<List<Map<String, dynamic>>> findFiles(String startPath, String pattern, {int maxDepth = -1}) async {
    return [];
  }
  
  // --- Misc ---
  Future<void> printTree(
    String path,
    void Function(String) printLine, {
    int maxDepth = 3,
  }) async {}
}

class ConfigService {
  final String configPath;
  ConfigService({required this.configPath});

  Future<Map<String, String>?> readCredentials() async => null;
  Future<void> saveCredentials(Map<String, dynamic> credentials) async {}
  Future<void> clearCredentials() async {}

  String generateBatchId(String operationType, List<String> sources, String target) => '';
  Future<Map<String, dynamic>?> loadBatchState(String batchId) async => null;
  Future<void> saveBatchState(String batchId, Map<String, dynamic> state) async {}
  Future<void> deleteBatchState(String batchId) async {}
}