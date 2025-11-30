// webdav_filesystem.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import 'filen.dart'; // exports FilenClient and ConfigService

// --- Helper: Virtual FileStat ---
class _VirtualFileStat implements io.FileStat {
  @override
  final DateTime modified;
  @override
  final int size;
  @override
  final FileSystemEntityType type;

  _VirtualFileStat({
    required this.modified,
    required this.size,
    required this.type,
  });

  @override
  int get mode => 0;
  @override
  DateTime get accessed => modified;
  @override
  DateTime get changed => modified;

  @override
  String modeString() {
    switch (type) {
      case FileSystemEntityType.file:
        return '-rw-r--r--';
      case FileSystemEntityType.directory:
        return 'drwxr-xr-x';
      default:
        return '----------';
    }
  }

  @override
  String toString() =>
      'VirtualFileStat(type: $type, size: $size, mod: $modified)';
}

// --- Helper: Streaming File Sink ---
class FilenFileSink implements io.IOSink {
  final FilenFile filenFile;
  final FilenClient client;
  final String remotePath;
  final bool preserveTimestamps;

  static const int _maxMemorySize = 100 * 1024 * 1024; // 100MB
  bool _usingDisk = false;
  io.BytesBuilder _memoryBuffer = io.BytesBuilder(copy: false);
  io.File? _tempFile;
  io.IOSink? _tempFileSink;
  int _bytesWritten = 0;

  final Completer<void> _doneCompleter = Completer<void>();

  FilenFileSink(
    this.filenFile,
    this.client,
    this.remotePath,
    this.preserveTimestamps,
  );

  void _switchToDisk() {
    if (_usingDisk) return;

    client._log('WebDAV: Switching to disk for large upload $remotePath');
    _usingDisk = true;
    _tempFile = io.File(p.join(
      io.Directory.systemTemp.path,
      'filen-webdav-upload-${DateTime.now().millisecondsSinceEpoch}',
    ));
    _tempFileSink = _tempFile!.openWrite();

    final bufferedBytes = _memoryBuffer.takeBytes();
    if (bufferedBytes.isNotEmpty) {
      _tempFileSink!.add(bufferedBytes);
    }

    _memoryBuffer = io.BytesBuilder(copy: false);
  }

  @override
  void add(List<int> data) {
    if (_doneCompleter.isCompleted) {
      throw Exception('Cannot write to a closed sink');
    }

    _bytesWritten += data.length;

    if (!_usingDisk && _bytesWritten > _maxMemorySize) {
      _switchToDisk();
    }

    if (_usingDisk) {
      _tempFileSink!.add(data);
    } else {
      _memoryBuffer.add(data);
    }
  }

  @override
  Future<void> close() async {
    if (_doneCompleter.isCompleted) {
      return _doneCompleter.future;
    }

    client._log('WebDAV: close() called on file sink for $remotePath');

    try {
      final remoteParentPath = p.dirname(remotePath);
      final remoteFilename = p.basename(remotePath);

      // Resolve parent folder
      final parentResolved = await client.resolvePath(remoteParentPath);
      if (parentResolved['type'] != 'folder') {
        throw io.FileSystemException('Invalid parent path', remoteParentPath);
      }

      final io.File localFileToUpload; // Non-nullable declaration

      if (_usingDisk) {
        await _tempFileSink!.close();
        localFileToUpload = _tempFile!;
        client
            ._log('WebDAV: Uploading large file from disk: ${_tempFile!.path}');
      } else {
        final bytes = _memoryBuffer.takeBytes();
        client._log(
            'WebDAV: Uploading small file from memory (${bytes.length} bytes)');
        final tempFile = io.File(p.join(
          io.Directory.systemTemp.path,
          'filen-webdav-upload-small-${DateTime.now().millisecondsSinceEpoch}',
        ));
        await tempFile.writeAsBytes(bytes);
        localFileToUpload = tempFile;
      }

      // Get timestamps if preserving
      String? creationTime;
      String? modificationTime;
      if (preserveTimestamps) {
        try {
          final stat = await localFileToUpload.stat();
          modificationTime = stat.modified.millisecondsSinceEpoch.toString();
          creationTime = stat.changed.millisecondsSinceEpoch.toString();
        } catch (_) {}
      }

      // Upload the file
      await client.uploadFile(
        localFileToUpload,
        parentResolved['uuid'],
        creationTime: creationTime,
        modificationTime: modificationTime,
      );

      _doneCompleter.complete();
    } catch (e, s) {
      client._log('WebDAV: Error during sink close: $e\n$s');
      _doneCompleter.completeError(e, s);
      throw io.FileSystemException('Error writing file', remotePath);
    } finally {
      if (_tempFile != null && await _tempFile!.exists()) {
        await _tempFile!.delete();
      }
    }

    return _doneCompleter.future;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    client._log('WebDAV Sink Error: $error');
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.completeError(error, stackTrace);
    }
  }

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future get done => _doneCompleter.future;

  @override
  Encoding encoding = utf8;

  @override
  void write(Object? obj) => add(encoding.encode(obj.toString()));

  @override
  void writeAll(Iterable objects, [String separator = ""]) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => add([charCode]);

  @override
  void writeln([Object? obj = ""]) => write("$obj\n");

  @override
  Future flush() async {
    if (_usingDisk) {
      await _tempFileSink?.flush();
    }
  }
}

// --- Main FileSystem Implementation ---
class FilenFileSystem implements FileSystem {
  final FilenClient client;

  @override
  final p.Context path;

  FilenFileSystem({required this.client}) : path = p.posix;

  @override
  String getPath(dynamic path) {
    if (path is Uri) {
      return path.toFilePath(windows: false);
    } else if (path is FileSystemEntity) {
      return path.path;
    } else if (path is String) {
      return path;
    }
    throw ArgumentError('Invalid path type: ${path.runtimeType}');
  }

  @override
  Directory directory(dynamic path) {
    return FilenDirectory(
      client: client,
      path: getPath(path),
      fs: this,
    );
  }

  @override
  File file(dynamic path) {
    return FilenFile(
      client: client,
      path: getPath(path),
      fs: this,
    );
  }

  @override
  Future<FileSystemEntityType> type(String path,
      {bool followLinks = true}) async {
    try {
      final resolved = await client.resolvePath(path);
      if (resolved['type'] == 'folder') return FileSystemEntityType.directory;
      if (resolved['type'] == 'file') return FileSystemEntityType.file;
    } catch (e) {
      // Path not found
    }
    return FileSystemEntityType.notFound;
  }

  @override
  Future<io.FileStat> stat(String path) async {
    try {
      final resolved = await client.resolvePath(path);
      final metadata = resolved['metadata'] as Map<String, dynamic>?;
      final isFolder = resolved['type'] == 'folder';

      DateTime mTime;
      if (metadata != null && metadata['lastModified'] != null) {
        final lastMod = metadata['lastModified'];
        if (lastMod is int) {
          mTime = DateTime.fromMillisecondsSinceEpoch(lastMod);
        } else if (lastMod is String) {
          mTime = DateTime.tryParse(lastMod) ?? DateTime.now();
        } else {
          mTime = DateTime.now();
        }
      } else {
        mTime = DateTime.now();
      }

      return _VirtualFileStat(
        type: isFolder
            ? FileSystemEntityType.directory
            : FileSystemEntityType.file,
        size: isFolder ? -1 : (metadata?['size'] ?? 0),
        modified: mTime,
      );
    } catch (e) {
      return _VirtualFileStat(
        type: FileSystemEntityType.notFound,
        size: -1,
        modified: DateTime(0),
      );
    }
  }

  @override
  Future<bool> isDirectory(String path) async {
    return await type(path) == FileSystemEntityType.directory;
  }

  @override
  Future<bool> isFile(String path) async {
    return await type(path) == FileSystemEntityType.file;
  }

  @override
  Future<bool> isLink(String path) async => false;

  @override
  bool isDirectorySync(String path) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  bool isFileSync(String path) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  bool isLinkSync(String path) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Future<bool> identical(String path1, String path2) async {
    return path.absolute(path1) == path.absolute(path2);
  }

  @override
  bool identicalSync(String path1, String path2) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  io.FileStat statSync(String path) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  FileSystemEntityType typeSync(String path, {bool followLinks = true}) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Directory get currentDirectory => LocalFileSystem().currentDirectory;

  @override
  set currentDirectory(dynamic path) =>
      throw UnimplementedError('Not applicable for virtual filesystem');

  @override
  Directory get systemTempDirectory => LocalFileSystem().systemTempDirectory;

  @override
  Directory get homeDirectory =>
      throw UnimplementedError('Not applicable for virtual filesystem');

  @override
  Link link(dynamic path) =>
      throw UnimplementedError('Links are not supported');

  @override
  String get pathSeparator => '/';

  @override
  bool get isWatchSupported => false;

  @override
  Future<String> symbolicLinkTarget(String path) =>
      throw UnimplementedError('Links not supported');

  @override
  Future<File> createTemp(String prefix) => throw UnimplementedError(
      'Temp operations not supported on virtual filesystem');

  @override
  File createTempSync(String prefix) =>
      throw UnimplementedError('Sync operations not supported');
}

// --- Directory Implementation ---
class FilenDirectory implements Directory {
  final FilenClient client;

  @override
  final String path;

  @override
  final FilenFileSystem fs;

  FilenDirectory({
    required this.client,
    required this.path,
    required this.fs,
  });

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    if (recursive) {
      throw UnimplementedError('Recursive listing not supported');
    }

    return Stream.fromFuture(() async {
      try {
        final resolved = await client.resolvePath(path);
        if (resolved['type'] != 'folder') return <FileSystemEntity>[];

        final folders = await client.listFoldersAsync(resolved['uuid']);
        final files = await client.listFolderFiles(resolved['uuid']);

        final List<FileSystemEntity> entities = [];

        for (var folder in folders) {
          final name = folder['name'] ?? 'unknown_folder';
          entities.add(fs.directory(p.join(path, name)));
        }

        for (var file in files) {
          final name = file['name'] ?? 'unknown_file';
          entities.add(fs.file(p.join(path, name)));
        }

        return entities;
      } catch (e) {
        client._log('WebDAV: Error listing $path: $e');
        return <FileSystemEntity>[];
      }
    }())
        .expand((entities) => entities);
  }

  @override
  Future<Directory> create({bool recursive = false}) async {
    client._log('WebDAV: MKCOL $path');
    await client.createFolderRecursive(path);
    return this;
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    client._log('WebDAV: DELETE (Folder) $path');
    final resolved = await client.resolvePath(path);
    await client.trashItem(resolved['uuid'], 'folder');
    return this;
  }

  @override
  Future<Directory> rename(String newPath) async {
    client._log('WebDAV: MOVE (Folder) $path -> $newPath');
    final newName = p.basename(newPath);
    final newParentPath = p.dirname(newPath);
    final oldParentPath = p.dirname(path);

    final resolved = await client.resolvePath(path);

    if (newParentPath == oldParentPath) {
      // Just rename
      await client.renameItem(resolved['uuid'], newName, 'folder');
    } else {
      // Move to new parent
      final destResolved = await client.resolvePath(newParentPath);
      await client.moveItem(resolved['uuid'], destResolved['uuid'], 'folder');

      // Then rename if needed
      if (p.basename(path) != newName) {
        await client.renameItem(resolved['uuid'], newName, 'folder');
      }
    }

    return fs.directory(newPath);
  }

  @override
  Future<bool> exists() async {
    try {
      final resolved = await client.resolvePath(path);
      return resolved['type'] == 'folder';
    } catch (e) {
      return false;
    }
  }

  @override
  Future<io.FileStat> stat() async => fs.stat(path);

  // Note: Must check of Filen does support setting timestamps directly on folders via API
  // This is a stub for interface compliance
  @override
  Future<void> setStat(io.FileStat stat) async {
    client
        ._log('WebDAV: PROPPATCH (Folder) $path - not supported by Filen API');
    // Filen API maybe doesn't provide folder timestamp updates
    // Silently ignore or throw based on requirements
  }

  @override
  Directory get absolute => this;

  @override
  Future<String> resolveSymbolicLinks() async => path;

  @override
  String resolveSymbolicLinksSync() =>
      throw UnimplementedError('Sync operations not supported');

  @override
  void createSync({bool recursive = false}) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  void deleteSync({bool recursive = false}) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  bool existsSync() =>
      throw UnimplementedError('Sync operations not supported');

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Directory renameSync(String newPath) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Directory get parent => fs.directory(p.dirname(path));

  @override
  Uri get uri => Uri.parse(path);

  @override
  FileSystem get fileSystem => fs;

  @override
  String get basename => p.basename(path);

  @override
  String get dirname => p.dirname(path);

  @override
  bool get isAbsolute => p.isAbsolute(path);

  @override
  io.FileStat statSync() =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) =>
      throw UnimplementedError('Watch not supported on virtual filesystem');

  @override
  Directory childDirectory(String basename) =>
      fs.directory(p.join(path, basename));

  @override
  File childFile(String basename) => fs.file(p.join(path, basename));

  @override
  Link childLink(String basename) => fs.link(p.join(path, basename));

  @override
  Future<Directory> createTemp([String? prefix]) => throw UnimplementedError(
      'Temp operations not supported on virtual filesystem');

  @override
  Directory createTempSync([String? prefix]) =>
      throw UnimplementedError('Sync operations not supported');
}

// --- File Implementation ---
class FilenFile implements File {
  final FilenClient client;

  @override
  final String path;

  @override
  final FilenFileSystem fs;

  FilenFile({
    required this.client,
    required this.path,
    required this.fs,
  });

  @override
  Future<Uint8List> readAsBytes() async {
    client._log('WebDAV: GET $path');
    try {
      final resolved = await client.resolvePath(path);
      if (resolved['type'] != 'file') {
        throw io.FileSystemException('Path is not a file', path);
      }

      final result = await client.downloadFile(resolved['uuid']);
      return result['data'] as Uint8List;
    } catch (e) {
      client._log('WebDAV: Error reading $path: $e');
      throw io.FileSystemException('Error reading file', path);
    }
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    io.FileMode mode = io.FileMode.write,
    bool flush = false,
  }) async {
    client._log('WebDAV: PUT (writeAsBytes) $path (${bytes.length} bytes)');

    final sink = openWrite(mode: mode);
    sink.add(bytes);
    await sink.close();
    return this;
  }

  @override
  io.IOSink openWrite({
    io.FileMode mode = io.FileMode.write,
    Encoding encoding = utf8,
  }) {
    client._log('WebDAV: PUT (openWrite) $path');
    return FilenFileSink(
      this,
      client,
      path,
      true, // preserveTimestamps
    );
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    client._log('WebDAV: DELETE (File) $path');
    final resolved = await client.resolvePath(path);
    await client.trashItem(resolved['uuid'], 'file');
    return this;
  }

  @override
  Future<File> rename(String newPath) async {
    client._log('WebDAV: MOVE (File) $path -> $newPath');
    final newName = p.basename(newPath);
    final newParentPath = p.dirname(newPath);
    final oldParentPath = p.dirname(path);

    final resolved = await client.resolvePath(path);

    if (newParentPath == oldParentPath) {
      // Just rename
      await client.renameItem(resolved['uuid'], newName, 'file');
    } else {
      // Move to new parent
      final destResolved = await client.resolvePath(newParentPath);
      await client.moveItem(resolved['uuid'], destResolved['uuid'], 'file');

      // Then rename if needed
      if (p.basename(path) != newName) {
        await client.renameItem(resolved['uuid'], newName, 'file');
      }
    }

    return fs.file(newPath);
  }

  @override
  Future<File> copy(String newPath) async {
    client._log('WebDAV: COPY $path -> $newPath');

    final bytes = await readAsBytes();
    final newFile = fs.file(newPath) as FilenFile;
    await newFile.writeAsBytes(bytes);

    return newFile;
  }

  @override
  Future<bool> exists() async {
    try {
      final resolved = await client.resolvePath(path);
      return resolved['type'] == 'file';
    } catch (e) {
      return false;
    }
  }

  @override
  Future<io.FileStat> stat() async => fs.stat(path);

  // Note: Filen doesn't support setting timestamps directly via API
  // This is a stub for interface compliance
  @override
  Future<void> setStat(io.FileStat stat) async {
    client._log('WebDAV: PROPPATCH (File) $path - not supported by Filen API');
    // Filen API doesn't provide file timestamp updates after upload
    // Silently ignore or throw based on requirements
  }

  @override
  File get absolute => this;

  @override
  Future<String> resolveSymbolicLinks() async => path;

  @override
  String resolveSymbolicLinksSync() =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      throw UnimplementedError('Use writeAsBytes to create files');

  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  void deleteSync({bool recursive = false}) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  bool existsSync() =>
      throw UnimplementedError('Sync operations not supported');

  @override
  File renameSync(String newPath) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  File copySync(String newPath) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Future<int> length() async => (await stat()).size;

  @override
  int lengthSync() => throw UnimplementedError('Sync operations not supported');

  @override
  Future<DateTime> lastModified() async => (await stat()).modified;

  @override
  DateTime lastModifiedSync() =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Future<io.RandomAccessFile> open({io.FileMode mode = io.FileMode.read}) =>
      throw UnimplementedError(
          'Random access not supported on virtual filesystem');

  @override
  io.RandomAccessFile openSync({io.FileMode mode = io.FileMode.read}) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    if (start != null || end != null) {
      return Stream.fromFuture(readAsBytes().then((bytes) {
        final s = start ?? 0;
        final e = end ?? bytes.length;
        return bytes.sublist(s, e);
      }));
    }
    return Stream.fromFuture(readAsBytes());
  }

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) async =>
      LineSplitter().convert(await readAsString(encoding: encoding));

  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());

  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Future<File> writeAsString(
    String contents, {
    io.FileMode mode = io.FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    return writeAsBytes(encoding.encode(contents), mode: mode, flush: flush);
  }

  @override
  void writeAsStringSync(
    String contents, {
    io.FileMode mode = io.FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    io.FileMode mode = io.FileMode.write,
    bool flush = false,
  }) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Directory get parent => fs.directory(p.dirname(path));

  @override
  Uri get uri => Uri.parse(path);

  @override
  FileSystem get fileSystem => fs;

  @override
  String get basename => p.basename(path);

  @override
  String get dirname => p.dirname(path);

  @override
  bool get isAbsolute => p.isAbsolute(path);

  @override
  io.FileStat statSync() =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) =>
      throw UnimplementedError('Watch not supported on virtual filesystem');

  @override
  Future<DateTime> lastAccessed() => lastModified();

  @override
  DateTime lastAccessedSync() =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Future setLastAccessed(DateTime time) =>
      throw UnimplementedError('Not supported on virtual filesystem');

  @override
  void setLastAccessedSync(DateTime time) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Future setLastModified(DateTime time) =>
      throw UnimplementedError('Not supported, use setStat');

  @override
  void setLastModifiedSync(DateTime time) =>
      throw UnimplementedError('Sync operations not supported');

  @override
  Uint8List readAsBytesSync() =>
      throw UnimplementedError('Sync operations not supported');
}

// --- Extension for FilenClient logging ---
extension FilenClientLogging on FilenClient {
  void _log(String message) {
    if (debugMode) {
      print('🔍 [DEBUG] $message');
    }
  }
}
