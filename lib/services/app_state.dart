// services/app_state.dart
import 'package:flutter/foundation.dart';
import '../models/file_item.dart';
import '../models/operation_progress.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_storage_interface.dart';

import 'filen_client_adapter.dart';
import 'internxt_client_adapter.dart';
import 'sftp_client_adapter.dart';

import 'webdav_client_adapter.dart';
import 'webdav_config_service.dart';

import 'filen_config_service.dart'; // Needed for type checking
import 'sftp_config_service.dart';  // Needed for switching

import 'internxt_client.dart';      // Needed for type checking

import 'share_service.dart';
import 'receive_service.dart';
import 'local_file_service.dart'; 
import '../screens/file_browser_screen.dart';

import 'package:universal_html/html.dart' as html;

enum SortBy { name, size, date, extension }
enum SortOrder { ascending, descending }

class AppState extends ChangeNotifier {
  // Cloud storage abstraction
  CloudProvider _currentProvider = CloudProvider.filen;
  late CloudStorageClient _cloudClient;
  dynamic _config;
  String _configPath = ''; // Store path to recreate configs

  late final LocalFileService _localFileService; 

  bool _isConnected = false;
  String? _userEmail;
  PanelSide _activePanel = PanelSide.local;

  String _remotePath = '/';

  List<FileItem>? _localFiles;
  List<FileItem>? _remoteFiles;

  final Set<FileItem> _localSelection = {};
  final Set<FileItem> _remoteSelection = {};
  
  FileItem? _lastSelectedLocal;
  FileItem? _lastSelectedRemote;

  final Set<FileItem> _selectedLocalFiles = {};
  final Set<FileItem> _selectedRemoteFiles = {};

  final List<OperationProgress> _operations = [];

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  FileItem? _itemToScrollTo;
  FileItem? get itemToScrollTo => _itemToScrollTo;
  void clearItemToScrollTo() { _itemToScrollTo = null; }

  List<String> _receivedFiles = [];
  String? _receivedText;

  List<String> get receivedFiles => _receivedFiles;
  String? get receivedText => _receivedText;

  bool get hasLocalSelection => _selectedLocalFiles.isNotEmpty;
  bool get hasRemoteSelection => _selectedRemoteFiles.isNotEmpty;
  
  List<FileItem> get selectedLocalFiles => _selectedLocalFiles.toList();
  List<FileItem> get selectedRemoteFiles => _selectedRemoteFiles.toList();

  String? _lastError;
  String? get lastError => _lastError;

  SortBy _localSortBy = SortBy.name;
  SortOrder _localSortOrder = SortOrder.ascending;
  SortBy _remoteSortBy = SortBy.name;
  SortOrder _remoteSortOrder = SortOrder.ascending;

  SortBy getSort(PanelSide side) => 
      side == PanelSide.local ? _localSortBy : _remoteSortBy;
  
  SortOrder getSortOrder(PanelSide side) => 
      side == PanelSide.local ? _localSortOrder : _remoteSortOrder;

  void setSortBy(PanelSide side, SortBy sortBy) {
    if (side == PanelSide.local) {
      _localSortBy = sortBy;
      _sortFiles(_localFiles, _localSortBy, _localSortOrder);
    } else {
      _remoteSortBy = sortBy;
      _sortFiles(_remoteFiles, _remoteSortBy, _remoteSortOrder);
    }
    notifyListeners();
  }

  void toggleSortOrder(PanelSide side) {
    if (side == PanelSide.local) {
      _localSortOrder = _localSortOrder == SortOrder.ascending 
          ? SortOrder.descending 
          : SortOrder.ascending;
      _sortFiles(_localFiles, _localSortBy, _localSortOrder);
    } else {
      _remoteSortOrder = _remoteSortOrder == SortOrder.ascending 
          ? SortOrder.descending 
          : SortOrder.ascending;
      _sortFiles(_remoteFiles, _remoteSortBy, _remoteSortOrder);
    }
    notifyListeners();
  }

  void _sortFiles(List<FileItem>? files, SortBy sortBy, SortOrder order) {
    if (files == null || files.isEmpty) {
      print('⚠️ No files to sort');
      return;
    }

    try {
      print('🔄 Sorting ${files.length} files by $sortBy ($order)');
      
      files.sort((a, b) {
        try {
          if (a.isFolder && !b.isFolder) return -1;
          if (!a.isFolder && b.isFolder) return 1;

          int comparison = 0;
          
          switch (sortBy) {
            case SortBy.name:
              comparison = (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
              break;
            case SortBy.size:
              final sizeA = a.size ?? 0;
              final sizeB = b.size ?? 0;
              comparison = sizeA.compareTo(sizeB);
              break;
            case SortBy.date:
              final dateA = a.updatedAt ?? DateTime(1970);
              final dateB = b.updatedAt ?? DateTime(1970);
              comparison = dateA.compareTo(dateB);
              break;
            case SortBy.extension:
              if (a.isFolder || b.isFolder) {
                comparison = 0;
              } else {
                final nameA = a.name ?? '';
                final nameB = b.name ?? '';
                final extA = nameA.contains('.') ? nameA.split('.').last.toLowerCase() : '';
                final extB = nameB.contains('.') ? nameB.split('.').last.toLowerCase() : '';
                comparison = extA.compareTo(extB);
              }
              break;
          }
          return order == SortOrder.ascending ? comparison : -comparison;
        } catch (e) {
          print('⚠️ Error comparing items: $e');
          return 0;
        }
      });
      
      print('✅ Sorting complete');
    } catch (e, stackTrace) {
      print('❌ Error in sorting function: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> pickLocalDirectory() async {
    try {
      print('📂 Opening directory picker...');
      
      final selectedDirectory = await _localFileService.requestDirectoryAccess(
        initialDirectory: _localFileService.currentPath,
      );
      
      if (selectedDirectory != null) {
        print('📁 User selected: $selectedDirectory');
        _localFileService.currentPath = selectedDirectory;
        await _loadLocalFiles();
        notifyListeners();
      } else {
        print('⚠️ User cancelled directory selection');
      }
    } catch (e) {
      print('❌ Error picking directory: $e');
      _lastError = 'Error picking directory: $e';
      notifyListeners();
    }
  }

  void initializeReceiving() {
    if (kIsWeb) {
      print('⚠️ Receive sharing intent not supported on web.');
      return;
    }
    
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        ReceiveService.initialize(
          onFilesReceived: (files) {
            _receivedFiles.addAll(files);
            notifyListeners();
          },
          onTextReceived: (text) {
            print('Received text: $text');
          },
        );
      } else {
        print('⚠️ Receive sharing intent not supported on this platform.');
      }
    } catch (e) {
      print('Could not initialize receive service: $e');
    }
  }

  Future<void> shareFiles(List<FileItem> files) async {
    if (kIsWeb) {
       print('⚠️ File sharing not supported on web.');
       return;
    }
    
    if (Platform.isAndroid || Platform.isIOS) {
      final paths = files.map((f) => f.path!).where((p) => p.isNotEmpty).toList();
      if (paths.isNotEmpty) {
        await ShareService.shareFiles(paths);
      }
    } else {
      print('⚠️ File sharing not supported on this platform.');
    }
  }

  void clearReceivedFiles() {
    _receivedFiles = [];
    _receivedText = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      ReceiveService.dispose();
    }
    super.dispose();
  }

  // CHANGED: Constructor now accepts config and initializes cloud client
  AppState({required dynamic config, CloudProvider? initialProvider}) 
      : _config = config,
        _currentProvider = initialProvider ?? CloudProvider.filen,
        _localFileService = LocalFileService() {

    // EXTRACT PATH from initial config to reuse when switching
    if (config is FilenConfigService) _configPath = config.configPath;
    else if (config is SFTPConfigService) _configPath = config.configPath;
    else if (config is ConfigService) _configPath = config.configPath;
    
    // Initialize cloud client based on provider
    _cloudClient = CloudStorageFactory.create(_currentProvider, config: config);
    
    
    
    _activePanel = PanelSide.local;
    
    _initializeLocalPath();
    _attemptAutoLogin();
  }

  // NEW: Method to switch cloud providers
  Future<void> switchProvider(CloudProvider provider) async {
    if (_currentProvider == provider) return;
    
    print('🔄 Switching cloud provider to $provider');
    
    if (_isConnected) {
      await logout();
    }
    
    // 1. Save Preference
    final prefs = await SharedPreferences.getInstance();
    String providerKey;
    switch (provider) {
      case CloudProvider.filen: providerKey = 'filen'; break;
      case CloudProvider.sftp: providerKey = 'sftp'; break;
      case CloudProvider.webdav: providerKey = 'webdav'; break;
      case CloudProvider.internxt: providerKey = 'internxt'; break;
    }
    await prefs.setString('cloud_provider', providerKey);
    print('💾 Saved provider preference: $providerKey');

    // 2. Instantiate correct config service
    // This ensures the new adapter gets the right config type with the correct path
    if (provider == CloudProvider.filen) {
      _config = FilenConfigService(configPath: _configPath);
    } else if (provider == CloudProvider.sftp) {
      _config = SFTPConfigService(configPath: _configPath);
    } else if (provider == CloudProvider.webdav) { 
      _config = WebDavConfigService(configPath: _configPath);
    } else if (provider == CloudProvider.internxt) {
      _config = ConfigService(configPath: _configPath);
    }

    // 3. Create Client
    _currentProvider = provider;
    _cloudClient = CloudStorageFactory.create(provider, config: _config);
    _remotePath = _cloudClient.rootPath;
    _remoteFiles = null;
    
    // 4. Try auto-login with new provider
    await _attemptAutoLogin();
    
    notifyListeners();
  }

  // Getters for cloud client info
  CloudProvider get currentProvider => _currentProvider;
  String get providerName => _cloudClient.providerName;
  CloudStorageClient get client => _cloudClient;

  Future<void> _initializeLocalPath() async {
    try {
      await _localFileService.getInitialPath(); 
      
      if (!kIsWeb && Platform.isMacOS && _localFileService.grantedBasePath == null) {
        print('📂 No previous directory access, prompting user...');
        await _requestInitialDirectoryAccess();
      } else {
        await _loadLocalFiles(); 
        notifyListeners();
      }
    } catch (e) {
      print('❌ Error initializing local path: $e');
      _localFileService.currentPath = await _localFileService.getSafeFallbackDirectory();
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> _requestInitialDirectoryAccess() async {
    _lastError = 'Please select a base directory to grant access (e.g., your home folder)';
    notifyListeners();

    final grantedPath = await _localFileService.requestDirectoryAccess(
      initialDirectory: await _localFileService.getSafeFallbackDirectory(),
    );

    if (grantedPath != null) {
      _lastError = null;
      await _loadLocalFiles();
      notifyListeners();
    } else {
      _localFileService.currentPath = await _localFileService.getSafeFallbackDirectory();
      _lastError = 'Access cancelled. Using fallback directory.';
      await _loadLocalFiles(); 
      notifyListeners();
    }
  }

  Future<void> _loadLocalFiles() async {
    try {
      print('📁 Loading local files from: ${localPath}');
      
      final entities = await _localFileService.listDirectory(localPath);
      
      if (entities == null) {
         _localFiles = [];
         // On web, empty list might just mean no folder selected yet
         if (!kIsWeb) _lastError = 'Local file access is not supported on this platform.';
         notifyListeners();
         return;
      }

      final items = <FileItem>[];
      // print('📦 Found ${entities.length} entities');

      for (final entity in entities) {
        try {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;

          // --- WEB SPECIFIC LOGIC ---
          if (kIsWeb) {
            final isFolder = entity is Directory;
            int size = 0;
            DateTime updated = DateTime.now();

            if (!isFolder) {
              // Retrieve real size from WebFileService
              final meta = _localFileService.getWebMetadata(entity.path);
              size = meta['size'] ?? 0;
              updated = meta['modified'] ?? DateTime.now();
            }

            items.add(FileItem(
              name: name,
              path: entity.path,
              isFolder: isFolder,
              size: size,
              updatedAt: updated,
            ));
            continue; 
          }
          // --- Web logic end ---

          final stat = await entity.stat(); 
          if (stat.type == FileSystemEntityType.directory) {
            items.add(FileItem(
              name: name,
              path: entity.path,
              isFolder: true,
              updatedAt: stat.modified,
            ));
          } else if (stat.type == FileSystemEntityType.file) {
            items.add(FileItem(
              name: name,
              path: entity.path,
              isFolder: false,
              size: stat.size,
              updatedAt: stat.modified,
            ));
          }
        } catch (e) {
          continue;
        }
      }

      _localFiles = items;
      _sortFiles(_localFiles, _localSortBy, _localSortOrder);
      // print('✅ Loaded ${_localFiles?.length ?? 0} local items');
      _lastError = null;
      notifyListeners();
    } catch (e, stackTrace) {
      if (!kIsWeb && (e is PathAccessException || e.toString().contains('Operation not permitted') || e.toString().contains('Permission denied'))) {
        _localFiles = [];
        _lastError = 'Permission denied. Use the Browse button (folder icon) to grant access.';
        notifyListeners();
        return; 
      }
      
      print('❌ Error loading local files: $e');
      _localFiles = [];
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> _attemptAutoLogin() async {
    print('🔄 Attempting auto-login for provider: ${_cloudClient.providerName}');
    
    try {
      if (_cloudClient is InternxtClientAdapter) {
        final adapter = _cloudClient as InternxtClientAdapter;
        final creds = await adapter.config.readCredentials();
        if (creds == null || creds['token'] == null) {
           print('⚠️ Internxt: No credentials found');
           return;
        }
        adapter.setAuth(creds);
        _userEmail = creds['email'];
        _isConnected = true;
        await refreshPanel(PanelSide.remote);
        notifyListeners();
      } else if (_cloudClient is FilenClientAdapter) {
        final adapter = _cloudClient as FilenClientAdapter;
        final creds = await adapter.filenConfig.readCredentials();
        if (creds == null || creds['email'] == null) {
           print('⚠️ Filen: No credentials found');
           return;
        }
        if (creds['apiKey'] != null && creds['apiKey']!.isNotEmpty) {
          adapter.client.setAuth(creds);
          _userEmail = creds['email'];
          _isConnected = true;
          await refreshPanel(PanelSide.remote);
          notifyListeners();
        }
      } else if (_cloudClient is SFTPClientAdapter) {
        final adapter = _cloudClient as SFTPClientAdapter;
        final creds = await adapter.config.readCredentials();
        
        if (creds != null && creds['host'] != null && creds['username'] != null) {
          _userEmail = '${creds['username']}@${creds['host']}';
          _isConnected = true;
          print('✅ SFTP: Auto-login successful for $_userEmail');
          
          // Force a refresh to list files immediately
          await refreshPanel(PanelSide.remote);
          notifyListeners();
        } else {
          print('⚠️ SFTP: No saved credentials found');
        }
      } else if (_cloudClient is WebDavClientAdapter) {
        final adapter = _cloudClient as WebDavClientAdapter;
        final creds = await adapter.config.readCredentials();
        
        if (creds != null && creds['host'] != null && creds['username'] != null) {
          _userEmail = '${creds['username']}@${creds['host']}';
          _isConnected = true;
          print('✅ WebDAV: Auto-login successful for $_userEmail');
          await refreshPanel(PanelSide.remote);
          notifyListeners();
        } else {
          print('⚠️ WebDAV: No credentials found');
        }
      }
    } catch (e) {
      print('⚠️ Auto-login exception: $e');
      _lastError = 'Session expired. Please log in again.';
      _isConnected = false;
      notifyListeners();
    }
  }

  void clearCompletedOperations() {
    _operations.removeWhere((op) => op.isComplete && op.error == null);
    notifyListeners();
  }

  void removeOperation(String id) {
    _operations.removeWhere((op) => op.id == id);
    notifyListeners();
  }

  // Getters
  bool get isConnected => _isConnected;
  String? get userEmail => _userEmail;
  PanelSide get activePanel => _activePanel;
  String get localPath => _localFileService.currentPath;
  String get remotePath => _remotePath;
  List<FileItem>? get localFileItems => _localFiles;
  List<FileItem>? get remoteFiles => _remoteFiles;
  Set<FileItem> get localSelection => _localSelection;
  Set<FileItem> get remoteSelection => _remoteSelection;
  List<OperationProgress> get operations => _operations;
  bool get hasActiveOperations => _operations.any((op) => !op.isComplete);

  Future<void> login(String email, String password, String? tfaCode) async {
    await _cloudClient.login(email, password, twoFactorCode: tfaCode);
    
    if (_cloudClient is InternxtClientAdapter) {
      final adapter = _cloudClient as InternxtClientAdapter;
      final response = adapter.lastLoginResponse;
      
      if (response != null) {
        await adapter.config.saveCredentials({
          'email': email,
          'token': response['token'] ?? '',
          'mnemonic': response['mnemonic'] ?? '',
          'userId': response['userId'] ?? '',
          'bridgeUser': response['bridgeUser'] ?? '',
          'userIdForAuth': response['userIdForAuth'] ?? '',
          'bucketId': response['bucketId'] ?? '',
          'rootFolderId': response['rootFolderId'] ?? '',
          'newToken': response['newToken'] ?? '',
        });
      }
    } else if (_cloudClient is FilenClientAdapter) {
      final adapter = _cloudClient as FilenClientAdapter;
      final savedCreds = await adapter.filenConfig.readCredentials();
      if (savedCreds == null) {
        print('⚠️ Warning: Filen credentials were not saved properly');
      }
    } else if (_cloudClient is SFTPClientAdapter) {
      final adapter = _cloudClient as SFTPClientAdapter;
      final savedCreds = await adapter.config.readCredentials();
      if (savedCreds == null) {
        print('⚠️ Warning: SFTP credentials were not saved properly');
      }
    } else if (_cloudClient is WebDavClientAdapter) {
      final adapter = _cloudClient as WebDavClientAdapter;
      final savedCreds = await adapter.config.readCredentials();
      if (savedCreds == null) {
        print('⚠️ Warning: WebDAV credentials were not saved properly');
      }
    }
    
    _userEmail = email;
    _isConnected = true;
    _lastError = null; 
    notifyListeners();
    await refreshPanel(PanelSide.remote);
  }

  Future<void> logout() async {
    await _cloudClient.logout();
    
    if (_cloudClient is InternxtClientAdapter) {
      await (_cloudClient as InternxtClientAdapter).config.clearCredentials();
    } else if (_cloudClient is FilenClientAdapter) {
      await (_cloudClient as FilenClientAdapter).filenConfig.clearCredentials();
    } else if (_cloudClient is SFTPClientAdapter) {
      await (_cloudClient as SFTPClientAdapter).config.clearCredentials();
    } else if (_cloudClient is WebDavClientAdapter) {
      await (_cloudClient as WebDavClientAdapter).config.clearCredentials();
    }
    
    _isConnected = false;
    _userEmail = null;
    _remoteFiles = null;
    _remotePath = _cloudClient.rootPath;
    _remoteSelection.clear();
    notifyListeners();
  }

  void setActivePanel(PanelSide side) {
    _activePanel = side;
    notifyListeners();
  }

  Future<void> refreshPanel(PanelSide side) async {
    if (side == PanelSide.local) {
      await _loadLocalFiles();
    } else {
      try {
        // FIX: Only attempt auto-login if we are NOT authenticated AND NOT logically connected.
        // SFTP is often !isAuthenticated (socket closed) but _isConnected (creds loaded).
        if (!_cloudClient.isAuthenticated && !_isConnected) {
          await _attemptAutoLogin();
          // If still not connected after attempt, clear files and return
          if (!_isConnected) {
            _remoteFiles = [];
            notifyListeners();
            return;
          }
        }
        
        final result = await _cloudClient.listPath(_remotePath);
        
        final folders = (result['folders'] as List<dynamic>?)?.map((item) {
              final map = item as Map<String, dynamic>;
              DateTime? folderDate;
              if (map['modificationTime'] != null) {
                try { folderDate = DateTime.parse(map['modificationTime'].toString()); } catch (_) {}
              }
              return FileItem(
                name: map['name'] ?? 'Unknown',
                isFolder: true,
                uuid: map['uuid'],
                updatedAt: folderDate,
              );
            }).toList() ?? [];

        final files = (result['files'] as List<dynamic>?)?.map((item) {
              final map = item as Map<String, dynamic>;
              final fileName = map['name'] ?? 'Unknown';
              
              // Logic to handle extensions ONLY if the provider separates them (like Internxt)
              final rawType = map['fileType'] ?? map['type'] ?? '';
              final fileType = rawType.toString().toLowerCase();
              
              String fullName = fileName;
              if (fileType.isNotEmpty && fileType != 'file' && !fileName.toLowerCase().endsWith('.$fileType')) {
                 fullName = '$fileName.$rawType';
              }
                  
              DateTime? fileDate;
              if (map['modificationTime'] != null) {
                try { fileDate = DateTime.parse(map['modificationTime'].toString()); } catch (_) {}
              }
              return FileItem(
                name: fullName,
                isFolder: false,
                size: map['size'] as int?,
                uuid: map['uuid'],
                updatedAt: fileDate,
              );
            }).toList() ?? [];

        _remoteFiles = [...folders, ...files];
        _sortFiles(_remoteFiles, _remoteSortBy, _remoteSortOrder);
        _lastError = null; 
        notifyListeners();
      } catch (e) {
        // Don't clear files on temporary network errors if possible, 
        // but for now we follow standard pattern
        print('❌ Refresh Error: $e');
        _remoteFiles = [];
        _lastError = e.toString(); 
        notifyListeners();
      }
    }
  }

  Future<void> navigateUp(PanelSide side) async {
    if (side == PanelSide.local) {
      
      final parent = p.dirname(localPath);

      // Ensure we don't navigate above our virtual root
      if (parent != localPath && parent != '.') {
        await navigateToPath(side, parent);
      }
    } else {
      if (_remotePath != '/') {
        _remotePath = p.dirname(_remotePath);
        if (_remotePath.isEmpty) _remotePath = '/';
        await refreshPanel(PanelSide.remote);
        print('📁 Navigated up to: $_remotePath');
      }
    }
  }

  Future<void> navigateToPath(PanelSide side, String path, {FileItem? selectItem}) async {
    if (side == PanelSide.local) {
      
      // We allow web navigation per a Virtual File System.
      // On Web, we treat the virtual root '/' as accessible.
      // On Desktop/Mobile, we check strict permissions.
      if (!kIsWeb && !await _localFileService.hasAccessToPath(path)) {
        print('⚠️ Path $path is outside granted directory');
        _lastError = 'Cannot access paths outside the granted directory. Please grant access to a parent folder.';
        notifyListeners();
        
        // Attempt to request access to the new path
        final newGrant = await _localFileService.requestDirectoryAccess(
          initialDirectory: path,
        );
        
        if (newGrant != null) {
          path = newGrant; 
        } else {
          return; 
        }
      } else if (kIsWeb && !await _localFileService.hasAccessToPath(path)) {
         // On Web, if we try to go somewhere our virtual tree doesn't know about
         // (should only be possible via manual manipulation), block it.
         print('⚠️ Virtual path not found: $path');
         return;
      }
      
      _localFileService.currentPath = path; 
      await _loadLocalFiles();
      
      if (selectItem != null && _localFiles != null) {
        try {
          final itemToSelect = _localFiles!.firstWhere(
            (file) => file.path == selectItem.path
          );
          _localSelection.clear();
          _localSelection.add(itemToSelect);
          _lastSelectedLocal = itemToSelect;
          _itemToScrollTo = itemToSelect; 
        } catch (e) {
          print('⚠️ Could not find item to select after navigation: ${selectItem.name}');
        }
      }
      
      notifyListeners();
      print('📁 Navigated to: $localPath');
    } else {
      // Remote Navigation Logic
      _remotePath = path;
      await refreshPanel(PanelSide.remote);
      
      if (selectItem != null && _remoteFiles != null) {
        try {
          final itemToSelect = _remoteFiles!.firstWhere(
            (file) => file.uuid == selectItem.uuid
          );
          _remoteSelection.clear();
          _remoteSelection.add(itemToSelect);
          _lastSelectedRemote = itemToSelect;
          _itemToScrollTo = itemToSelect; 
        } catch (e) {
          print('⚠️ Could not find item to select after navigation: ${selectItem.name}');
        }
      }
      
      print('📁 Navigated to: $_remotePath');
    }
  }

  Future<void> navigateInto(PanelSide side, FileItem item) async {
    if (!item.isFolder) return;

    if (side == PanelSide.local) {
      if (item.path != null) {
        await navigateToPath(side, item.path!);
      }
    } else {
      final newPath = p.posix.join(_remotePath, item.name);
      print('🔍 Attempting to navigate to: $newPath');
      
      try {
        await navigateToPath(side, newPath);
      } catch (e) {
        print('⚠️ Navigation failed: $e');
        
        _lastError = 'Cannot open folder: ${item.name}. Path may not exist.';
        notifyListeners();
      }
    }
  }

  bool isSelected(PanelSide side, FileItem item) {
    return side == PanelSide.local
        ? _localSelection.contains(item)
        : _remoteSelection.contains(item);
  }

  void toggleSelection(PanelSide side, FileItem item, {bool shiftKey = false, bool ctrlKey = false}) {
    final selection = side == PanelSide.local ? _localSelection : _remoteSelection;
    final files = side == PanelSide.local ? _localFiles : _remoteFiles; 
    final lastSelected = side == PanelSide.local ? _lastSelectedLocal : _lastSelectedRemote;

    if (shiftKey && lastSelected != null && files != null) {
      final startIdx = files.indexOf(lastSelected);
      final endIdx = files.indexOf(item);
      if (startIdx != -1 && endIdx != -1) {
        final start = startIdx < endIdx ? startIdx : endIdx;
        final end = startIdx < endIdx ? endIdx : startIdx;
        for (var i = start; i <= end; i++) {
          selection.add(files[i]);
        }
      }
    } else if (ctrlKey) {
      if (selection.contains(item)) {
        selection.remove(item);
      } else {
        selection.add(item);
      }
    } else {
      selection.clear();
      selection.add(item);
    }

    if (side == PanelSide.local) {
      _lastSelectedLocal = item;
    } else {
      _lastSelectedRemote = item;
    }

    notifyListeners();
  }

  void selectAll(PanelSide side) {
    final selection = side == PanelSide.local ? _localSelection : _remoteSelection;
    final files = side == PanelSide.local ? _localFiles : _remoteFiles; 
    if (files != null) {
      selection.addAll(files);
      notifyListeners();
    }
  }

  void clearSelection(PanelSide side) {
    if (side == PanelSide.local) {
      _localSelection.clear();
      _lastSelectedLocal = null;
    } else {
      _remoteSelection.clear();
      _lastSelectedRemote = null;
    }
    notifyListeners();
  }
  
  // File operations
  
  Future<void> uploadFiles(List<FileItem> files, {String? targetPath}) async {
    
    print('');
    print('═══════════════════════════════════════════');
    print('📤 UPLOAD STARTED (${_cloudClient.providerName})');
    print('═══════════════════════════════════════════');
    print('Files to upload: ${files.length}');
    print('Target path: ${targetPath ?? _remotePath}');
    
    final target = targetPath ?? _remotePath;
    
    // Get credentials (provider-specific)
    Map<String, String>? creds;
    String? identityLog; // For logging purposes

    if (_cloudClient is InternxtClientAdapter) {
      creds = await (_cloudClient as InternxtClientAdapter).config.readCredentials();
      identityLog = creds?['email'];
    } else if (_cloudClient is FilenClientAdapter) {
      creds = await (_cloudClient as FilenClientAdapter).filenConfig.readCredentials();
      identityLog = creds?['email'];
    } else if (_cloudClient is SFTPClientAdapter) {
      creds = await (_cloudClient as SFTPClientAdapter).config.readCredentials();
      if (creds != null) identityLog = '${creds['username']}@${creds['host']}';
    } else if (_cloudClient is WebDavClientAdapter) {
      creds = await (_cloudClient as WebDavClientAdapter).config.readCredentials();
      if (creds != null) identityLog = '${creds['username']}@${creds['host']}';
    }
    
    if (creds == null) {
      print('❌ ERROR: Not authenticated');
      throw Exception('Not authenticated');
    }
    
    print('✅ Credentials loaded for: $identityLog');
    
    print('');
    print('📊 Calculating sizes...');
    final fileProgresses = <FileProgress>[];
    int totalBytes = 0;
    
    for (final file in files) {
      int fileSize = 0;
      
      if (file.isFolder && file.path != null) {
        fileSize = await _calculateFolderSize(file.path!);
        print('   📁 ${file.name}: ${_formatBytes(fileSize)}');
      } else {
        fileSize = file.size ?? 0;
        print('   📄 ${file.name}: ${_formatBytes(fileSize)}');
      }
      
      fileProgresses.add(FileProgress(
        name: file.name,
        path: file.path!,
        size: fileSize,
      ));
      
      totalBytes += fileSize;
    }
    
    print('📊 Total size: ${_formatBytes(totalBytes)}');
    
    final operation = OperationProgress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OperationType.upload,
      sourcePath: files.length == 1 ? files.first.path! : '${files.length} files',
      targetPath: target,
      fileName: files.length == 1 ? files.first.name : '${files.length} files',
      totalBytes: totalBytes,
      files: fileProgresses,
    );
    
    _operations.add(operation);
    notifyListeners();
    print('✅ Created single operation for ${files.length} files ($totalBytes bytes)');
    
    _runUploadInBackground(operation, files, fileProgresses, target, creds);
  }

  Future<void> _runUploadInBackground(
    OperationProgress operation,
    List<FileItem> files,
    List<FileProgress> fileProgresses,
    String target,
    Map<String, String> creds,
  ) async {
    int completedBytes = 0;
    
    try {
      for (int i = 0; i < files.length; i++) {
        // 1. Check Cancellation/Pause
        if (operation.isCancelled) {
          print('🚫 Upload cancelled by user');
          break;
        }
        
        if (operation.isPaused) {
          print('⏸️  Upload paused, waiting for resume...');
          await operation.pauseFuture;
          print('▶️  Upload resumed, continuing...');
          
          if (operation.isCancelled) {
            print('🚫 Upload cancelled during pause');
            break;
          }
        }
        
        final file = files[i];
        final fileProgress = fileProgresses[i];
        
        print('');
        print('───────────────────────────────────────────');
        print('📤 FILE ${i + 1}/${files.length}');
        print('───────────────────────────────────────────');
        print('Name: ${file.name}');
        print('Path: ${file.path}');
        print('Size: ${fileProgress.size} bytes');
        
        if (file.path == null) {
          print('❌ ERROR: File has no path, skipping');
          fileProgress.error = 'No path';
          notifyListeners();
          continue;
        }

        try {
          if (file.isFolder) {
            await _uploadFolderViaClient(file.path!, target, operation);
          } else {
            // --- STEP A: READ FILE TO MEMORY ---
            print('   📖 Reading file into memory (Size: ${fileProgress.size})...');
            final startRead = DateTime.now();
            
            // CRITICAL LIMITATION: This loads the ENTIRE file into RAM.
            final fileData = await _localFileService.readFile(
              file.path!, 
              fileItem: file 
            );
            
            final readTime = DateTime.now().difference(startRead).inMilliseconds;
            print('   ✅ Read complete (${readTime}ms). Starting upload...');

            // --- STEP B: UPLOAD MEMORY BUFFER ---
            await _cloudClient.uploadFile(
              fileData,
              file.name,
              target,
              onProgress: (current, total) {
                // Update State
                operation.currentBytes = completedBytes + current;
                notifyListeners();

                // Throttle Console Logs (Only log every ~5MB or at 100%)
                if (total > 0 && (current % (1024 * 1024 * 5) < 1024 * 64 || current == total)) {
                   final pct = (current / total * 100).toStringAsFixed(1);
                   print('   🚀 Uploading: $pct% ($current/$total)');
                }
              },
            );
          }
          
          print('   ✅ Upload complete: ${file.name}');
          
          fileProgress.isComplete = true;
          completedBytes += fileProgress.size;
          operation.currentBytes = completedBytes;
          notifyListeners();
          
        } catch (e, stackTrace) {
          if (operation.isCancelled || e.toString().contains('Cancelled')) {
            print('🚫 File upload cancelled: ${file.name}');
            fileProgress.error = 'Cancelled';
            break; // Stop batch
          } else {
            print('❌ UPLOAD FAILED: ${file.name}');
            print('   Error: $e');
            print('   Stack: $stackTrace');
            fileProgress.error = e.toString();
          }
          notifyListeners();
        }
      }

      // Final Status Check
      if (operation.isCancelled) {
        print('🚫 Upload operation cancelled');
        operation.fail('Cancelled by user');
      } else {
        final failedCount = fileProgresses.where((f) => f.error != null).length;
        if (failedCount == 0) {
          print('✅ All files uploaded successfully');
          operation.complete();
        } else if (failedCount == files.length) {
          print('❌ All files failed to upload');
          operation.fail('All files failed');
        } else {
          print('⚠️ Some files failed to upload: $failedCount/${files.length}');
          operation.complete();
        }
      }
    } catch (e) {
      print('❌ Unexpected error in background upload: $e');
      operation.fail(e.toString());
    }
    
    notifyListeners();
    
    await refreshPanel(PanelSide.remote);
    clearSelection(PanelSide.local);
  }

  Future<int> _calculateFolderSize(String folderPath) async {
    try {
      // We use _localFileService to list directory. This handles macOS security scopes 
      // which prevents the "Operation not permitted" error.
      final entities = await _localFileService.listDirectory(folderPath);
      
      if (entities == null) return 0;
      
      int totalSize = 0;
      for (final entity in entities) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            totalSize += stat.size;
          } catch (e) {
            print('⚠️ Could not stat file: ${entity.path}');
          }
        } else if (entity is Directory) {
          // Recursive call for subdirectories using the same safe listing method
          totalSize += await _calculateFolderSize(entity.path);
        }
      }
      return totalSize;
    } catch (e) {
      print('⚠️ Error calculating folder size: $e');
      return 0;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // CHANGED: Download now uses cloud client abstraction
  Future<void> downloadFiles(List<FileItem> files, {String? localPath}) async {
    
    print('');
    print('═══════════════════════════════════════════');
    print('⬇️  DOWNLOAD STARTED (${_cloudClient.providerName})');
    print('═══════════════════════════════════════════');
    print('Files to download: ${files.length}');
    print('Local path: ${localPath ?? _localFileService.currentPath}'); 
    
    final target = localPath ?? _localFileService.currentPath;
    
    Map<String, String>? creds;
    String? identityLog;
    if (_cloudClient is InternxtClientAdapter) {
      creds = await (_cloudClient as InternxtClientAdapter).config.readCredentials();
      identityLog = creds?['email'];
    } else if (_cloudClient is FilenClientAdapter) {
      creds = await (_cloudClient as FilenClientAdapter).filenConfig.readCredentials();
      identityLog = creds?['email'];
    } else if (_cloudClient is SFTPClientAdapter) {
      creds = await (_cloudClient as SFTPClientAdapter).config.readCredentials();
      if (creds != null) identityLog = '${creds['username']}@${creds['host']}';
    } else if (_cloudClient is WebDavClientAdapter) {
      creds = await (_cloudClient as WebDavClientAdapter).config.readCredentials();
      if (creds != null) identityLog = '${creds['username']}@${creds['host']}';
    }
    
    if (creds == null) {
      print('❌ ERROR: Not authenticated');
      throw Exception('Not authenticated');
    }
    
    print('✅ Credentials loaded for: $identityLog');
    
    print('');
    print('📊 Preparing download...');
    final fileProgresses = files.map((f) => FileProgress(
      name: f.name,
      path: f.uuid ?? f.name, 
      size: f.size ?? 0,
    )).toList();
    
    final totalBytes = files.fold(0, (sum, f) => sum + (f.size ?? 0));
    print('📊 Total size: ${_formatBytes(totalBytes)}');
    
    final operation = OperationProgress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OperationType.download,
      sourcePath: files.length == 1 ? files.first.name : '${files.length} files',
      targetPath: target,
      fileName: files.length == 1 ? files.first.name : '${files.length} files',
      totalBytes: totalBytes,
      files: fileProgresses,
    );
    
    _operations.add(operation);
    notifyListeners();
    print('✅ Created single operation for ${files.length} files ($totalBytes bytes)');
    
    _runDownloadInBackground(operation, files, fileProgresses, target, creds);
  }

  Future<void> _runDownloadInBackground(
    OperationProgress operation,
    List<FileItem> files,
    List<FileProgress> fileProgresses,
    String target,
    Map<String, String> creds,
  ) async {
    int completedBytes = 0;
    
    try {
      for (int i = 0; i < files.length; i++) {
        if (operation.isCancelled) {
          print('🚫 Download cancelled by user');
          break;
        }
        
        if (operation.isPaused) {
          print('⏸️  Download paused, waiting for resume...');
          await operation.pauseFuture;
          print('▶️  Download resumed, continuing...');
          
          if (operation.isCancelled) {
            print('🚫 Download cancelled during pause');
            break;
          }
        }
        
        final file = files[i];
        final fileProgress = fileProgresses[i];
        
        print('');
        print('───────────────────────────────────────────');
        print('⬇️  FILE ${i + 1}/${files.length}');
        print('───────────────────────────────────────────');
        print('Name: ${file.name}');
        print('UUID: ${file.uuid}');
        print('Size: ${fileProgress.size} bytes');
        print('Is folder: ${file.isFolder}');

        try {
          if (kIsWeb) {
            // --- WEB DOWNLOAD LOGIC ---
            if (file.isFolder) {
               print('Folder download not supported on Web (requires zipping)');
               // skip or handle error
            } else {
               // 1. Get Path
               final remotePath = p.posix.join(_remotePath, file.name);
               
               // 2. We need to fetch bytes directly. 
               // NOTE: We must ensure our CloudClients have a way to get bytes, or use a temp path approach that returns bytes.
               // Assuming downloadFileByPath might not work on web if it uses File(path).openWrite.
               // We might need to add `downloadFileBytes` to interface, OR hack it:
               
               // For now, assuming standard clients use HTTP, we might need a specific method.
               // But if we assume downloadFileByPath fails, we need:
               final bytes = await _cloudClient.downloadFileBytes(remotePath);

               // 3. Create Blob and Anchor
               final blob = html.Blob([bytes]);
               final url = html.Url.createObjectUrlFromBlob(blob);
               final anchor = html.AnchorElement(href: url)
                 ..setAttribute("download", file.name)
                 ..click();
               html.Url.revokeObjectUrl(url);
            }
            // --- end web logic ---
          } else {
              // --- DESKTOP/MOBILE LOGIC  ---
            final remotePath = p.posix.join(_remotePath, file.name);
            final localFilePath = p.join(target, file.name);
            
            // Use cloud client abstraction
            if (file.isFolder) {
              await _downloadFolderViaClient(remotePath, target, operation);
            } else {
              await _cloudClient.downloadFileByPath(
                remotePath,
                localFilePath,
                onProgress: (current, total) {
                  operation.currentBytes = completedBytes + current;
                  notifyListeners();
                },
              );
            }
            
            print('✅ Download complete: ${file.name}');
            
            fileProgress.isComplete = true;
            completedBytes += fileProgress.size;
            operation.currentBytes = completedBytes;
            
            print('📊 Overall progress: ${operation.currentBytes}/${operation.totalBytes} bytes (${(operation.progress * 100).toStringAsFixed(1)}%)');
            notifyListeners();
          } // end desktop logic
          
        } catch (e, stackTrace) {
          if (operation.isCancelled || e.toString().contains('Cancelled')) {
            print('🚫 File download cancelled: ${file.name}');
            fileProgress.error = 'Cancelled';
            break;
          } else {
            print('❌ DOWNLOAD FAILED: ${file.name}');
            print('   Error: $e');
            fileProgress.error = e.toString();
          }
          notifyListeners();
        }
      }

      if (operation.isCancelled) {
        print('🚫 Download operation cancelled');
        operation.fail('Cancelled by user');
      } else {
        final failedCount = fileProgresses.where((f) => f.error != null).length;
        if (failedCount == 0) {
          print('✅ All files downloaded successfully');
          operation.complete();
        } else if (failedCount == files.length) {
          print('❌ All files failed to download');
          operation.fail('All files failed');
        } else {
          print('⚠️ Some files failed to download: $failedCount/${files.length}');
          operation.complete();
        }
      }
    } catch (e) {
      print('❌ Unexpected error in background download: $e');
      operation.fail(e.toString());
    }
    
    notifyListeners();
    
    print('');
    print('═══════════════════════════════════════════');
    print('⬇️  DOWNLOAD BATCH COMPLETE');
    print('═══════════════════════════════════════════');
    print('');
    
    await refreshPanel(PanelSide.local);
    clearSelection(PanelSide.remote);
  }
  
  // Helper methods for folder operations via cloud client
  Future<void> _uploadFolderViaClient(String localPath, String remotePath, OperationProgress operation) async {
    if (kIsWeb) return;
    
    final folderName = p.basename(localPath);
    final newRemotePath = p.posix.join(remotePath, folderName);

    try {
      await _cloudClient.createFolderPath(newRemotePath);
    } catch (e) {
      // Folder might already exist
    }

    // Use listDirectory to get entities (handles listing permissions)
    final entities = await _localFileService.listDirectory(localPath);
    if (entities == null) return;

    for (final entity in entities) {
      if (operation.isCancelled) break;
      
      if (entity is File) {
        try {
          final fileName = p.basename(entity.path);
          // FIX: Use readFile to get bytes (handles reading permissions)
          final fileData = await _localFileService.readFile(entity.path);
          
          await _cloudClient.uploadFile(fileData, fileName, newRemotePath);
          operation.currentBytes += fileData.length;
          notifyListeners();
        } catch (e) {
          print('⚠️ Error reading/uploading file in folder ${entity.path}: $e');
        }
      } else if (entity is Directory) {
        await _uploadFolderViaClient(entity.path, newRemotePath, operation);
      }
    }
  }

  Future<void> _downloadFolderViaClient(String remotePath, String localPath, OperationProgress operation) async {
    if (kIsWeb) return;
    
    final folderName = p.basename(remotePath);
    final newLocalPath = p.join(localPath, folderName);

    await Directory(newLocalPath).create(recursive: true);

    final contents = await _cloudClient.listPath(remotePath);
    
    for (final file in contents['files']) {
      if (operation.isCancelled) break;
      
      final fileName = file['name'];
      final fileSize = int.tryParse(file['size']?.toString() ?? '0') ?? 0;
      final localFilePath = p.join(newLocalPath, fileName);
      
      await _cloudClient.downloadFileByPath(
        p.posix.join(remotePath, fileName),
        localFilePath,
      );
      
      operation.currentBytes += fileSize;
      notifyListeners();
    }

    for (final folder in contents['folders']) {
      if (operation.isCancelled) break;
      
      await _downloadFolderViaClient(
        p.posix.join(remotePath, folder['name']),
        newLocalPath,
        operation,
      );
    }
  }

  // CHANGED: Uses cloud client abstraction
  Future<void> deleteFiles(PanelSide side, List<FileItem> files) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      for (final file in files) {
        if (side == PanelSide.local) {
          if (file.isFolder) {
            await Directory(file.path!).delete(recursive: true);
          } else {
            await File(file.path!).delete();
          }
        } else {
          await _cloudClient.deletePath(p.posix.join(_remotePath, file.name));
        }
      }

      await refreshPanel(side);
      clearSelection(side);
    } catch (e) {
      print('❌ Error deleting files: $e');
      _lastError = 'Delete failed: $e';
      notifyListeners();
    }
  }

  // CHANGED: Uses cloud client abstraction
  Future<void> moveFiles(PanelSide side, List<FileItem> files, String targetPath) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      for (final file in files) {
        if (side == PanelSide.local) {
          final newPath = p.join(targetPath, file.name);
          if (file.isFolder) {
            await Directory(file.path!).rename(newPath);
          } else {
            await File(file.path!).rename(newPath);
          }
        } else {
          final sourcePath = p.posix.join(_remotePath, file.name);
          await _cloudClient.movePath(sourcePath, targetPath);
        }
      }

      await refreshPanel(side);
      clearSelection(side);
    } catch (e) {
      print('❌ Error moving files: $e');
      _lastError = 'Move failed: $e';
      notifyListeners();
      await refreshPanel(side);
    }
  }

  // CHANGED: Uses cloud client abstraction
  Future<void> copyFiles(PanelSide side, List<FileItem> files, String targetPath) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      for (final file in files) {
        if (side == PanelSide.local) {
          final newPath = p.join(targetPath, file.name);
          if (file.isFolder) {
            await _copyDirectory(file.path!, newPath);
          } else {
            await File(file.path!).copy(newPath);
          }
        } else {
          if (kIsWeb) throw UnsupportedError('Remote copy not supported on web');
          final tempPath = p.join(Directory.systemTemp.path, file.name);
          await _cloudClient.downloadFileByPath(p.posix.join(_remotePath, file.name), tempPath);
          final data = await File(tempPath).readAsBytes();
          await _cloudClient.uploadFile(data, file.name, targetPath);
          await File(tempPath).delete();
        }
      }

      await refreshPanel(side);
    } catch (e) {
      print('❌ Error copying files: $e');
      _lastError = 'Copy failed: $e';
      notifyListeners();
    }
  }

  Future<void> _copyDirectory(String source, String target) async {
    if (kIsWeb) return;
    await Directory(target).create(recursive: true);
    final dir = Directory(source);
    final entities = await dir.list().toList();
    
    for (final entity in entities) {
      if (entity is File) {
        await entity.copy(p.join(target, p.basename(entity.path)));
      } else if (entity is Directory) {
        await _copyDirectory(entity.path, p.join(target, p.basename(entity.path)));
      }
    }
  }

  // CHANGED: Uses cloud client abstraction
  Future<void> renameFile(PanelSide side, FileItem file, String newName) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      if (side == PanelSide.local) {
        final newPath = p.join(p.dirname(file.path!), newName);
        if (file.isFolder) {
          await Directory(file.path!).rename(newPath);
        } else {
          await File(file.path!).rename(newPath);
        }
      } else {
        await _cloudClient.renamePath(p.posix.join(_remotePath, file.name), newName);
      }

      await refreshPanel(side);
    } catch (e) {
      print('❌ Error renaming file: $e');
      _lastError = 'Rename failed: $e';
      notifyListeners();
    }
  }

  // CHANGED: Uses cloud client abstraction
  Future<void> createFolder(PanelSide side, String name) async {
    if (kIsWeb && side == PanelSide.local) return;
    try {
      if (side == PanelSide.local) {
        await Directory(p.join(localPath, name)).create();
      } else {
        await _cloudClient.createFolderPath(p.posix.join(_remotePath, name));
      }

      await refreshPanel(side);
    } catch (e) {
      print('❌ Error creating folder: $e');
      _lastError = 'Create folder failed: $e';
      notifyListeners();
    }
  }

  // CHANGED: Search methods now use cloud client (if supported)
  Future<Map<String, List<FileItem>>> searchFiles(String query) async {
    if (_isSearching) return {};
    _isSearching = true;
    notifyListeners();
    
    try {
      // Check if cloud client supports search
      if (_cloudClient is InternxtClientAdapter) {
        final adapter = _cloudClient as InternxtClientAdapter;
        final results = await adapter.search(query, detailed: true);
        
        final folders = (results['folders'] as List<dynamic>?)
            ?.map((item) => FileItem(
                  name: item['fullPath'] ?? item['name'], 
                  isFolder: true,
                  uuid: item['uuid'],
                  path: item['fullPath'], 
                ))
            .toList() ?? [];
            
        final files = (results['files'] as List<dynamic>?)
            ?.map((item) {
              final plainName = item['name'] ?? 'Unknown';
              final fileType = item['type'] ?? '';
              final fullName = (fileType.isNotEmpty && !plainName.endsWith(fileType)) 
                  ? '$plainName.$fileType' 
                  : plainName;
              final displayName = item['fullPath'] ?? fullName;
              
              return FileItem(
                name: displayName,
                isFolder: false,
                uuid: item['uuid'],
                path: item['fullPath'], 
              );
            })
            .toList() ?? [];

        _isSearching = false;
        notifyListeners();
        return {'folders': folders, 'files': files};
      } else {
        // Filen or other providers - implement as needed
        throw UnsupportedError('Search not supported for ${_cloudClient.providerName}');
      }
    } catch (e) {
      _lastError = "Search failed: $e";
      _isSearching = false;
      notifyListeners();
      return {};
    }
  }

  Future<List<FileItem>> findFiles(String pattern) async {
    if (_isSearching) return [];
    _isSearching = true;
    notifyListeners();
    
    try {
      // Check if cloud client supports find
      if (_cloudClient is InternxtClientAdapter) {
        final adapter = _cloudClient as InternxtClientAdapter;
        final results = await adapter.findFiles(_remotePath, pattern, maxDepth: -1);
        
        final files = results
            .map((item) {
              final plainName = item['name'] ?? 'Unknown';
              final fileType = item['fileType'] ?? '';
              final fullName = (fileType.isNotEmpty && !plainName.endsWith(fileType)) 
                  ? '$plainName.$fileType' 
                  : plainName;
              final displayName = item['fullPath'] ?? fullName;

              return FileItem(
                name: displayName,
                isFolder: false,
                uuid: item['uuid'],
                size: item['size'] as int?,
                path: item['fullPath'], 
                updatedAt: DateTime.tryParse(item['updatedAt'] ?? ''),
              );
            })
            .toList();

        _isSearching = false;
        notifyListeners();
        return files;
      } else {
        throw UnsupportedError('Find not supported for ${_cloudClient.providerName}');
      }
    } catch (e) {
      _lastError = "Find failed: $e";
      _isSearching = false;
      notifyListeners();
      return [];
    }
  }

  void pauseOperation(String operationId) {
    try {
      final operation = _operations.firstWhere((op) => op.id == operationId);
      operation.pause();
      notifyListeners();
    } catch (e) {
      print('⚠️ Error pausing operation: $e');
    }
  }

  void resumeOperation(String operationId) {
    try {
      final operation = _operations.firstWhere((op) => op.id == operationId);
      operation.resume();
      notifyListeners();
    } catch (e) {
      print('⚠️ Error resuming operation: $e');
    }
  }

  void cancelOperation(String operationId) {
    try {
      final operation = _operations.firstWhere((op) => op.id == operationId);
      operation.cancel();
      // Optionally remove it immediately or let the UI handle it
      notifyListeners();
    } catch (e) {
      print('⚠️ Error cancelling operation: $e');
    }
  }
}