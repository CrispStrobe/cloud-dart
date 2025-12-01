// lib/services/webdav_client_adapter.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:path/path.dart' as p;
import 'cloud_storage_interface.dart';
import 'webdav_config_service.dart';
import 'dart:io' as dart_io;

class WebDavClientAdapter implements CloudStorageClient {
  final WebDavConfigService _config;
  
  WebDavConfigService get config => _config;

  webdav.Client? _client;
  String? _user;
  String? _host;

  WebDavClientAdapter({required dynamic config}) 
      : _config = (config is WebDavConfigService) 
            ? config 
            : WebDavConfigService(configPath: '');

  @override
  String get providerName => 'WebDAV';

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => _client != null;

  @override
  String? get userId => _user;

  @override
  String? get bucketId => _host;

  void _initClient(String url, String user, String password) {
    _client = webdav.newClient(
      url,
      user: user,
      password: password,
      debug: false, 
    );
    _client!.setHeaders({'Content-Type': 'application/octet-stream'});
  }

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {
    String user = email;
    String host = '';

    if (email.contains('@http')) {
      final splitIndex = email.lastIndexOf('@http');
      user = email.substring(0, splitIndex);
      host = email.substring(splitIndex + 1);
    } else {
      throw Exception('Format must be user@ServerURL');
    }

    try {
      final tempClient = webdav.newClient(host, user: user, password: password);
      await tempClient.readDir('/'); 
    } catch (e) {
      throw Exception('Connection failed: $e');
    }

    await _config.saveCredentials({
      'username': user,
      'password': password,
      'host': host,
    });

    _user = user;
    _host = host;
    _initClient(host, user, password);
  }

  @override
  Future<void> logout() async {
    _client = null;
    await _config.clearCredentials();
  }
  
  Future<void> _ensureClient() async {
    if (_client != null) return;
    
    final creds = await _config.readCredentials();
    if (creds == null) throw Exception('Not logged in');
    
    _user = creds['username'];
    _host = creds['host'];
    _initClient(_host!, _user!, creds['password']!);
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    await _ensureClient();
    try {
      final list = await _client!.readDir(path);
      if (list.isEmpty) return null;
      
      final item = list.first;
      
      // FIX: Use isDir and mTime for webdav_client 1.2.2
      return {
        'type': (item.isDir ?? false) ? 'folder' : 'file',
        'name': item.name ?? p.basename(path),
        'path': path,
        'size': item.size,
        'updatedAt': item.mTime?.toIso8601String(),
        'uuid': path,
      };
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await _ensureClient();
    
    final folders = <Map<String, dynamic>>[];
    final files = <Map<String, dynamic>>[];

    try {
      final contents = await _client!.readDir(path);
      
      for (final item in contents) {
        if (item.name == null || item.name == '.' || item.name == '..') continue;
        
        final fullPath = p.posix.join(path, item.name);
        // FIX: Use isDir
        final isDir = item.isDir ?? false;
        
        final map = {
          'uuid': fullPath,
          'name': item.name,
          'size': item.size,
          // FIX: Use mTime
          'modificationTime': item.mTime?.toIso8601String(),
          'type': isDir ? 'folder' : 'file',
          'path': fullPath,
        };

        if (isDir) {
          folders.add(map);
        } else {
          files.add(map);
        }
      }
    } catch (e) {
      print('WebDAV List Error: $e');
      throw Exception('Failed to list path $path: $e');
    }

    return {
      'folders': folders,
      'files': files,
    };
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureClient();
    final remotePath = p.posix.join(targetPath, fileName);
    
    await _client!.write(remotePath, Uint8List.fromList(fileData));
    
    if (onProgress != null) {
      onProgress(fileData.length, fileData.length);
    }
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    await _ensureClient();
    
    final data = await _client!.read(remotePath);
    
    await dart_io.File(localPath).writeAsBytes(data);
    
    if (onProgress != null) {
      onProgress(data.length, data.length);
    }
  }

  @override
  Future<void> createFolderPath(String path) async {
    await _ensureClient();
    await _client!.mkdir(path);
  }

  @override
  Future<void> deletePath(String path) async {
    await _ensureClient();
    await _client!.remove(path); // 'remove' instead of 'removeAll' in 1.2.2 usually, checking common usage
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    await _ensureClient();
    // FIX: Use rename() for moving, with overwrite=false (or true if preferred)
    await _client!.rename(sourcePath, targetPath, false); 
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    await _ensureClient();
    final newPath = p.posix.join(p.dirname(path), newName);
    // FIX: Use rename()
    await _client!.rename(path, newPath, false);
  }
  
  @override
  Future<bool> is2faNeeded(String email) async => false; 
}