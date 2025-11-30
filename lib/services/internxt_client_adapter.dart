// lib/services/internxt_client_adapter.dart
import 'cloud_storage_interface.dart';
import 'internxt_client.dart';
import 'internxt_client_extensions.dart'; // Import the extensions

class InternxtClientAdapter implements CloudStorageClient {
  final InternxtClient _client;
  
  InternxtClientAdapter({required ConfigService config}) 
      : _client = InternxtClient(config: config);

  // Expose config for AppState to use
  ConfigService get config => _client.config;
  
  // Expose last login response for AppState
  Map<String, dynamic>? get lastLoginResponse => _lastLoginResponse;
  Map<String, dynamic>? _lastLoginResponse;
  
  @override
  String get providerName => 'Internxt';
  
  @override
  String get rootPath => '/';
  
  @override
  // Check if userId is set on the client instance
  bool get isAuthenticated => _client.userId != null;
  
  @override
  String? get userId => _client.userId;
  
  @override
  String? get bucketId => _client.bucketId;

  // ... (rest of the adapter delegates to _client or extensions) ...

  void setAuth(Map<String, dynamic> creds) {
    _client.setAuth(creds);
  }

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {
    final response = await _client.login(email, password, tfaCode: twoFactorCode);
    _lastLoginResponse = response;
    // login() inside client should set the internal state, but we ensure it here if needed
    _client.setAuth(response); 
  }

  @override
  Future<bool> is2faNeeded(String email) => _client.is2faNeeded(email);

  @override
  Future<void> logout() async {
    // Clear client state
    _client.userId = null;
    _client.bucketId = null;
    await _client.config.clearCredentials();
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    try {
      return await _client.resolvePath(path);
    } catch (e) {
      if (e is UnsupportedError) rethrow; // Pass up "Disabled" error
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) => _client.listPath(path);

  @override
  Future<void> uploadFile(List<int> fileData, String fileName, String targetPath, {Function(int p1, int p2)? onProgress}) {
    return _client.uploadFile(fileData, fileName, targetPath, onProgress: onProgress);
  }

  @override
  Future<void> downloadFileByPath(String remotePath, String localPath, {Function(int p1, int p2)? onProgress}) {
    return _client.downloadFileByPath(remotePath, localPath, onProgress: onProgress);
  }

  @override
  Future<void> createFolderPath(String path) => _client.createFolderPath(path);

  @override
  Future<void> deletePath(String path) => _client.deletePath(path);

  @override
  Future<void> movePath(String sourcePath, String targetPath) => _client.movePath(sourcePath, targetPath);

  @override
  Future<void> renamePath(String path, String newName) => _client.renamePath(path, newName);
  
  // Specific methods for Internxt searching if needed by AppState
  Future<Map<String, List<Map<String, dynamic>>>> search(String query, {bool detailed = false}) => _client.search(query, detailed: detailed);
  
  Future<List<Map<String, dynamic>>> findFiles(String path, String pattern, {int maxDepth = -1}) => _client.findFiles(path, pattern, maxDepth: maxDepth);
}