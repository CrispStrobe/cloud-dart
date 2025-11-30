// lib/services/internxt_client_extensions.dart
import 'internxt_client.dart';
import 'dart:io';
import 'dart:typed_data';

extension InternxtClientExtensions on InternxtClient {
  Future<Map<String, dynamic>> listPath(String path) async {
    // 1. Resolve Path
    // The client method returns a Map<String, dynamic>
    final resolved = await resolvePath(path);
    
    // Check if resolvePath threw or returned error structure (depending on implementation)
    // The placeholder throws UnsupportedError, which will propagate up.
    
    if (resolved['type'] != 'folder') {
      throw Exception('Path is not a folder: $path');
    }
    
    final folderId = resolved['uuid'];
    
    // IMPORTANT: Pass detailed: true to get date fields
    final folders = await listFolders(folderId, detailed: true);
    final files = await listFolderFiles(folderId, detailed: true);
    
    return {
      'folders': folders,
      'files': files,
    };
  }

  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(fileData);
    
    try {
      // Access fields on 'this' (the InternxtClient instance)
      final currentUserId = this.userId;
      final currentBucketId = this.bucketId;

      if (currentUserId == null || currentBucketId == null) {
        throw Exception('Not authenticated (missing userId or bucketId)');
      }
      
      final batchId = 'upload_${DateTime.now().millisecondsSinceEpoch}';
      
      await upload(
        [tempFile.path],
        targetPath,
        recursive: false,
        onConflict: 'skip',
        preserveTimestamps: false,
        include: [],
        exclude: [],
        bridgeUser: currentBucketId, // bridgeUser is often the bucketId in Internxt legacy logic
        userIdForAuth: currentUserId,
        batchId: batchId,
        saveStateCallback: (state) async {},
        initialBatchState: null,
      );
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    final resolved = await resolvePath(remotePath);
    // If resolvePath succeeds, 'resolved' is not null in current implementation
    
    if (resolved['type'] != 'file') {
      throw Exception('Path is not a file: $remotePath');
    }
    
    final currentUserId = this.userId;
    final currentBucketId = this.bucketId;

    if (currentUserId == null || currentBucketId == null) {
      throw Exception('Not authenticated');
    }
    
    final localDir = File(localPath).parent.path;
    final batchId = 'download_${DateTime.now().millisecondsSinceEpoch}';
    
    await downloadPath(
      remotePath,
      localDestination: localDir,
      recursive: false,
      onConflict: 'skip',
      preserveTimestamps: false,
      include: [],
      exclude: [],
      bridgeUser: currentBucketId,
      userIdForAuth: currentUserId,
      batchId: batchId,
      saveStateCallback: (state) async {},
      initialBatchState: null,
    );
    
    // Move if the filename differed
    final expectedPath = '$localDir/${resolved['name']}';
    // Simple check if download saved as original name but we wanted 'localPath' name
    if (expectedPath != localPath && File(expectedPath).existsSync()) {
      try {
        if (File(localPath).existsSync()) {
          await File(localPath).delete();
        }
        await File(expectedPath).rename(localPath);
      } catch (e) {
        print('⚠️ Could not rename downloaded file: $e');
      }
    }
  }

  Future<void> createFolderPath(String path) async {
    await createFolderRecursive(path);
  }

  Future<void> deletePath(String path) async {
    final resolved = await resolvePath(path);
    await trashItems(resolved['uuid'], resolved['type']);
  }

  Future<void> movePath(String sourcePath, String targetPath) async {
    final sourceResolved = await resolvePath(sourcePath);
    final targetResolved = await resolvePath(targetPath);
    
    if (targetResolved['type'] != 'folder') {
      throw Exception('Target path is not a folder: $targetPath');
    }
    
    if (sourceResolved['type'] == 'file') {
      await moveFile(sourceResolved['uuid'], targetResolved['uuid']);
    } else {
      await moveFolder(sourceResolved['uuid'], targetResolved['uuid']);
    }
  }

  Future<void> renamePath(String path, String newName) async {
    final resolved = await resolvePath(path);
    
    if (resolved['type'] == 'file') {
      final parts = newName.split('.');
      String? extension;
      String plainName = newName;
      
      if (parts.length > 1) {
        extension = parts.last;
        plainName = parts.sublist(0, parts.length - 1).join('.');
      }
      
      await renameFile(resolved['uuid'], plainName, extension);
    } else {
      await renameFolder(resolved['uuid'], newName);
    }
  }
}