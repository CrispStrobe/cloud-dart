#!/usr/bin/env dart

/// ---------------------------------------------------------------------------
/// FILEN CLI (v0.0.4)
/// ---------------------------------------------------------------------------
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:universal_html/html.dart' as html; // For Web Crypto
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'package:convert/convert.dart';
import 'package:hex/hex.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart' hide Digest, HMac, SHA512Digest;
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'dart:js_util' as js_util; // For calling JS methods safely

// WebDAV Imports
import 'package:shelf/shelf.dart'; // for Pipeline/Middleware
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart'; // Exports: ShelfDAV, DAVConfig, BasicAuthenticationProvider, RoleBasedAuthorizationProvider
import 'package:file/file.dart' as file_pkg;
import 'package:file/local.dart';
import 'webdav_filesystem.dart';

void main(List<String> arguments) async {
  final cli = FilenCLI();
  await cli.run(arguments);
}

// Helper class to capture the hash result
class DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) {
    value = data;
  }

  @override
  void close() {}
}

// Cache entry helper
class _CacheEntry {
  final dynamic items;
  final DateTime timestamp;
  _CacheEntry({required this.items, required this.timestamp});
}

class FilenCLI {
  final ConfigService config;
  late final FilenClient client;
  bool debugMode = false;
  bool force = false;

  FilenCLI()
      : config = ConfigService(
            configPath: p.join(
                Platform.environment['HOME'] ??
                    Platform.environment['USERPROFILE'] ??
                    '.',
                '.filen-cli')) {
    client = FilenClient(config: config);
  }

  Future<void> run(List<String> arguments) async {
    final parser = ArgParser()
      ..addFlag('verbose', abbr: 'v', help: 'Enable verbose debug output')
      ..addFlag('force', abbr: 'f', help: 'Force overwrite / ignore conflicts')
      ..addFlag('uuids', help: 'Show full UUIDs in list/search commands')
      ..addFlag('recursive', abbr: 'r', help: 'Recursive operation')
      ..addFlag('preserve-timestamps',
          abbr: 'p', help: 'Preserve file modification times')
      ..addOption('target', abbr: 't', help: 'Destination path')
      ..addOption('on-conflict',
          help: 'Action if target exists (overwrite/skip/newer)',
          allowed: ['overwrite', 'skip', 'newer'],
          defaultsTo: 'skip')
      ..addMultiOption('include', help: 'Include only files matching pattern')
      ..addMultiOption('exclude', help: 'Exclude files matching pattern')
      ..addFlag('detailed', abbr: 'd', help: 'Show detailed information')
      ..addOption('depth',
          abbr: 'l', help: 'Maximum depth for tree', defaultsTo: '3')
      ..addOption('maxdepth',
          help: 'Limit find to N levels (-1 for infinite)', defaultsTo: '-1')
      ..addFlag('background',
          abbr: 'b', help: 'Run WebDAV server in background')
      ..addFlag('daemon',
          hide: true, help: 'Internal: run as daemon process') // <-- ADD THIS
      ..addOption('mount-point', abbr: 'm', help: 'WebDAV mount point path')
      ..addOption('port', help: 'WebDAV server port', defaultsTo: '8080')
      ..addFlag('webdav-debug', help: 'Enable WebDAV debug logging');

    try {
      final argResults = parser.parse(arguments);
      debugMode = argResults['verbose'];
      force = argResults['force'];
      client.debugMode = debugMode;

      final commandArgs = argResults.rest;
      if (commandArgs.isEmpty) {
        printHelp();
        return;
      }

      final command = commandArgs[0];

      switch (command) {
        case 'login':
          await handleLogin(commandArgs.sublist(1));
          break;
        case 'ls':
        case 'list':
          await handleList(argResults, commandArgs.sublist(1));
          break;
        case 'mkdir':
        case 'mkdir-path':
          if (commandArgs.length < 2) _exit('Usage: mkdir <path>');
          await handleMkdir(commandArgs[1]);
          break;
        case 'upload':
        case 'up':
          await handleUpload(argResults);
          break;
        case 'download':
        case 'dl':
          if (commandArgs.length < 2) _exit('Usage: dl <file-uuid>');
          await handleDownload(argResults);
          break;
        case 'download-path':
          await handleDownloadPath(argResults);
          break;
        case 'mv':
        case 'move':
        case 'move-path':
          if (commandArgs.length < 3) _exit('Usage: mv <source> <dest>');
          await handleMove(commandArgs[1], commandArgs[2]);
          break;
        case 'cp':
        case 'copy':
          if (commandArgs.length < 3) _exit('Usage: cp <source> <dest>');
          await handleCopy(commandArgs[1], commandArgs[2]);
          break;
        case 'rm':
        case 'trash':
        case 'trash-path':
          if (commandArgs.length < 2) _exit('Usage: rm <path>');
          await handleTrash(argResults, commandArgs[1]);
          break;
        case 'delete-path':
          if (commandArgs.length < 2) _exit('Usage: delete-path <path>');
          await handleDeletePath(argResults, commandArgs[1]);
          break;
        case 'rename':
        case 'rename-path':
          if (commandArgs.length < 3) _exit('Usage: rename <path> <new_name>');
          await handleRename(commandArgs[1], commandArgs[2]);
          break;
        case 'verify':
          await handleVerify(argResults);
          break;
        case 'list-trash':
          await handleListTrash(argResults);
          break;
        case 'restore-uuid':
          await handleRestoreUuid(argResults);
          break;
        case 'restore-path':
          await handleRestorePath(argResults);
          break;
        case 'resolve':
          if (commandArgs.length < 2) _exit('Usage: resolve <path>');
          await handleResolve(commandArgs[1]);
          break;
        case 'search':
          await handleSearch(argResults);
          break;
        case 'find':
          await handleFind(argResults);
          break;
        case 'tree':
          await handleTree(argResults);
          break;
        case 'whoami':
          await handleWhoami();
          break;
        case 'logout':
          await handleLogout();
          break;
        case 'config':
          await handleConfig();
          break;
        case 'help':
          printHelp();
          break;
        case 'mount':
        case 'webdav':
          await handleMount(argResults);
          break;
        case 'webdav-start':
          await handleWebdavStart(argResults);
          break;

        case 'webdav-stop':
          await handleWebdavStop(argResults);
          break;

        case 'webdav-status':
          await handleWebdavStatus(argResults);
          break;

        case 'webdav-test':
          await handleWebdavTest(argResults);
          break;

        case 'webdav-mount':
          await handleWebdavMount(argResults);
          break;

        case 'webdav-config':
          await handleWebdavConfig(argResults);
          break;
        default:
          _exit('Unknown command: $command');
      }
    } catch (e, stackTrace) {
      stderr.writeln('❌ Error: $e');
      if (debugMode) stderr.writeln(stackTrace);
      exit(1);
    }
  }

  void printHelp() {
    print('╔═════════════════════════════════════════════╗');
    print('║    Filen CLI - v0.0.3                       ║');
    print('╚═════════════════════════════════════════════╝');
    print('');
    print('Flags:');
    print('  -v, --verbose              Enable debug output');
    print('  -f, --force                Skip confirmations');
    print('  -b, --background           Run WebDAV in background');
    print('  --uuids                    Show full UUIDs');
    print('  -r, --recursive            Recursive operations');
    print('  -p, --preserve-timestamps  Preserve modification times');
    print('  -d, --detailed             Show detailed info');
    print('  -t, --target <path>        Destination path');
    print('  --on-conflict <mode>       skip/overwrite/newer (default: skip)');
    print('  --include <pattern>        Include file pattern');
    print('  --exclude <pattern>        Exclude file pattern');
    print('  -l, --depth <n>            Tree depth (default: 3)');
    print('  --maxdepth <n>             Find depth (-1: infinite)');
    print('  -m, --mount-point <path>   WebDAV mount point');
    print('  --port <n>                 WebDAV port (default: 8080)');
    print('  --webdav-debug             WebDAV debug logging');
    print('');
    print('File Operations:');
    print('  login                            Login to account');
    print('  whoami                           Show current user');
    print('  logout                           Logout and clear credentials');
    print('  ls [path]                        List folder contents');
    print('  mkdir <path>                     Create folder(s)');
    print('  up <sources...>                  Upload files/folders');
    print('  dl <uuid>                        Download file by UUID');
    print('  download-path <path>             Download by path');
    print('  mv <src> <dest>                  Move file/folder');
    print('  cp <src> <dest>                  Copy file/folder');
    print('  rm <path>                        Move to trash');
    print('  delete-path <path>               Permanently delete');
    print('  rename <path> <name>             Rename item');
    print('  verify <uuid|path> <local file>  Verify upload (SHA-512)');
    print('  list-trash                       Show trash contents');
    print('  restore-uuid <uuid>              Restore from trash by UUID');
    print('  restore-path <name>              Restore from trash by name');
    print('  resolve <path>                   Debug path resolution');
    print('  search <query>                   Server-side search');
    print('  find <path> <pattern>            Recursive file find');
    print('  tree [path]                      Show folder tree');
    print('  config                           Show configuration');
    print('');
    print('WebDAV Server:');
    print('  mount                      Start WebDAV (foreground)');
    print('  webdav-start               Start WebDAV server');
    print('  webdav-start -b            Start in background');
    print('  webdav-stop                Stop background server');
    print('  webdav-status              Check server status');
    print('  webdav-test                Test server connection');
    print('  webdav-mount               Show mount instructions');
    print('  webdav-config              Show server config');
    print('');
    print('Examples:');
    print('  dart filen.dart login');
    print('  dart filen.dart ls /Documents -d');
    print('  dart filen.dart up file.txt -t /Docs -p');
    print('  dart filen.dart download-path /file.txt -p');
    print('  dart filen.dart tree / -l 2');
    print('  dart filen.dart find / "*.pdf" --maxdepth 3');
    print('  dart filen.dart search "report"');
    print('');
    print('WebDAV Examples:');
    print('  dart filen.dart webdav-start -b --port 8080');
    print('  dart filen.dart webdav-status');
    print('  dart filen.dart webdav-test');
    print('  dart filen.dart webdav-mount');
    print('  dart filen.dart webdav-stop');
  }

  // ---------------------------------------------------------------------------
  // HANDLERS
  // ---------------------------------------------------------------------------

  Future<void> handleLogin(List<String> args) async {
    stdout.write('Email: ');
    final email = stdin.readLineSync()?.trim() ?? '';
    if (email.isEmpty) _exit('Email is required');

    stdout.write('Password: ');
    stdin.echoMode = false;
    final rawPassword = stdin.readLineSync() ?? '';
    stdin.echoMode = true;
    print('');

    final password = rawPassword.replaceAll(RegExp(r'[\r\n]+$'), '');
    if (password.isEmpty) _exit('Password is required');

    print('🔐 Logging in...');

    try {
      var credentials = await client.login(email, password);

      print('📂 Fetching root folder info...');
      client.setAuth(credentials);
      final rootUUID = await client.fetchBaseFolderUUID();
      credentials['baseFolderUUID'] = rootUUID;

      await config.saveCredentials(credentials);
      _printSuccess(credentials);
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('enter_2fa') || errStr.contains('wrong_2fa')) {
        print('\n🔐 Two-factor authentication required.');
        stdout.write('Enter 2FA code: ');
        final tfaCode = stdin.readLineSync()?.trim();
        if (tfaCode == null || tfaCode.isEmpty) _exit('Code required.');

        try {
          var credentials =
              await client.login(email, password, twoFactorCode: tfaCode!);

          print('📂 Fetching root folder info...');
          client.setAuth(credentials);
          final rootUUID = await client.fetchBaseFolderUUID();
          credentials['baseFolderUUID'] = rootUUID;

          await config.saveCredentials(credentials);
          _printSuccess(credentials);
        } catch (e2) {
          _exit('Login failed: ${e2.toString().replaceAll('Exception: ', '')}');
        }
      } else {
        _exit('Login failed: ${errStr.replaceAll('Exception: ', '')}');
      }
    }
  }

  void _printSuccess(Map<String, dynamic> creds) {
    print('✅ Login successful!');
    print('   User: ${creds['email']}');
    print('   Root: ${creds['baseFolderUUID']}');
    final keys = (creds['masterKeys'] ?? '').toString().split('|');
    print('   Master Keys: ${keys.length}');
  }

  Future<void> handleList(ArgResults flags, List<String> pathArgs) async {
    await _prepareClient();
    final path = pathArgs.isNotEmpty ? pathArgs.join(' ') : '/';
    final bool showFullUUIDs =
        flags['uuids'] || flags['detailed']; // Show full UUIDs if --uuids OR -d
    final bool detailed = flags['detailed'];

    final res = await client.resolvePath(path);

    if (res['type'] == 'file') {
      print('📄 File: ${p.basename(path)} (${res['uuid']})');
      return;
    }

    final uuid = res['uuid'];
    print('📂 ${res['path']} (UUID: ${uuid.substring(0, 8)}...)\n');

    final folders = await client.listFoldersAsync(uuid, detailed: detailed);
    final files = await client.listFolderFiles(uuid, detailed: detailed);
    final items = [...folders, ...files];

    if (items.isEmpty) {
      print('   (empty)');
      return;
    }

    // Build table
    const int nameWidth = 40;
    const int sizeWidth = 12;
    const int dateWidth = 10;
    final int uuidWidth = showFullUUIDs ? 36 : 11;

    String header;
    String top;
    String footer;

    if (detailed) {
      header =
          '║  Type    ${"Name".padRight(nameWidth)}  ${"Size".padLeft(sizeWidth)}  ${"Modified".padLeft(dateWidth)}  ${"UUID".padRight(uuidWidth)} ║';
      top =
          '╔${"═" * 9}${"═" * nameWidth}${"═" * (sizeWidth + 2)}${"═" * (dateWidth + 2)}${"═" * (uuidWidth + 2)}╗';
      footer =
          '╚${"═" * 9}${"═" * nameWidth}${"═" * (sizeWidth + 2)}${"═" * (dateWidth + 2)}${"═" * (uuidWidth + 2)}╝';
    } else {
      header =
          '║  Type    ${"Name".padRight(nameWidth)}  ${"Size".padLeft(sizeWidth)}  ${"UUID".padRight(uuidWidth)} ║';
      top =
          '╔${"═" * 9}${"═" * nameWidth}${"═" * (sizeWidth + 2)}${"═" * (uuidWidth + 2)}╗';
      footer =
          '╚${"═" * 9}${"═" * nameWidth}${"═" * (sizeWidth + 2)}${"═" * (uuidWidth + 2)}╝';
    }

    print(top);
    print(header);
    print(
        '╠${"═" * 9}${"═" * nameWidth}${"═" * (sizeWidth + 2)}${detailed ? "═" * (dateWidth + 2) : ""}${"═" * (uuidWidth + 2)}╣');

    int folderCount = 0;
    int fileCount = 0;

    for (var i in items) {
      final type = i['type'] == 'folder' ? '📁' : '📄';
      if (i['type'] == 'folder')
        folderCount++;
      else
        fileCount++;

      var name = i['name'] ?? 'Unknown';
      if (name.length > nameWidth)
        name = name.substring(0, nameWidth - 3) + '...';
      name = name.padRight(nameWidth);

      final size =
          (i['type'] == 'folder' ? '<DIR>' : formatSize(i['size'] ?? 0))
              .padLeft(sizeWidth);
      final uuid = i['uuid'] ?? 'N/A';
      final uuidDisplay = (showFullUUIDs ? uuid : '${uuid.substring(0, 8)}...')
          .padRight(uuidWidth);

      if (detailed) {
        final modified = i['lastModified'] ?? i['timestamp'];
        final dateDisplay = formatDate(modified).padLeft(dateWidth);
        print('║  $type  $name  $size  $dateDisplay  $uuidDisplay ║');
      } else {
        print('║  $type  $name  $size  $uuidDisplay ║');
      }
    }

    print(footer);
    print(
        '\n📊 Total: ${items.length} items ($folderCount folders, $fileCount files)');
  }

  Future<void> handleMkdir(String arg) async {
    await _prepareClient();
    print('📂 Creating "$arg"...');
    try {
      await client.createFolderRecursive(arg);
      print('✅ Folder created.');
    } catch (e) {
      _exit('Mkdir failed: $e');
    }
  }

  Future<void> handleVerify(ArgResults argResults) async {
  final args = argResults.rest.sublist(1);
  if (args.length < 2) {
    stderr.writeln('❌ Usage: dart filen.dart verify <file-uuid-or-path> <local-file>');
    stderr.writeln('   Examples:');
    stderr.writeln('     dart filen.dart verify abc123-def456-... localfile.pdf');
    stderr.writeln('     dart filen.dart verify /Documents/file.pdf localfile.pdf');
    exit(1);
  }

  try {
    final creds = await config.readCredentials();
    if (creds == null) {
      stderr.writeln('❌ Not logged in. Use "dart filen.dart login" first.');
      exit(1);
    }
    client.setAuth(creds);

    final input = args[0];
    final localPath = args[1];
    final localFile = File(localPath);
    
    if (!await localFile.exists()) {
      stderr.writeln('❌ Local file not found: $localPath');
      exit(1);
    }

    // Check if input looks like a UUID
    final isUuid = RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
      caseSensitive: false
    ).hasMatch(input);

    String fileUuid;
    String displayName;

    if (isUuid) {
      // Direct UUID verification
      fileUuid = input;
      displayName = p.basename(localPath);
      
      print('🔍 Verifying upload by UUID');
      print('   Remote UUID: $fileUuid');
      print('   Local file: $localPath');
      print('');
    } else {
      // Path-based verification - resolve first
      print('🔍 Resolving remote path: $input');
      
      final resolved = await client.resolvePath(input);
      
      if (resolved['type'] != 'file') {
        stderr.writeln('❌ Error: "$input" is not a file (it\'s a ${resolved['type']})');
        exit(1);
      }
      
      fileUuid = resolved['uuid'];
      displayName = p.basename(input);
      
      print('   ✅ Resolved to UUID: $fileUuid');
      print('   Local file: $localPath');
      print('');
    }
    
    final match = await client.verifyUploadMetadata(fileUuid, localFile);
    
    exit(match ? 0 : 1);
  } catch (e) {
    stderr.writeln('❌ Verification failed: $e');
    if (debugMode) {
      stderr.writeln(e);
    }
    exit(1);
  }
}

  Future<void> handleUpload(ArgResults argResults) async {
    final sources = argResults.rest.sublist(1);
    if (sources.isEmpty) _exit('No source files specified');

    await _prepareClient();

    String targetPath = '/';
    List<String> actualSources = sources;

    if (argResults.wasParsed('target')) {
      targetPath = argResults['target'] as String;
    } else if (sources.length > 1) {
      final lastArg = sources.last;
      if (lastArg.startsWith('/') || !lastArg.contains('*')) {
        targetPath = lastArg;
        actualSources = sources.sublist(0, sources.length - 1);
      }
    }

    final recursive = argResults['recursive'] as bool;
    final onConflict = argResults['on-conflict'] as String;
    final preserveTimestamps = argResults['preserve-timestamps'] as bool;
    final include = argResults['include'] as List<String>;
    final exclude = argResults['exclude'] as List<String>;

    final batchId = config.generateBatchId('upload', actualSources, targetPath);
    print("🔄 Batch ID: $batchId");
    print("🎯 Target: $targetPath");
    var batchState = await config.loadBatchState(batchId);

    try {
      await client.upload(
        actualSources,
        targetPath,
        recursive: recursive,
        onConflict: onConflict,
        preserveTimestamps: preserveTimestamps,
        include: include,
        exclude: exclude,
        batchId: batchId,
        initialBatchState: batchState,
        saveStateCallback: (state) => config.saveBatchState(batchId, state),
      );

      await config.deleteBatchState(batchId);
      print("✅ Upload batch completed.");
    } catch (e) {
      _exit('Upload failed: $e');
    }
  }

  Future<void> handleDownload(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: dl <file-uuid-or-path>');

    await _prepareClient();

    final input = args[0];
    final onConflict = argResults['on-conflict'] as String;

    // Check if input looks like a UUID
    final isUuid = RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
            caseSensitive: false)
        .hasMatch(input);

    if (isUuid) {
      // Original UUID-based download
      print('📥 Downloading file by UUID: $input');
      try {
        final result = await client.downloadFile(input);
        final data = result['data'] as Uint8List;
        final filename = result['filename'] as String;
        final remoteModTime = result['modificationTime'];

        final file = File(filename);

        // Check conflict
        if (await file.exists()) {
          if (onConflict == 'overwrite' || force) {
            if (force) {
              print('⚠️  File exists, overwriting (--force)');
            } else {
              print('⚠️  File exists, overwriting (--on-conflict overwrite)');
            }
          } else if (onConflict == 'skip') {
            print('⏭️  Skipping: $filename (exists, --on-conflict skip)');
            return;
          } else if (onConflict == 'newer') {
            if (remoteModTime != null) {
              final localStat = await file.stat();
              final localModTime = localStat.modified;

              DateTime remoteDateTime;
              if (remoteModTime is int) {
                remoteDateTime =
                    DateTime.fromMillisecondsSinceEpoch(remoteModTime);
              } else {
                remoteDateTime = DateTime.parse(remoteModTime.toString());
              }

              if (!remoteDateTime.isAfter(localModTime)) {
                print('⏭️  Skipping: $filename (local is newer or same)');
                return;
              }
              print('⚠️  Remote file is newer, downloading...');
            } else {
              print('⚠️  Cannot compare timestamps, skipping');
              return;
            }
          } else {
            // No flag set - prompt user
            stdout.write('⚠️  File "$filename" exists. Overwrite? [y/N]: ');
            final response = stdin.readLineSync()?.toLowerCase().trim();
            if (response != 'y' && response != 'yes') {
              print('❌ Download cancelled');
              return;
            }
          }
        }

        await file.writeAsBytes(data);

        print('✅ Downloaded: $filename (${formatSize(data.length)})');
      } catch (e) {
        _exit('Download failed: $e');
      }
    } else {
      // Path-based download - resolve first
      print('🔍 Resolving path: $input');

      try {
        final resolved = await client.resolvePath(input);

        if (resolved['type'] != 'file') {
          _exit("'$input' is not a file. Use 'download-path -r' for folders.");
        }

        final fileUuid = resolved['uuid'];
        final filename = p.basename(input);
        final localFile = File(filename);
        final metadata = resolved['metadata'];
        final remoteModTime =
            metadata?['lastModified'] ?? metadata?['timestamp'];

        // Check conflict
        if (await localFile.exists()) {
          if (onConflict == 'overwrite' || force) {
            if (force) {
              print('⚠️  File exists, overwriting (--force)');
            } else {
              print('⚠️  File exists, overwriting (--on-conflict overwrite)');
            }
          } else if (onConflict == 'skip') {
            print('⏭️  Skipping: $filename (exists, --on-conflict skip)');
            return;
          } else if (onConflict == 'newer') {
            if (remoteModTime != null) {
              final localStat = await localFile.stat();
              final localModTime = localStat.modified;

              DateTime remoteDateTime;
              if (remoteModTime is int) {
                remoteDateTime =
                    DateTime.fromMillisecondsSinceEpoch(remoteModTime);
              } else {
                remoteDateTime = DateTime.parse(remoteModTime.toString());
              }

              if (!remoteDateTime.isAfter(localModTime)) {
                print('⏭️  Skipping: $filename (local is newer or same)');
                return;
              }
              print('⚠️  Remote file is newer, downloading...');
            } else {
              print('⚠️  Cannot compare timestamps, skipping');
              return;
            }
          } else {
            // No flag set - prompt user
            stdout.write('⚠️  File "$filename" exists. Overwrite? [y/N]: ');
            final response = stdin.readLineSync()?.toLowerCase().trim();
            if (response != 'y' && response != 'yes') {
              print('❌ Download cancelled');
              return;
            }
          }
        }

        print('📥 Downloading: $filename');

        final result = await client.downloadFile(fileUuid, savePath: filename);

        print(
            '✅ Downloaded: $filename (${formatSize(localFile.lengthSync())})');
      } catch (e) {
        _exit('Download failed: $e');
      }
    }
  }

  Future<void> handleDownloadPath(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: download-path <path>');

    await _prepareClient();

    final remotePath = args[0];
    final localDestination = argResults['target'] as String?;
    final recursive = argResults['recursive'] as bool;
    final onConflict = argResults['on-conflict'] as String;
    final preserveTimestamps = argResults['preserve-timestamps'] as bool;
    final include = argResults['include'] as List<String>;
    final exclude = argResults['exclude'] as List<String>;

    final batchId = config.generateBatchId(
        'download', [remotePath], localDestination ?? '.');
    print("🔄 Batch ID: $batchId");
    var batchState = await config.loadBatchState(batchId);

    try {
      await client.downloadPath(
        remotePath,
        localDestination: localDestination,
        recursive: recursive,
        onConflict: onConflict,
        preserveTimestamps: preserveTimestamps,
        include: include,
        exclude: exclude,
        batchId: batchId,
        initialBatchState: batchState,
        saveStateCallback: (state) => config.saveBatchState(batchId, state),
      );

      await config.deleteBatchState(batchId);
      print("✅ Download batch completed.");
    } catch (e) {
      _exit('Download failed: $e');
    }
  }

  Future<void> handleMove(String srcPath, String destPath) async {
    await _prepareClient();

    final src = await client.resolvePath(srcPath);

    Map<String, dynamic>? destParent;
    String? destName;
    bool isRename = false;

    try {
      final destObj = await client.resolvePath(destPath);
      if (destObj['type'] == 'folder') {
        destParent = destObj;
        destName = p.basename(srcPath);
      } else {
        _exit('Destination exists as a file.');
      }
    } catch (_) {
      final parentDir = p.dirname(destPath);
      destName = p.basename(destPath);

      try {
        destParent =
            await client.resolvePath(parentDir == '.' ? '/' : parentDir);
        if (destParent!['type'] != 'folder') throw Exception('Parent not dir');
      } catch (e) {
        _exit('Destination parent not found.');
      }
      isRename = true;
    }

    if (destParent == null) {
      _exit('Could not resolve destination.');
      return;
    }

    print(
        '🚚 Moving "${src['path']}" to "${destParent!['path']}/$destName"...');

    if (src['parent'] != destParent!['uuid']) {
      await client.moveItem(src['uuid'], destParent!['uuid'], src['type']);
    }

    final currentName = p.basename(src['path']!);
    if (isRename && destName != currentName && destName != null) {
      await client.renameItem(src['uuid'], destName, src['type']);
    }

    print('✅ Done.');
  }

  Future<void> handleCopy(String srcPath, String destPath) async {
    await _prepareClient();

    final src = await client.resolvePath(srcPath);
    if (src['type'] == 'folder') _exit('Folder copy not yet supported.');

    Map<String, dynamic>? destFolder;
    String targetName;

    try {
      final destObj = await client.resolvePath(destPath);
      if (destObj['type'] == 'folder') {
        destFolder = destObj;
        targetName = p.basename(srcPath);
      } else {
        if (!force) _exit('Destination exists. Use -f to overwrite.');
        final parentPath = p.dirname(destPath);
        destFolder =
            await client.resolvePath(parentPath == '.' ? '/' : parentPath);
        targetName = p.basename(destPath);
      }
    } catch (_) {
      final parentPath = p.dirname(destPath);
      try {
        destFolder =
            await client.resolvePath(parentPath == '.' ? '/' : parentPath);
      } catch (e) {
        _exit('Destination parent not found.');
      }
      targetName = p.basename(destPath);
    }

    if (destFolder == null) {
      _exit('Invalid destination.');
      return;
    }

    print(
        '📋 Copying "${src['path']}" to "${destFolder!['path']}/$targetName"...');

    final tempDir = Directory.systemTemp.createTempSync('filen_cli_cp_');
    final tempFile = File(p.join(tempDir.path, targetName));

    try {
      stdout.write('   1/2 Downloading...  \r');
      await client.downloadFile(src['uuid'], savePath: tempFile.path);

      stdout.write('   2/2 Uploading...    \r');
      await client.uploadFile(tempFile, destFolder!['uuid']);

      print('\n✅ Copy complete.');
    } catch (e) {
      print('');
      _exit('Copy failed: $e');
    } finally {
      if (tempFile.existsSync()) tempFile.deleteSync();
      if (tempDir.existsSync()) tempDir.deleteSync();
    }
  }

  Future<void> handleRename(String path, String newName) async {
    await _prepareClient();
    final src = await client.resolvePath(path);

    print('✏️ Renaming "${src['path']}" to "$newName"...');
    try {
      await client.renameItem(src['uuid'], newName, src['type']);
      print('✅ Renamed.');
    } catch (e) {
      _exit('Rename failed: $e');
    }
  }

  Future<void> handleTrash(ArgResults argResults, String path) async {
    await _prepareClient();
    final src = await client.resolvePath(path);
    final forceFlag = argResults['force'] as bool;

    if (!forceFlag) {
      final prompt = '❓ Move ${src['type']} "$path" to trash?';
      if (!_confirmAction(prompt)) {
        print("❌ Cancelled");
        return;
      }
    }

    print('🗑️ Moving "${src['path']}" to trash...');
    try {
      await client.trashItem(src['uuid'], src['type']);
      print('✅ Trashed.');
    } catch (e) {
      _exit('Trash failed: $e');
    }
  }

  Future<void> handleDeletePath(ArgResults argResults, String path) async {
    await _prepareClient();
    final src = await client.resolvePath(path);
    final forceFlag = argResults['force'] as bool;

    print('⚠️ WARNING: This will PERMANENTLY delete the item!');
    if (!forceFlag) {
      final prompt = '❓ Permanently delete ${src['type']} "$path"?';
      if (!_confirmAction(prompt)) {
        print("❌ Cancelled");
        return;
      }
    }

    print('🗑️ Deleting "${src['path']}"...');
    try {
      await client.deletePermanently(src['uuid'], src['type']);
      print('✅ Permanently deleted.');
    } catch (e) {
      _exit('Delete failed: $e');
    }
  }

  Future<void> handleListTrash(ArgResults argResults) async {
    await _prepareClient();
    final bool showFullUUIDs = argResults['uuids'];

    print('🗑️ Listing trash contents...\n');

    final trashItems = await client.getTrashContent();

    if (trashItems.isEmpty) {
      print('📭 Trash is empty');
      return;
    }

    // Table display
    const int nameWidth = 40;
    const int sizeWidth = 12;
    final int uuidWidth = showFullUUIDs ? 36 : 11;

    final top =
        '╔${"═" * 9}${"═" * nameWidth}${"═" * (sizeWidth + 2)}${"═" * (uuidWidth + 2)}╗';
    final header =
        '║  Type    ${"Name".padRight(nameWidth)}  ${"Size".padLeft(sizeWidth)}  ${"UUID".padRight(uuidWidth)} ║';
    final footer =
        '╚${"═" * 9}${"═" * nameWidth}${"═" * (sizeWidth + 2)}${"═" * (uuidWidth + 2)}╝';

    print(top);
    print(header);
    print(
        '╠${"═" * 9}${"═" * nameWidth}${"═" * (sizeWidth + 2)}${"═" * (uuidWidth + 2)}╣');

    int folderCount = 0;
    int fileCount = 0;

    for (var item in trashItems) {
      final type = item['type'] == 'folder' ? '📁' : '📄';
      if (item['type'] == 'folder')
        folderCount++;
      else
        fileCount++;

      var name = item['name'] ?? 'Unknown';
      if (name.length > nameWidth)
        name = name.substring(0, nameWidth - 3) + '...';
      name = name.padRight(nameWidth);

      final size =
          (item['type'] == 'folder' ? '<DIR>' : formatSize(item['size'] ?? 0))
              .padLeft(sizeWidth);
      final uuid = item['uuid'] ?? 'N/A';
      final uuidDisplay = (showFullUUIDs ? uuid : '${uuid.substring(0, 8)}...')
          .padRight(uuidWidth);

      print('║  $type  $name  $size  $uuidDisplay ║');
    }

    print(footer);
    print(
        '\n📊 Total: ${trashItems.length} items ($folderCount folders, $fileCount files)');
  }

  Future<void> handleRestoreUuid(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: restore-uuid <uuid>');

    await _prepareClient();

    final itemUuid = args[0];
    final forceFlag = argResults['force'] as bool;

    // Note: The API restores to the ORIGINAL parent.
    // We cannot easily specify a new target (-t) during the restore call.

    if (!forceFlag) {
      final prompt = '❓ Restore item "$itemUuid" to original location?';
      if (!_confirmAction(prompt)) {
        print("❌ Cancelled");
        return;
      }
    }

    print("🚀 Restoring item...");
    try {
      // Try restoring as file first
      try {
        await client.restoreItem(itemUuid, 'file');
        print("✅ Restored (file).");
      } catch (_) {
        // If failed, try as folder
        await client.restoreItem(itemUuid, 'folder');
        print("✅ Restored (folder).");
      }
    } catch (e) {
      _exit("Failed to restore: $e");
    }
  }

  Future<void> handleRestorePath(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: restore-path <name>');

    await _prepareClient();

    final itemName = args[0];
    final forceFlag = argResults['force'] as bool;

    print("🔍 Finding '$itemName' in trash...");
    // This now uses the working getTrashContent()
    final trashItems = await client.getTrashContent();

    final matches = trashItems.where((i) => i['name'] == itemName).toList();

    if (matches.isEmpty) _exit("Item '$itemName' not found in trash.");
    if (matches.length > 1) {
      stderr.writeln("❌ Multiple items named '$itemName' found in trash.");
      stderr.writeln("   Use 'restore-uuid' with one of these UUIDs:");
      for (var m in matches) {
        stderr.writeln(
            "   - ${m['type']} ${m['uuid']} (Size: ${formatSize(m['size'])})");
      }
      exit(1);
    }

    final item = matches.first;
    final itemUuid = item['uuid'] as String;
    final itemType = item['type'] as String;

    if (!forceFlag) {
      final prompt = '❓ Restore $itemType "$itemName" to original location?';
      if (!_confirmAction(prompt)) {
        print("❌ Cancelled");
        return;
      }
    }

    print("🚀 Restoring item...");
    try {
      await client.restoreItem(itemUuid, itemType);
      print("✅ Restored.");
    } catch (e) {
      _exit("Restore failed: $e");
    }
  }

  Future<void> handleResolve(String path) async {
    await _prepareClient();
    print("🔍 Resolving path: $path");

    final resolved = await client.resolvePath(path);

    print("\n✅ Path resolved!");
    print("=" * 40);
    print("  Type: ${resolved['type']?.toString().toUpperCase()}");
    print("  UUID: ${resolved['uuid']}");
    print("  Path: ${resolved['path']}");
    if (resolved['metadata'] != null) {
      print("\n  Metadata:");
      (resolved['metadata'] as Map).forEach((k, v) {
        print("    $k: $v");
      });
    }
    print("=" * 40);
  }

  Future<void> handleSearch(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: search <query>');

    await _prepareClient();
    final query = args[0];
    final detailed = argResults['uuids'];

    print("🔍 Searching for '$query'...");

    final results = await client.search(query, detailed: detailed);
    final folders = results['folders']!;
    final files = results['files']!;

    if (folders.isEmpty && files.isEmpty) {
      print("\n📭 No results found.");
      return;
    }

    print("\n" + "=" * 60);
    if (folders.isNotEmpty) {
      print("📂 Folders (${folders.length}):");
      for (var f in folders) {
        final displayName = f['fullPath'] ?? f['name'];
        print("  📁 $displayName (${f['uuid'].substring(0, 8)}...)");
      }
    }

    if (files.isNotEmpty) {
      print("\n📄 Files (${files.length}):");
      for (var f in files) {
        final displayName = f['fullPath'] ?? f['name'];
        print("  📄 $displayName (${f['uuid'].substring(0, 8)}...)");
      }
    }
    print("=" * 60);
  }

  Future<void> handleFind(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.length < 2) _exit('Usage: find <path> <pattern>');

    await _prepareClient();

    final path = args[0];
    final pattern = args[1];
    final maxDepth = int.tryParse(argResults['maxdepth'] ?? '-1') ?? -1;

    print("🔍 Finding files matching '$pattern' in '$path'...");
    if (maxDepth != -1) print("   (Limiting to $maxDepth levels deep)");

    final results = await client.findFiles(path, pattern, maxDepth: maxDepth);

    if (results.isEmpty) {
      print("\n📭 No results found.");
      return;
    }

    print("\n" + "=" * 60);
    print("📄 Found Files (${results.length}):");
    for (var file in results) {
      final size = formatSize(file['size'] ?? 0);
      print("  ${file['fullPath']}  ($size)");
    }
    print("=" * 60);
  }

  Future<void> handleTree(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    final path = args.isNotEmpty ? args[0] : '/';
    final maxDepth = int.tryParse(argResults['depth'] ?? '3') ?? 3;

    await _prepareClient();

    print("\n🌳 Folder tree: $path");
    print("=" * 60);
    print(path == '/' ? '📁 /' : '📁 ${p.basename(path)}');

    await client.printTree(
      path,
      (line) => print(line),
      maxDepth: maxDepth,
    );

    print("\n(Showing max $maxDepth levels deep)");
  }

  Future<void> handleWhoami() async {
    final creds = await _requireAuth();
    print('📧 Email: ${creds['email']}');
    print('🆔 User ID: ${creds['userId']}');
    print('📁 Root: ${creds['baseFolderUUID']}');
    final keys = (creds['masterKeys'] ?? '').toString().split('|');
    print('🔑 Master Keys: ${keys.length}');
  }

  Future<void> handleLogout() async {
    await config.clearCredentials();
    print('✅ Logged out');
  }

  Future<void> handleConfig() async {
    print('╔════════════════════════════════════════╗');
    print('║         Configuration                  ║');
    print('╚════════════════════════════════════════╝');
    print('📁 Config dir: ${config.configDir}');
    print('🔐 Credentials: ${config.credentialsFile}');
    print('🔄 Batch states: ${config.batchStateDir}');
    print('');
    print('🌐 API Endpoints:');
    print('   Gateway: ${FilenClient.apiUrl}');
    print('   Ingest: https://ingest.filen.io');
    print('   Egest: https://egest.filen.io');
  }

  // WebDAV Daemon Methods

  Future<void> handleWebdavStart(ArgResults argResults) async {
    final bool background = argResults['background'] ?? false;
    final bool isDaemon = argResults['daemon'] ?? false;
    final int port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;

    // If running as daemon (spawned by background start), just run the server
    if (isDaemon) {
      await handleMount(argResults);
      return;
    }

    // Check for existing instance
    final existingPid = await config.readWebdavPid();
    if (existingPid != null) {
      // Check if process is actually running
      final isRunning = await _isProcessRunning(existingPid);

      if (isRunning) {
        stderr
            .writeln('❌ WebDAV server is already running (PID: $existingPid).');
        stderr
            .writeln('💡 Run "dart filen.dart webdav-stop" to stop it first.');
        exit(1);
      } else {
        // Stale PID file, clear it
        await config.clearWebdavPid();
      }
    }

    if (background) {
      print('🚀 Starting WebDAV server in background...');
      try {
        // Start the daemon process
        final process = await Process.start(
          Platform.executable,
          [
            Platform.script.toFilePath(),
            'webdav-start',
            '--daemon',
            '--port=$port',
          ],
          mode: ProcessStartMode.detached,
        );

        // Give it time to start up
        await Future.delayed(Duration(milliseconds: 1000));

        // Verify it's running
        final isRunning = await _isProcessRunning(process.pid);

        if (!isRunning) {
          stderr.writeln('❌ Failed to start background process');
          await config.clearWebdavPid();
          exit(1);
        }

        await config.saveWebdavPid(process.pid);

        print('✅ WebDAV server started in background (PID: ${process.pid})');
        print('   URL: http://localhost:$port/');
        print('   User: filen');
        print('   Pass: filen-webdav');
        print('\n💡 Use "dart filen.dart webdav-test" to verify connection');
        print('💡 Use "dart filen.dart webdav-status" to check status');
        print('💡 Use "dart filen.dart webdav-stop" to stop');
        exit(0);
      } catch (e) {
        stderr.writeln('❌ Failed to start background process: $e');
        await config.clearWebdavPid();
        exit(1);
      }
    }

    // Foreground mode
    print('🚀 Starting WebDAV server in foreground...');
    print('   (Press Ctrl+C to stop)');
    await handleMount(argResults);
  }

  Future<void> handleWebdavStop(ArgResults argResults) async {
    print('🛑 Stopping WebDAV server...');
    final pid = await config.readWebdavPid();

    if (pid == null) {
      print('❌ Server does not appear to be running (no PID file).');
      await config.clearWebdavPid();
      exit(1);
    }

    try {
      // First check if process exists
      final exists = await _isProcessRunning(pid);

      if (!exists) {
        print('⚠️  Process (PID: $pid) is not running. Cleaning up PID file.');
        await config.clearWebdavPid();
        exit(0);
      }

      // Try graceful shutdown with SIGTERM
      final success = Process.killPid(pid, ProcessSignal.sigterm);

      if (success) {
        // Wait a moment for graceful shutdown
        await Future.delayed(Duration(milliseconds: 500));

        // Check if it's still running
        final stillRunning = await _isProcessRunning(pid);

        if (stillRunning) {
          // Force kill if still running
          print('⚠️  Forcing termination...');
          Process.killPid(pid, ProcessSignal.sigkill);
          await Future.delayed(Duration(milliseconds: 200));
        }

        print('✅ Server process (PID: $pid) terminated.');
      } else {
        print(
            '⚠️  Could not terminate process (PID: $pid). It may already be stopped.');
      }
    } catch (e) {
      print('⚠️  Error terminating process: $e');
    }

    await config.clearWebdavPid();
  }

  Future<bool> _isProcessRunning(int pid) async {
    try {
      if (Platform.isWindows) {
        // Windows: use tasklist
        final result = await Process.run('tasklist', ['/FI', 'PID eq $pid']);
        return result.stdout.toString().contains(pid.toString());
      } else {
        // Unix-like: use ps
        final result = await Process.run('ps', ['-p', pid.toString()]);
        return result.exitCode == 0;
      }
    } catch (e) {
      return false;
    }
  }

  Future<void> handleWebdavStatus(ArgResults argResults) async {
    final pid = await config.readWebdavPid();
    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;

    if (pid == null) {
      print('❌ WebDAV server is not running (no PID file).');
      print('💡 Start with: dart filen.dart webdav-start --background');
      exit(1);
    }

    // Check if process actually exists
    final isRunning = await _isProcessRunning(pid);

    if (!isRunning) {
      print('❌ WebDAV server PID file exists but process is not running.');
      print('   Stale PID: $pid');
      print('💡 Run "dart filen.dart webdav-stop" to clean up.');
      exit(1);
    }

    print('✅ WebDAV server is running in background.');
    print('   PID: $pid');
    print('   URL: http://localhost:$port/');
    print('   User: filen');
    print('   Pass: filen-webdav');
    print('\n💡 Use "dart filen.dart webdav-test" to verify connection.');
    print('💡 Use "dart filen.dart webdav-stop" to stop it.');
  }

  Future<void> handleWebdavMount(ArgResults argResults) async {
    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;
    final url = 'http://localhost:$port/';

    print('🗂️  Mount Instructions for Filen Drive');
    print('=' * 50);
    print('Server URL: $url');
    print('Username:   filen');
    print('Password:   filen-webdav');

    print('\n--- macOS ---');
    print('1. Open Finder');
    print('2. Press Cmd+K (Go > Connect to Server)');
    print('3. Enter: $url');
    print('4. Connect, then enter username and password.');

    print('\n--- Windows ---');
    print('1. Open File Explorer');
    print('2. Right-click "This PC" > "Map network drive..."');
    print('3. Enter: $url');
    print('4. Check "Connect using different credentials"');
    print('5. Connect, then enter username and password.');

    print('\n--- Linux (davfs2) ---');
    print('sudo apt install davfs2');
    print('sudo mkdir -p /mnt/filen');
    print('sudo mount -t davfs $url /mnt/filen');
    print('(You will be prompted for username and password)');
  }

  Future<void> handleWebdavTest(ArgResults argResults) async {
    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;
    final url = Uri.parse('http://localhost:$port/');

    print('🧪 Testing WebDAV server connection at $url ...');

    final propfindBody = '''
    <?xml version="1.0" encoding="utf-8"?>
    <D:propfind xmlns:D="DAV:">
        <D:prop>
            <D:resourcetype/>
        </D:prop>
    </D:propfind>
    ''';

    final basicAuth =
        'Basic ${base64Encode(utf8.encode('filen:filen-webdav'))}';

    try {
      final request = http.Request('PROPFIND', url)
        ..headers['Authorization'] = basicAuth
        ..headers['Depth'] = '0'
        ..headers['Content-Type'] = 'application/xml'
        ..body = propfindBody;

      final response =
          await http.Client().send(request).timeout(Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 207 && responseBody.contains('<?xml')) {
        print('✅ Connection successful! (Received 207 Multi-Status)');
        print('   Server is running and authentication is working.');
      } else {
        print('❌ Connection failed.');
        print('   Server returned status: ${response.statusCode}');
        print(
            '   Response: ${responseBody.substring(0, min(100, responseBody.length))}...');
      }
    } catch (e) {
      if (e is SocketException) {
        print(
            '❌ Connection failed: Server is not running or unreachable at $url');
      } else if (e is TimeoutException) {
        print('❌ Connection timed out. Is the server running?');
      } else {
        print('❌ Connection test failed: $e');
      }
    }
  }

  Future<void> handleWebdavConfig(ArgResults argResults) async {
    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;

    print('⚙️  WebDAV Server Configuration');
    print('=' * 40);
    print('   Host: localhost');
    print('   Port: $port');
    print('   User: filen');
    print('   Pass: filen-webdav');
    print('   Protocol: http (SSL not implemented in this version)');
    print('   Background PID File: ${config.webdavPidFile}');
  }

  Future<void> handleMount(ArgResults argResults) async {
    await _prepareClient();

    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;
    final mountPoint = argResults['mount-point'] as String?;
    final webdavDebug = argResults['webdav-debug'] as bool;

    print('╔═══════════════════════════════════════════════╗');
    print('║    Filen WebDAV Server                        ║');
    print('╚═══════════════════════════════════════════════╝');
    print('');
    print('🔐 User: ${client.email}');
    print('🌐 Starting WebDAV server on port $port...');
    print('');

    try {
      // Create the virtual filesystem
      final filenFS = FilenFileSystem(client: client);

      // Create WebDAV config
      final davConfig = DAVConfig(
        root: filenFS.directory('/'),
        prefix: '/',
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          realm: 'Filen WebDAV',
          users: {'filen': 'filen-webdav'},
        ),
        authorizationProvider: RoleBasedAuthorizationProvider(
          readWriteUsers: {'filen'},
          allowAnonymousRead: false,
        ),
        enableLocking: true,
      );

      // Create ShelfDAV instance
      final dav = ShelfDAV.withConfig(davConfig);

      // --- FIX: ADD CORS MIDDLEWARE ---
      final handler = const Pipeline()
          .addMiddleware((innerHandler) {
            return (request) async {
              // Handle Pre-flight OPTIONS request
              if (request.method == 'OPTIONS') {
                return Response.ok('', headers: {
                  'Access-Control-Allow-Origin': '*',
                  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL, COPY, MOVE, LOCK, UNLOCK, OPTIONS',
                  'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization, Depth, Destination, If-None-Match, If-Match, If-Modified-Since',
                  'Access-Control-Expose-Headers': 'DAV, ETag, Link',
                  'Access-Control-Max-Age': '86400',
                });
              }
              
              // Forward request
              final response = await innerHandler(request);
              
              // Add CORS headers to actual response
              return response.change(headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Expose-Headers': 'DAV, ETag, Link',
                'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL, COPY, MOVE, LOCK, UNLOCK, OPTIONS',
                 // Important: Add any other headers your client sends
                'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization, Depth, Destination, If-None-Match, If-Match, If-Modified-Since',
              });
            };
          })
          .addHandler(dav.handler);
      // --------------------------------

      // Start the shelf server
      final server = await shelf_io.serve(
        handler, // Use the new handler with CORS
        '0.0.0.0',
        port,
      );

      print('✅ WebDAV server started successfully!');
      print('');
      print('📡 Server URL: http://localhost:$port/');
      print('📡 Network URL: http://${await _getLocalIpAddress()}:$port/');
      print('');
      print('🔐 Authentication:');
      print('   Username: filen');
      print('   Password: filen-webdav');
      print('');
      print('📂 Mount instructions:');
      print('');
      print('   Linux (davfs2):');
      print('   ─────────────────────────────────────────────');
      print(
          '   sudo mount -t davfs http://localhost:$port ${mountPoint ?? '/mnt/filen'}');
      print('');
      print('   macOS (Finder):');
      print('   ─────────────────────────────────────────────');
      print('   1. Open Finder');
      print('   2. Press Cmd+K');
      print('   3. Enter: http://localhost:$port');
      print('   4. Username: filen, Password: filen-webdav');
      print('');
      print('   Windows:');
      print('   ─────────────────────────────────────────────');
      print('   net use Z: http://localhost:$port /user:filen filen-webdav');
      print('');
      print('🛑 Press Ctrl+C to stop the server');
      print('');

      // Handle shutdown signals
      ProcessSignal.sigint.watch().listen((_) async {
        print('\n🛑 Shutting down WebDAV server...');
        await server.close(force: true);
        await config.clearWebdavPid();
        print('✅ Server stopped gracefully.');
        exit(0);
      });

      ProcessSignal.sigterm.watch().listen((_) async {
        print('\n🛑 Shutting down WebDAV server...');
        await server.close(force: true);
        await config.clearWebdavPid();
        print('✅ Server stopped gracefully.');
        exit(0);
      });
    } catch (e, stackTrace) {
      stderr.writeln('❌ Failed to start WebDAV server: $e');
      if (debugMode || webdavDebug) {
        stderr.writeln(stackTrace);
      }
      await config.clearWebdavPid();
      exit(1);
    }
  }

  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return 'localhost';
  }

  Future<void> _prepareClient() async {
    final c = await config.readCredentials();
    if (c == null) _exit('Not logged in');
    client.setAuth(c!);
    if (client.baseFolderUUID.isEmpty) {
      try {
        client.baseFolderUUID = await client.fetchBaseFolderUUID();
        c['baseFolderUUID'] = client.baseFolderUUID;
        await config.saveCredentials(c);
      } catch (_) {
        _exit('Could not fetch root UUID');
      }
    }
  }

  Future<Map<String, dynamic>> _requireAuth() async {
    final creds = await config.readCredentials();
    if (creds == null) _exit('Not logged in. Run "login" first.');
    return creds!;
  }

  bool _confirmAction(String prompt) {
    stdout.write('$prompt [y/N]: ');
    final response = stdin.readLineSync()?.toLowerCase().trim();
    return response == 'y' || response == 'yes';
  }

  void _exit(String m) {
    stderr.writeln('❌ $m');
    exit(1);
  }
}

/// Exception for chunk upload failures
class ChunkUploadException implements Exception {
  final String message;
  final String fileUuid; // Store file UUID
  final String uploadKey;
  final int lastSuccessfulChunk;
  final Object? originalError;

  ChunkUploadException(
    this.message, {
    required this.fileUuid, // Required parameter
    required this.uploadKey,
    required this.lastSuccessfulChunk,
    this.originalError,
  });

  @override
  String toString() => 'ChunkUploadException: $message '
      '(uuid: $fileUuid, uploadKey: $uploadKey, lastChunk: $lastSuccessfulChunk)';
}

// ============================================================================
// API CLIENT (Enhanced)
// ============================================================================

class FilenClient {
  static const apiUrl = 'https://gateway.filen.io';
  final ConfigService config;
  bool debugMode = false;
  String? apiKey = '';
  String baseFolderUUID = '';
  List<String>? masterKeys = [];
  String? email = '';
  
  // Cache path strings to UUIDs/Metadata to speed up batch ops
  final Map<String, Map<String, dynamic>> _pathCache = {}; // Cache for path -> info

  // Caching
  static const Duration _cacheDuration = Duration(minutes: 10);
  final Map<String, _CacheEntry> _folderCache = {};
  final Map<String, _CacheEntry> _fileCache = {};

  // Token refresh lock
  bool _isRefreshingToken = false;

  FilenClient({required this.config});

  // Centralized request method with retry logic
  Future<http.Response> _makeRequest(
    String method,
    Uri url, {
    Map<String, String>? headers,
    dynamic body,
    bool useAuth = true,
    bool isAuthRetry = false,
    int maxRetries = 3,
    int retryCount = 0,
  }) async {
    final requestHeaders = headers ?? {'Content-Type': 'application/json'};
    if (useAuth && apiKey != null && apiKey!.isNotEmpty) {
      requestHeaders['Authorization'] = 'Bearer $apiKey';
    }

    http.Response response;
    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(url, headers: requestHeaders);
          break;
        case 'POST':
          response = await http.post(url, headers: requestHeaders, body: body);
          break;
        case 'PUT':
          response = await http.put(url, headers: requestHeaders, body: body);
          break;
        case 'PATCH':
          response = await http.patch(url, headers: requestHeaders, body: body);
          break;
        case 'DELETE':
          final request = http.Request('DELETE', url)
            ..headers.addAll(requestHeaders)
            ..body = body ?? '';
          final streamedResponse = await request.send();
          response = await http.Response.fromStream(streamedResponse);
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }
    } catch (e) {
      _log('Network error: $e');
      if (retryCount < maxRetries) {
        final delay = Duration(seconds: 1 << retryCount);
        _log(
            'Retrying in ${delay.inSeconds}s... (${retryCount + 1}/$maxRetries)');
        await Future.delayed(delay);
        return _makeRequest(
          method,
          url,
          headers: headers,
          body: body,
          useAuth: useAuth,
          isAuthRetry: isAuthRetry,
          maxRetries: maxRetries,
          retryCount: retryCount + 1,
        );
      }
      throw Exception('Network request failed after $maxRetries attempts: $e');
    }

    // Handle 5xx errors with retry
    if (response.statusCode >= 500 && response.statusCode < 600) {
      if (retryCount < maxRetries) {
        final delay = Duration(seconds: 1 << retryCount);
        _log(
            'Server error ${response.statusCode}. Retrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
        return _makeRequest(
          method,
          url,
          headers: headers,
          body: body,
          useAuth: useAuth,
          isAuthRetry: isAuthRetry,
          maxRetries: maxRetries,
          retryCount: retryCount + 1,
        );
      }
    }

    // Handle 401 (for future token refresh support)
    if (response.statusCode == 401 && useAuth && !isAuthRetry) {
      _log('Auth error (401). API key may be invalid.');
      // Filen doesn't have refresh tokens, but structure is here for consistency
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log('API Error ${response.statusCode}: ${response.body}');
      throw Exception('API Error: ${response.statusCode} - ${response.body}');
    }

    return response;
  }

  /// Hash a file using SHA-512
  Future<String> hashFile(File file) async {
    final digestSink = DigestSink();
    final byteSink = crypto.sha512.startChunkedConversion(digestSink);

    final raf = await file.open();
    const chunkSize = 1048576; // 1MB chunks

    try {
      while (true) {
        final bytes = await raf.read(chunkSize);
        if (bytes.isEmpty) break;
        byteSink.add(bytes);
      }

      byteSink.close();
      return HEX.encode(digestSink.value?.bytes ?? []).toLowerCase();
    } finally {
      await raf.close();
    }
  }

  /// Verify uploaded file using metadata hash (no download needed)
  Future<bool> verifyUploadMetadata(String fileUuid, File originalFile) async {
    _log('Verifying upload using metadata check...');

    // Hash the original file
    print('   📊 Hashing local file...');
    final localHash = await hashFile(originalFile);
    _log('   Local SHA-512: $localHash');

    // Get file metadata from server
    print('   📋 Fetching metadata from server...');
    final metadata = await getFileMetadata(fileUuid);
    final metaStr = await _tryDecrypt(metadata['metadata']);
    final meta = json.decode(metaStr);

    final serverHash = meta['hash'] as String?;

    if (serverHash == null || serverHash.isEmpty) {
      print('   ⚠️  No hash in metadata (empty file?)');
      return await originalFile.length() == 0;
    }

    _log('   Server SHA-512: $serverHash');

    final match = localHash == serverHash;

    if (match) {
      print('   ✅ Verification successful - hashes match!');
    } else {
      print('   ❌ Verification failed - hashes differ!');
      print('      Local:  $localHash');
      print('      Server: $serverHash');
    }

    return match;
  }

  Future<Map<String, String>> uploadFileChunked(
    File file,
    String parent, {
    String? fileUuid,
    String? creationTime,
    String? modificationTime,
    String? resumeUploadKey,
    int resumeFromChunk = 0,
    Function(int current, int total, int bytesUploaded, int totalBytes)?
        onProgress,
    Function(String uuid, String uploadKey)? onUploadStart,
  }) async {
    final name = p.basename(file.path);
    final size = await file.length();
    final uuid = fileUuid ?? _uuid();
    final mk = masterKeys?.last ?? '';
    if (mk.isEmpty) {
      throw Exception('No master keys available');
    }

    final fileKeyStr = _randomString(32);
    final fileKeyBytes = Uint8List.fromList(utf8.encode(fileKeyStr));

    // Get modification time
    var lastMod = modificationTime;
    if (lastMod == null && creationTime == null) {
      try {
        final stat = await file.stat();
        lastMod = stat.modified.millisecondsSinceEpoch.toString();
      } catch (_) {}
    }

    // Handle empty files
    if (size == 0) {
      _log('Uploading empty file via /v3/upload/empty');

      final metaJson = json.encode({
        'name': name,
        'size': size,
        'mime': 'application/octet-stream',
        'key': fileKeyStr,
        'hash': '',
        'lastModified': lastMod != null
            ? int.tryParse(lastMod) ?? DateTime.now().millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch,
      });

      final nameEncrypted = await _encryptMetadata002(name, fileKeyStr);
      final sizeEncrypted =
          await _encryptMetadata002(size.toString(), fileKeyStr);
      final mimeEncrypted =
          await _encryptMetadata002('application/octet-stream', fileKeyStr);
      final metadataEncrypted = await _encryptMetadata002(metaJson, mk);
      final nameHashed = await _hashFileName(name);

      await _post('/v3/upload/empty', {
        'uuid': uuid,
        'name': nameEncrypted,
        'nameHashed': nameHashed,
        'size': sizeEncrypted,
        'parent': parent,
        'mime': mimeEncrypted,
        'metadata': metadataEncrypted,
        'version': 2,
      });

      _invalidateCache(parent);

      if (onProgress != null) {
        onProgress(1, 1, 0, 0);
      }

      return {
        'uuid': uuid,
        'hash': '', // Empty files have no hash
        'size': '0',
      };
    }

    // Regular chunked upload
    final uploadKey = resumeUploadKey ?? _randomString(32);

    // Notify caller of UUID and uploadKey BEFORE starting upload
    if (onUploadStart != null && resumeFromChunk == 0) {
      onUploadStart(uuid, uploadKey);
    }

    final rm = _randomString(32);
    const chunkSz = 1048576; // 1MB chunks
    final totalChunks = (size / chunkSz).ceil();

    if (resumeFromChunk > 0) {
      _log('RESUMING upload:');
      _log('  UUID: $uuid');
      _log('  Upload Key: ${uploadKey.substring(0, 8)}...');
      _log('  Starting from chunk: $resumeFromChunk');
      _log('  Total chunks: $totalChunks');
    } else {
      _log('STARTING new upload:');
      _log('  UUID: $uuid');
      _log('  Upload Key: ${uploadKey.substring(0, 8)}...');
      _log('  Total chunks: $totalChunks');
    }

    final ingest = 'https://ingest.filen.io';
    final raf = await file.open();
    int offset = resumeFromChunk * chunkSz;
    int index = resumeFromChunk;

    final digestSink = DigestSink();
    final byteSink = crypto.sha512.startChunkedConversion(digestSink);

    try {
      // If resuming, re-hash previous chunks for final hash
      if (resumeFromChunk > 0) {
        _log('Re-hashing previous ${resumeFromChunk} chunks...');
        await raf.setPosition(0);
        for (var i = 0; i < resumeFromChunk; i++) {
          final len = min(chunkSz, size - (i * chunkSz));
          final bytes = await raf.read(len);
          byteSink.add(bytes);
        }
        await raf.setPosition(offset);
        _log('Re-hashing complete, resuming upload from byte $offset');
      }

      while (offset < size) {
        final len = min(chunkSz, size - offset);
        final bytes = await raf.read(len);
        byteSink.add(bytes);
        final encChunk = await _encryptData(bytes, fileKeyBytes);

        final chunkHash = crypto.sha512.convert(encChunk);
        final hashHex = HEX.encode(chunkHash.bytes).toLowerCase();

        final url = Uri.parse(
            '$ingest/v3/upload?uuid=$uuid&index=$index&parent=$parent&uploadKey=$uploadKey&hash=$hashHex');

        if (onProgress != null) {
          onProgress(index + 1, totalChunks, offset + len, size);
        } else {
          final progress = ((index + 1) / totalChunks * 100).toStringAsFixed(1);
          stdout.write(
              '     Uploading... ${index + 1}/$totalChunks chunks ($progress%)  \r');
        }

        try {
          final r = await http.post(url, body: encChunk, headers: {
            'Authorization': 'Bearer $apiKey'
          }).timeout(Duration(seconds: 30));

          if (r.statusCode != 200) {
            throw Exception('Chunk upload failed: ${r.statusCode} - ${r.body}');
          }
        } catch (e) {
          _log('Chunk $index failed: $e');
          throw ChunkUploadException(
            'Chunk $index upload failed',
            fileUuid: uuid,
            uploadKey: uploadKey,
            lastSuccessfulChunk: index - 1,
            originalError: e,
          );
        }

        offset += len;
        index++;
      }

      print(''); // Clear progress line

      byteSink.close();

      final totalHash = HEX.encode(digestSink.value?.bytes ?? []).toLowerCase();

      final metaJsonWithHash = json.encode({
        'name': name,
        'size': size,
        'mime': 'application/octet-stream',
        'key': fileKeyStr,
        'hash': totalHash,
        'lastModified': lastMod != null
            ? int.tryParse(lastMod) ?? DateTime.now().millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch,
      });

      final nameEncrypted = await _encryptMetadata002(name, fileKeyStr);
      final sizeEncrypted =
          await _encryptMetadata002(size.toString(), fileKeyStr);
      final mimeEncrypted =
          await _encryptMetadata002('application/octet-stream', fileKeyStr);
      final metadataEncryptedWithHash =
          await _encryptMetadata002(metaJsonWithHash, mk);
      final nameHashed = await _hashFileName(name);

      await _post('/v3/upload/done', {
        'uuid': uuid,
        'name': nameEncrypted,
        'nameHashed': nameHashed,
        'size': sizeEncrypted,
        'chunks': index,
        'mime': mimeEncrypted,
        'rm': rm,
        'metadata': metadataEncryptedWithHash,
        'version': 2,
        'uploadKey': uploadKey,
      });

      _invalidateCache(parent);

      return {
        'uuid': uuid,
        'hash': totalHash,
        'size': size.toString(),
      };
    } finally {
      await raf.close();
    }
  }

  void setAuth(Map<String, dynamic> c) {
    apiKey = c['apiKey'] ?? '';
    baseFolderUUID = c['baseFolderUUID'] ?? '';
    masterKeys = (c['masterKeys'] ?? '')
        .toString()
        .split('|')
        .where((k) => k.isNotEmpty)
        .toList();
    email = c['email'] ?? '';
  }

  void _log(String msg) {
    if (debugMode) print('🔍 [DEBUG] $msg');
  }

  void logWebDAV(String message) {
    if (debugMode) {
      final timestamp = DateTime.now().toIso8601String();
      print('[$timestamp] WebDAV: $message');
    }
  }

  // --- Token Refresh (Filen doesn't have this, but adding stub for consistency) ---
  Future<void> refreshToken() async {
    // Filen uses long-lived API keys, no refresh needed
    _log('Token refresh not needed for Filen');
  }

  // --- Cache management ---
  void _invalidateCache(String folderUuid) {
    _folderCache.remove(folderUuid);
    _fileCache.remove(folderUuid);
    // _pathCache.clear(); // Clear path cache to be safe
    _log('Cache invalidated for folder: $folderUuid');
  }

  Future<void> _clearParentCache(String itemUuid, String itemType) async {
    try {
      String? parentUuid;

      if (itemType == 'file') {
        final metadata = await getFileMetadata(itemUuid);
        parentUuid = metadata['data']?['parent'] ?? metadata['parent'];
      } else if (itemType == 'folder') {
        final metadata = await getFolderMetadata(itemUuid);
        parentUuid = metadata['data']?['parent'] ?? metadata['parent'];
      }

      if (parentUuid != null) {
        _invalidateCache(parentUuid);
        _log('Cleared parent cache for $parentUuid');
      }
    } catch (e) {
      _log('Could not clear parent cache for $itemUuid: $e');
    }
  }

  // --- AUTH & SETUP ---
  Future<Map<String, dynamic>> getAuthInfo(String email) async {
    final response = await _makeRequest(
      'POST',
      Uri.parse('$apiUrl/v3/auth/info'),
      body: json.encode({'email': email}),
      useAuth: false,
    );

    final data = json.decode(response.body);
    if (data['status'] != true) throw Exception(data['message']);
    return data['data'] ?? data;
  }

  Future<Map<String, dynamic>> login(String email, String password,
      {String twoFactorCode = "XXXXXX"}) async {
    final authInfo = await getAuthInfo(email);
    final authVersion = authInfo['authVersion'] ?? 2;
    final salt = authInfo['salt'] ?? '';

    _log('Deriving keys...');
    final derived = await _deriveKeys(password, authVersion, salt);
    final derivedPassword = derived['password']!;
    final localMasterKey = derived['masterKey']!;

    final loginPayload = {
      'email': email.toLowerCase(),
      'password': derivedPassword,
      'authVersion': authVersion,
      'twoFactorCode': twoFactorCode,
    };

    final response = await _makeRequest(
      'POST',
      Uri.parse('$apiUrl/v3/login'),
      body: json.encode(loginPayload),
      useAuth: false,
    );

    final data = json.decode(response.body);

    if (data['status'] == true && data['data'] != null) {
      final loginData = data['data'];

      List<String> rawEncryptedKeys = [];
      if (loginData['masterKeys'] is String) {
        rawEncryptedKeys = [loginData['masterKeys']];
      } else if (loginData['masterKeys'] is List) {
        rawEncryptedKeys =
            (loginData['masterKeys'] as List).map((e) => e.toString()).toList();
      }

      _log('Decrypting ${rawEncryptedKeys.length} master keys...');

      List<String> decryptedMasterKeys = [];
      for (var encryptedKey in rawEncryptedKeys) {
        try {
          final decrypted =
              await _decryptMetadata002(encryptedKey, localMasterKey);
          decryptedMasterKeys.add(decrypted);
        } catch (e) {
          _log('Failed to decrypt a master key: $e');
        }
      }

      if (decryptedMasterKeys.isEmpty) {
        _log('Warning: No master keys decrypted. Using local master key.');
        decryptedMasterKeys.add(localMasterKey);
      }

      return {
        'email': email,
        'apiKey': loginData['apiKey'],
        'masterKeys': decryptedMasterKeys.join('|'),
        'baseFolderUUID': loginData['baseFolderUUID'] ?? '',
        'userId': (loginData['id'] ?? loginData['userId'] ?? '').toString(),
      };
    } else {
      final code = data['code'] ?? '';
      if (code == 'enter_2fa' || code == 'wrong_2fa') throw Exception(code);
      throw Exception(data['message'] ?? 'Login failed');
    }
  }

  Future<String> fetchBaseFolderUUID() async {
    final response = await _makeRequest(
      'GET',
      Uri.parse('$apiUrl/v3/user/baseFolder'),
    );

    final data = json.decode(response.body);
    if (data['status'] == true && data['data'] != null) {
      return data['data']['uuid'] ?? '';
    }
    return data['uuid'] ?? '';
  }

  // --- HASHING ---
  Future<String> _generateHMACKey() async {
    final mk = masterKeys?.last ?? '';
    if (mk.isEmpty) {
      throw Exception('No master keys available');
    }
    final emailBytes = utf8.encode(email?.toLowerCase() ?? '');
    final mkBytes = utf8.encode(mk);
    final derived = _pbkdf2(mkBytes, emailBytes, 1, 32);
    return HEX.encode(derived).toLowerCase();
  }

  Future<String> _hashFileName(String name) async {
    final hmacKey = await _generateHMACKey();
    final hmacKeyBytes = HEX.decode(hmacKey);
    final hmac = crypto.Hmac(crypto.sha256, hmacKeyBytes);
    final digest = hmac.convert(utf8.encode(name.toLowerCase()));
    return HEX.encode(digest.bytes).toLowerCase();
  }

  // --- FILESYSTEM OPERATIONS ---

  Future<bool> checkFileExists(String parentUuid, String name) async {
    final hashed = await _hashFileName(name);
    try {
      final res = await _post(
          '/v3/file/exists', {'parent': parentUuid, 'nameHashed': hashed});
      return res['data']['exists'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<void> createDirectory(String name, String parent,
      {String? creationTime, String? modificationTime}) async {
    final uuid = _uuid();
    final mk = masterKeys?.last ?? '';
    if (mk.isEmpty) {
      throw Exception('No master keys available');
    }
    final encName = await _encryptMetadata002(json.encode({'name': name}), mk);
    final hashed = await _hashFileName(name);

    final payload = {
      'uuid': uuid,
      'name': encName,
      'nameHashed': hashed,
      'parent': parent,
    };

    if (creationTime != null) payload['creationTime'] = creationTime;
    if (modificationTime != null)
      payload['modificationTime'] = modificationTime;

    await _post('/v3/dir/create', payload);
    _invalidateCache(parent);
  }

  /// Helper to fetch and organize the flat tree for O(1) lookups
  Future<Map<String, List<Map<String, dynamic>>>> _fetchAndParseTree(String rootUuid) async {
    final treeData = await getFlatFolderTree(rootUuid);
    
    final rawFolders = treeData['folders'] as List? ?? [];
    // API might return 'files' or 'uploads'
    final rawFiles = (treeData['files'] as List?) ?? (treeData['uploads'] as List?) ?? [];
    
    if (debugMode) {
      print("🔍 [DEBUG] Tree fetched: ${rawFolders.length} folders, ${rawFiles.length} files");
    }

    // Adjacency Map: ParentUUID -> List of Children
    final adjacency = <String, List<Map<String, dynamic>>>{};

    // 1. Process Folders
    for (var f in rawFolders) {
      try {
        String uuid, encName, parent;
        
        // Handle Optimized List [uuid, name, parent]
        if (f is List) {
          if (f.length < 3) continue;
          uuid = f[0]; encName = f[1]; parent = f[2];
        } else {
          // Handle Dict
          if (f['deleted'] == true || f['trash'] == true) continue;
          uuid = f['uuid']; encName = f['name']; parent = f['parent'];
        }

        var decName = await _tryDecrypt(encName);
        if (decName.startsWith('{')) {
          decName = json.decode(decName)['name'];
        }

        final item = {
          'uuid': uuid, 
          'name': decName, 
          'parent': parent, 
          'type': 'folder'
        };

        if (!adjacency.containsKey(parent)) adjacency[parent] = [];
        adjacency[parent]!.add(item);
      } catch (_) {}
    }

    // 2. Process Files
    for (var f in rawFiles) {
      try {
        String uuid, encMeta, parent;
        
        // Handle Optimized List [uuid, bucket, region, chunks, parent, meta]
        if (f is List) {
          if (f.length < 6) continue;
          uuid = f[0]; parent = f[4]; encMeta = f[5];
        } else {
          // Handle Dict
          if (f['deleted'] == true || f['trash'] == true) continue;
          uuid = f['uuid']; parent = f['parent']; encMeta = f['metadata'];
        }

        final decMeta = await _tryDecrypt(encMeta);
        final meta = json.decode(decMeta);
        
        final item = {
          'uuid': uuid,
          'name': meta['name'] ?? 'Unknown',
          'parent': parent,
          'type': 'file',
          'size': meta['size'] ?? 0
        };

        if (!adjacency.containsKey(parent)) adjacency[parent] = [];
        adjacency[parent]!.add(item);
      } catch (_) {}
    }

    return adjacency;
  }

  Future<Map<String, dynamic>> getFlatFolderTree(String folderUuid) async {
    // FIX: Use _uuid() to generate a valid UUID v4, not _randomString
    final deviceId = _uuid(); 
    
    if (debugMode) {
      print("🔍 [DEBUG] Fetching flat tree for $folderUuid (DeviceID: $deviceId)...");
    }
    
    // Use /v3/dir/tree with integer skipCache
    final response = await _makeRequest(
      'POST',
      Uri.parse('$apiUrl/v3/dir/tree'),
      body: json.encode({
        'uuid': folderUuid,
        'deviceId': deviceId,
        'skipCache': 0 
      }),
    );

    final data = json.decode(response.body);
    
    if (data['status'] != true) {
      throw Exception(data['message'] ?? 'Failed to fetch tree');
    }
    
    return data['data'] ?? {};
  }

  Future<Map<String, dynamic>> createFolderRecursive(String path,
      {String? creationTime, String? modificationTime}) async {
    if (baseFolderUUID.isEmpty) throw Exception("Not logged in");

    var cleanPath = path.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (cleanPath.isEmpty) {
      return {'uuid': baseFolderUUID, 'plainName': 'Root', 'path': '/'};
    }

    // --- CACHE CHECK ---
    if (_pathCache.containsKey(cleanPath)) {
      return _pathCache[cleanPath]!;
    }

    var parts = cleanPath.split('/');
    var currentParentUuid = baseFolderUUID;
    var currentPath = '/';
    Map<String, dynamic> currentFolderInfo = {
      'uuid': baseFolderUUID,
      'plainName': 'Root',
      'path': '/'
    };

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;

      final isLastPart = (i == parts.length - 1);
      final partPathStr = '$currentPath$part/'.replaceAll('//', '/');
      final cleanPartPath = partPathStr.replaceAll(RegExp(r'/$'), '');

      // Check cache for this level
      if (_pathCache.containsKey(cleanPartPath)) {
        currentFolderInfo = _pathCache[cleanPartPath]!;
        currentParentUuid = currentFolderInfo['uuid'];
        currentPath = partPathStr;
        continue;
      }

      // Check if folder exists in current_uuid
      final folders = await listFoldersAsync(currentParentUuid);
      Map<String, dynamic>? found;

      for (var folder in folders) {
        if (folder['name'] == part) {
          found = folder;
          break;
        }
      }

      if (found != null) {
        currentParentUuid = found['uuid'];
        currentFolderInfo = found;
        currentFolderInfo['path'] = cleanPartPath;
        currentPath = partPathStr;
        
        // Update Cache
        _pathCache[cleanPartPath] = currentFolderInfo;
      } else {
        _log("Creating folder: $part in $currentPath");
        try {
          await createDirectory(
            part,
            currentParentUuid,
            creationTime: isLastPart ? creationTime : null,
            modificationTime: isLastPart ? modificationTime : null,
          );
        } catch (e) {
          if (e.toString().contains('409') || e.toString().contains('already exists')) {
             _log('Conflict (409), re-fetching...');
             await Future.delayed(Duration(milliseconds: 500));
             _invalidateCache(currentParentUuid);
          } else {
            throw e;
          }
        }

        // Re-fetch
        await Future.delayed(Duration(milliseconds: 200));
        _invalidateCache(currentParentUuid);
        final foldersAfter = await listFoldersAsync(currentParentUuid);
        
        Map<String, dynamic>? newFolder;
        for (var f in foldersAfter) {
          if (f['name'] == part) {
            newFolder = f;
            break;
          }
        }

        if (newFolder == null) throw Exception("Created folder but couldn't find it: $part");

        currentParentUuid = newFolder['uuid'];
        currentFolderInfo = newFolder;
        currentFolderInfo['path'] = cleanPartPath;
        currentPath = partPathStr;
        
        // Update Cache
        _pathCache[cleanPartPath] = currentFolderInfo;
      }
    }

    return currentFolderInfo;
  }

  Future<void> moveItem(String uuid, String destUuid, String type) async {
    await _clearParentCache(uuid, type);
    final endpoint = type == 'folder' ? '/v3/dir/move' : '/v3/file/move';
    await _post(endpoint, {'uuid': uuid, 'to': destUuid});
    _invalidateCache(destUuid);
    _pathCache.clear(); // Path structure changed, must clear path cache
  }

  Future<void> trashItem(String uuid, String type) async {
    await _clearParentCache(uuid, type);
    final endpoint = type == 'folder' ? '/v3/dir/trash' : '/v3/file/trash';
    await _post(endpoint, {'uuid': uuid});
    _pathCache.clear(); // Item removed from path, clear cache
  }

  Future<void> restoreItem(String uuid, String type) async {
    final endpoint = type == 'folder' ? '/v3/dir/restore' : '/v3/file/restore';
    await _post(endpoint, {'uuid': uuid});
    // Invalidate root cache since we don't know where it was restored to
    if (baseFolderUUID.isNotEmpty) {
      _invalidateCache(baseFolderUUID);
    }
  }

  Future<void> deletePermanently(String uuid, String type) async {
    await _clearParentCache(uuid, type);
    final endpoint = type == 'folder'
        ? '/v3/dir/delete/permanent'
        : '/v3/file/delete/permanent';
    await _post(endpoint, {'uuid': uuid});
  }

  Future<void> renameItem(String uuid, String newName, String type) async {
    await _clearParentCache(uuid, type); 
    final mk = masterKeys?.last ?? '';
    if (mk.isEmpty) {
      throw Exception('No master keys available');
    }
    final nameHashed = await _hashFileName(newName);

    if (type == 'folder') {
      final encName =
          await _encryptMetadata002(json.encode({'name': newName}), mk);
      await _post('/v3/dir/rename',
          {'uuid': uuid, 'name': encName, 'nameHashed': nameHashed});
    } else {
      final metaRaw = await getFileMetadata(uuid);
      final metadata = metaRaw['data'] ?? metaRaw;

      // Decrypt existing metadata
      final metaStr = await _tryDecrypt(metadata['metadata']);
      final metaJson = json.decode(metaStr);
      metaJson['name'] = newName; // Update name

      final fileKey = metaJson['key'];
      final nameEncrypted = await _encryptMetadata002(newName, fileKey);
      final metadataEncrypted =
          await _encryptMetadata002(json.encode(metaJson), mk);

      await _post('/v3/file/rename', {
        'uuid': uuid,
        'name': nameEncrypted,
        'metadata': metadataEncrypted,
        'nameHashed': nameHashed
      });
    }
    _pathCache.clear(); // Name changed, paths are invalid
  }

  Future<Map<String, dynamic>> getFileMetadata_old(String uuid) async {
    final info = await _post('/v3/file', {'uuid': uuid});
    final metaStr = await _tryDecrypt(info['data']['metadata']);
    return json.decode(metaStr);
  }

  Future<Map<String, dynamic>> getFileMetadata(String uuid) async {
    final info = await _post('/v3/file', {'uuid': uuid});
    return info['data'] ?? info;
  }

  Future<Map<String, dynamic>> getFolderMetadata(String uuid) async {
    final info = await _post('/v3/dir', {'uuid': uuid});
    return info['data'] ?? info;
  }

  // --- Upload/Download with batching ---

  bool shouldIncludeFile(
      String fileName, List<String> include, List<String> exclude) {
    if (include.isNotEmpty) {
      final matchesInclude =
          include.any((pattern) => Glob(pattern).matches(fileName));
      if (!matchesInclude) return false;
    }

    if (exclude.isNotEmpty) {
      final matchesExclude =
          exclude.any((pattern) => Glob(pattern).matches(fileName));
      if (matchesExclude) return false;
    }

    return true;
  }

  Future<void> uploadFile(File file, String parent,
      {String? creationTime, String? modificationTime}) async {
    final name = p.basename(file.path);
    final size = await file.length();
    final uuid = _uuid();
    final mk = masterKeys?.last ?? '';
    if (mk.isEmpty) {
      throw Exception('No master keys available');
    }

    final fileKeyStr = _randomString(32);
    final fileKeyBytes = Uint8List.fromList(utf8.encode(fileKeyStr));

    // Get modification time
    var lastMod = modificationTime;
    if (lastMod == null && creationTime == null) {
      try {
        final stat = await file.stat();
        lastMod = stat.modified.millisecondsSinceEpoch.toString();
      } catch (_) {}
    }

    final metaJson = json.encode({
      'name': name,
      'size': size,
      'mime': 'application/octet-stream',
      'key': fileKeyStr,
      'hash': '', // Empty hash for empty files
      'lastModified': lastMod != null
          ? int.tryParse(lastMod) ?? DateTime.now().millisecondsSinceEpoch
          : DateTime.now().millisecondsSinceEpoch,
    });

    final nameEncrypted = await _encryptMetadata002(name, fileKeyStr);
    final sizeEncrypted =
        await _encryptMetadata002(size.toString(), fileKeyStr);
    final mimeEncrypted =
        await _encryptMetadata002('application/octet-stream', fileKeyStr);
    final metadataEncrypted = await _encryptMetadata002(metaJson, mk);
    final nameHashed = await _hashFileName(name);

    // FIX: Handle empty files separately
    if (size == 0) {
      _log('Uploading empty file via /v3/upload/empty');

      await _post('/v3/upload/empty', {
        'uuid': uuid,
        'name': nameEncrypted,
        'nameHashed': nameHashed,
        'size': sizeEncrypted,
        'parent': parent,
        'mime': mimeEncrypted,
        'metadata': metadataEncrypted,
        'version': 2,
      });

      _invalidateCache(parent);
      return;
    }

    // Regular file upload for non-empty files
    final uploadKey = _randomString(32);
    final rm = _randomString(32);

    final ingest = 'https://ingest.filen.io';
    final raf = await file.open();
    int offset = 0;
    int index = 0;
    const chunkSz = 1048576;

    final digestSink = DigestSink();
    final byteSink = crypto.sha512.startChunkedConversion(digestSink);

    // Calculate total chunks for progress
    final totalChunks = (size / chunkSz).ceil();

    while (offset < size) {
      final len = min(chunkSz, size - offset);
      final bytes = await raf.read(len);
      byteSink.add(bytes);
      final encChunk = await _encryptData(bytes, fileKeyBytes);

      // Calculate hash of encrypted chunk
      final chunkHash = crypto.sha512.convert(encChunk);
      final hashHex = HEX.encode(chunkHash.bytes).toLowerCase();

      // Add hash parameter to upload
      final url = Uri.parse(
          '$ingest/v3/upload?uuid=$uuid&index=$index&parent=$parent&uploadKey=$uploadKey&hash=$hashHex');

      // Progress indicator
      final progress = ((index + 1) / totalChunks * 100).toStringAsFixed(1);
      stdout.write(
          '     Uploading... ${index + 1}/$totalChunks chunks ($progress%)  \r');

      final r = await http.post(url,
          body: encChunk, headers: {'Authorization': 'Bearer $apiKey'});

      if (r.statusCode != 200) {
        print(''); // Clear progress line
        throw Exception('Chunk upload failed: ${r.statusCode} - ${r.body}');
      }

      offset += len;
      index++;
    }

    print(''); // Clear progress line
    await raf.close();
    byteSink.close();

    final totalHash = HEX.encode(digestSink.value?.bytes ?? []).toLowerCase();

    // Update metadata with actual hash
    final metaJsonWithHash = json.encode({
      'name': name,
      'size': size,
      'mime': 'application/octet-stream',
      'key': fileKeyStr,
      'hash': totalHash,
      'lastModified': lastMod != null
          ? int.tryParse(lastMod) ?? DateTime.now().millisecondsSinceEpoch
          : DateTime.now().millisecondsSinceEpoch,
    });
    final metadataEncryptedWithHash =
        await _encryptMetadata002(metaJsonWithHash, mk);

    await _post('/v3/upload/done', {
      'uuid': uuid,
      'name': nameEncrypted,
      'nameHashed': nameHashed,
      'size': sizeEncrypted,
      'chunks': index,
      'mime': mimeEncrypted,
      'rm': rm,
      'metadata': metadataEncryptedWithHash,
      'version': 2,
      'uploadKey': uploadKey,
    });

    _invalidateCache(parent);
  }

  // --- In-Memory Upload for Web ---
  Future<void> uploadBytes(
    Uint8List data,
    String fileName,
    String parentUuid, {
    Function(int bytesUploaded, int totalBytes)? onProgress,
  }) async {
    _log('🚀 [Web] Starting memory upload for $fileName (${formatSize(data.length)})');
    
    final size = data.length;
    final uuid = _uuid();
    final mk = masterKeys?.last ?? '';
    if (mk.isEmpty) throw Exception('No master keys available');

    final fileKeyStr = _randomString(32);
    final fileKeyBytes = Uint8List.fromList(utf8.encode(fileKeyStr));

    // Handle Empty File
    if (size == 0) {
      _log('   Creating empty file...');
      final metaJson = json.encode({
        'name': fileName,
        'size': 0,
        'mime': 'application/octet-stream',
        'key': fileKeyStr,
        'hash': '',
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });

      final nameEncrypted = await _encryptMetadata002(fileName, fileKeyStr);
      final sizeEncrypted = await _encryptMetadata002('0', fileKeyStr);
      final mimeEncrypted = await _encryptMetadata002('application/octet-stream', fileKeyStr);
      final metadataEncrypted = await _encryptMetadata002(metaJson, mk);
      final nameHashed = await _hashFileName(fileName);

      await _post('/v3/upload/empty', {
        'uuid': uuid,
        'name': nameEncrypted,
        'nameHashed': nameHashed,
        'size': sizeEncrypted,
        'parent': parentUuid,
        'mime': mimeEncrypted,
        'metadata': metadataEncrypted,
        'version': 2,
      });
      
      if (onProgress != null) onProgress(0, 0);
      _invalidateCache(parentUuid);
      return;
    }

    // Chunked Upload
    final uploadKey = _randomString(32);
    final rm = _randomString(32);
    final ingest = 'https://ingest.filen.io';
    
    int offset = 0;
    int index = 0;
    const chunkSz = 1048576; // 1MB
    final totalChunks = (size / chunkSz).ceil();

    final digestSink = DigestSink();
    final byteSink = crypto.sha512.startChunkedConversion(digestSink);

    try {
      while (offset < size) {
        final end = min(size, offset + chunkSz);
        // Slice from memory instead of reading file
        final chunkBytes = data.sublist(offset, end); 
        
        // Hash original bytes
        byteSink.add(chunkBytes);
        
        // Encrypt
        final encChunk = await _encryptData(chunkBytes, fileKeyBytes);

        // Hash encrypted chunk for API integrity check
        final chunkHash = crypto.sha512.convert(encChunk);
        final hashHex = HEX.encode(chunkHash.bytes).toLowerCase();

        final url = Uri.parse('$ingest/v3/upload?uuid=$uuid&index=$index&parent=$parentUuid&uploadKey=$uploadKey&hash=$hashHex');

        _log('   Uploading chunk ${index + 1}/$totalChunks...');
        
        // Retry logic for unstable mobile connections
        int retry = 0;
        while (retry < 3) {
          try {
            final r = await http.post(
              url,
              body: encChunk,
              headers: {'Authorization': 'Bearer $apiKey'},
            ).timeout(const Duration(seconds: 45));

            if (r.statusCode != 200) {
              throw Exception('Status ${r.statusCode}: ${r.body}');
            }
            break; // Success
          } catch (e) {
            retry++;
            _log('   ⚠️ Chunk failed (Attempt $retry): $e');
            if (retry >= 3) throw e;
            await Future.delayed(const Duration(seconds: 1));
          }
        }

        offset += chunkBytes.length;
        index++;
        
        if (onProgress != null) {
          onProgress(offset, size);
        }
      }

      byteSink.close();
      final totalHash = HEX.encode(digestSink.value?.bytes ?? []).toLowerCase();

      // Finalize
      _log('   Finalizing upload...');
      final metaJsonWithHash = json.encode({
        'name': fileName,
        'size': size,
        'mime': 'application/octet-stream',
        'key': fileKeyStr,
        'hash': totalHash,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });

      final nameEncrypted = await _encryptMetadata002(fileName, fileKeyStr);
      final sizeEncrypted = await _encryptMetadata002(size.toString(), fileKeyStr);
      final mimeEncrypted = await _encryptMetadata002('application/octet-stream', fileKeyStr);
      final metadataEncryptedWithHash = await _encryptMetadata002(metaJsonWithHash, mk);
      final nameHashed = await _hashFileName(fileName);

      await _post('/v3/upload/done', {
        'uuid': uuid,
        'name': nameEncrypted,
        'nameHashed': nameHashed,
        'size': sizeEncrypted,
        'chunks': index,
        'mime': mimeEncrypted,
        'rm': rm,
        'metadata': metadataEncryptedWithHash,
        'version': 2,
        'uploadKey': uploadKey,
      });

      _invalidateCache(parentUuid);
      _log('✅ Upload complete!');

    } catch (e) {
      _log('❌ Upload Exception: $e');
      rethrow;
    }
  }

  // ============================================================================
  // 7. UPDATE: Upload with chunk-level resume
  // ============================================================================

  Future<void> upload(
    List<String> sources,
    String targetPath, {
    required bool recursive,
    required String onConflict,
    required bool preserveTimestamps,
    required List<String> include,
    required List<String> exclude,
    required String batchId,
    Map<String, dynamic>? initialBatchState,
    required Future<void> Function(Map<String, dynamic>) saveStateCallback,
    Function(String filename, int current, int total, int bytesUploaded,
            int totalBytes)?
        onFileProgress,
  }) async {
    _log("Upload target path: $targetPath");

    Map<String, dynamic> batchState;
    List<dynamic> tasks;

    if (initialBatchState != null) {
      print("🔄 Resuming batch...");
      batchState = initialBatchState;
      tasks = batchState['tasks'] as List<dynamic>;
    } else {
      print("🔍 Building task list...");
      tasks = [];

      // Loop over sources to build task list (same as before)
      for (final sourceArg in sources) {
        // Check for wildcards
        if (sourceArg.contains('*') || sourceArg.contains('?') || sourceArg.contains('[')) {
           final glob = Glob(sourceArg.replaceAll('\\', '/'));
           await for (final entity in glob.list()) {
              await _processEntityForUpload(entity, sourceArg, targetPath, recursive, include, exclude, tasks, preserveTimestamps);
           }
        } else {
           // Explicit path
           final type = await FileSystemEntity.type(sourceArg);
           if (type == FileSystemEntityType.directory) {
              await _processEntityForUpload(Directory(sourceArg), sourceArg, targetPath, recursive, include, exclude, tasks, preserveTimestamps);
           } else if (type == FileSystemEntityType.file) {
              await _processEntityForUpload(File(sourceArg), sourceArg, targetPath, recursive, include, exclude, tasks, preserveTimestamps);
           } else {
              _log("⚠️ Source not found: $sourceArg");
           }
        }
      }

      batchState = {
        'operationType': 'upload',
        'targetRemotePath': targetPath,
        'tasks': tasks,
      };
      await saveStateCallback(batchState);
      print("📝 Task list: ${tasks.length} files");
    }

    int successCount = 0;
    int skippedCount = 0;
    int errorCount = 0;
    int completedPreviously = 0;
    
    final totalTasks = tasks.length;

    // Use a single progress line for the whole batch
    for (int i = 0; i < totalTasks; i++) {
      final task = tasks[i] as Map<String, dynamic>;
      final localPath = task['localPath'] as String;
      final remotePath = task['remotePath'] as String;
      final status = task['status'] as String;
      final remoteName = p.basename(remotePath);

      // --- Progress Bar ---
      final pct = totalTasks > 0 ? ((i) / totalTasks * 100).toStringAsFixed(1) : '0.0';
      final width = 20;
      final filled = totalTasks > 0 ? ((i / totalTasks) * width).round() : 0;
      final bar = '█' * filled + '░' * (width - filled);
      
      if (!debugMode) {
        // Clean progress line
        final shortName = remoteName.length > 20 ? remoteName.substring(0, 17) + '...' : remoteName;
        stdout.write('\rUp: ${shortName.padRight(20)} |$bar| ${i+1}/$totalTasks ($pct%)  ');
      } else {
        _log("Processing ${i+1}/$totalTasks: $remoteName ($status)");
      }

      if (status == 'completed') {
        completedPreviously++;
        if (i == totalTasks -1 && !debugMode) stdout.write('\n'); 
        continue;
      }
      if (status.startsWith('skipped')) {
        skippedCount++;
        continue;
      }

      final localFile = File(localPath);
      if (!await localFile.exists()) {
        if (debugMode) print("⚠️ Source missing: $localPath");
        skippedCount++;
        task['status'] = 'skipped_missing';
        await saveStateCallback(batchState);
        continue;
      }

      // Resolve Parent (Uses Optimized Cache)
      final remoteParentPath = p.dirname(remotePath).replaceAll('\\', '/');
      Map<String, dynamic> parentInfo;
      try {
        parentInfo = await createFolderRecursive(remoteParentPath);
      } catch (e) {
        if (debugMode) print("❌ Error creating parent: $e");
        errorCount++;
        task['status'] = 'error_parent';
        continue;
      }

      // Check Conflict (Uses Cache)
      bool shouldUpload = true;
      if (task['fileUuid'] == null) {
        // Optimization: check local file list cache before API
        final cachedFiles = _fileCache[parentInfo['uuid']]?.items;
        bool exists = false;
        if (cachedFiles != null) {
           exists = (cachedFiles as List).any((f) => f['name'] == remoteName);
        } else {
           exists = await checkFileExists(parentInfo['uuid'], remoteName);
        }

        if (exists && onConflict == 'skip') {
           if (debugMode) print("⏭️ Skipping: $remoteName (exists)");
           skippedCount++;
           task['status'] = 'skipped_conflict';
           await saveStateCallback(batchState);
           shouldUpload = false;
        }
      }

      if (!shouldUpload) continue;

      // Upload
      try {
        final fileSize = await localFile.length();
        
        String? cTime, mTime;
        if (preserveTimestamps) {
           final stat = await localFile.stat();
           mTime = stat.modified.millisecondsSinceEpoch.toString();
           cTime = stat.changed.millisecondsSinceEpoch.toString();
        }

        task['status'] = 'uploading';
        await saveStateCallback(batchState);

        await uploadFileChunked(
          localFile,
          parentInfo['uuid'],
          fileUuid: task['fileUuid'],
          resumeUploadKey: task['uploadKey'],
          resumeFromChunk: (task['lastChunk'] ?? -1) + 1,
          creationTime: cTime,
          modificationTime: mTime,
          onUploadStart: (uuid, key) {
             task['fileUuid'] = uuid;
             task['uploadKey'] = key;
             task['lastChunk'] = -1;
             saveStateCallback(batchState);
          },
          onProgress: (cur, tot, bUp, bTot) {
             task['lastChunk'] = cur - 1;
          }
        );

        successCount++;
        task['status'] = 'completed';
        task['fileUuid'] = null;
        task['uploadKey'] = null;
        task['lastChunk'] = -1;

      } catch (e) {
        if (debugMode) print("\n❌ Upload error: $e");
        errorCount++;
        task['status'] = 'interrupted';
      }
      
      await saveStateCallback(batchState);
    }
    
    if (!debugMode) stdout.write('\n'); // Newline after progress bar

    print('=' * 40);
    print('📊 Upload Summary:');
    if (completedPreviously > 0) print('  ✅ Previous: $completedPreviously');
    print('  ✅ Uploaded: $successCount');
    print('  ⏭️  Skipped: $skippedCount');
    print('  ❌ Errors: $errorCount');
    print('=' * 40);
    
    if (errorCount > 0) throw Exception("Upload finished with errors");
  }

  // Helper for upload recursion
  Future<void> _processEntityForUpload(FileSystemEntity entity, String sourceBase, String targetPath, bool recursive, List<String> include, List<String> exclude, List<dynamic> tasks, bool preserveTimestamps) async {
      if (entity is Directory) {
          if (!recursive) {
            _log("Skipping directory: ${entity.path}");
            return;
          }
          
          final localDir = Directory(entity.path);
          String remoteBase;
          if (sourceBase.endsWith(Platform.pathSeparator) || sourceBase == '.' || sourceBase == './') {
             remoteBase = targetPath;
          } else {
             remoteBase = p.join(targetPath, p.basename(localDir.path)).replaceAll('\\', '/');
          }

          // Pre-create folder to ensure empty dirs are uploaded
          await createFolderRecursive(remoteBase);

          await for (final fileEntity in localDir.list(recursive: true, followLinks: false)) {
            if (fileEntity is File) {
              final relPath = p.relative(fileEntity.path, from: localDir.path);
              final remotePath = p.join(remoteBase, relPath).replaceAll('\\', '/');
              
              if (shouldIncludeFile(p.basename(fileEntity.path), include, exclude)) {
                tasks.add({
                  'localPath': fileEntity.path,
                  'remotePath': remotePath,
                  'status': 'pending',
                  'fileUuid': null,
                  'uploadKey': null,
                  'lastChunk': -1,
                });
              }
            }
          }
      } else if (entity is File) {
          final remotePath = p.join(targetPath, p.basename(entity.path)).replaceAll('\\', '/');
          if (shouldIncludeFile(p.basename(entity.path), include, exclude)) {
             tasks.add({
              'localPath': entity.path,
              'remotePath': remotePath,
              'status': 'pending',
              'fileUuid': null,
              'uploadKey': null,
              'lastChunk': -1,
            });
          }
      }
  }

  Future<Map<String, dynamic>> _resolveOrCreateFolder(String path) async {
    try {
      final info = await resolvePath(path);
      if (info['type'] != 'folder') {
        throw Exception("Path exists but is not a folder");
      }
      return info;
    } on Exception catch (e) {
      if (e.toString().contains("Path not found")) {
        _log("Creating target folder: $path");
        return await createFolderRecursive(path);
      }
      rethrow;
    }
  }

  /// Download file directly to memory (Uint8List) without writing to disk.
  Future<Uint8List> downloadFileBytes(
    String uuid, {
    Function(int bytesDownloaded, int totalBytes)? onProgress,
  }) async {
    _log('Downloading file to memory: $uuid');

    // 1. Fetch File Metadata
    final info = await _post('/v3/file', {'uuid': uuid});
    final d = info['data'];

    // 2. Decrypt Metadata
    final metaStr = await _tryDecrypt(d['metadata']);
    final meta = json.decode(metaStr);
    final keyBytes = _decodeUniversalKey(meta['key']);
    final chunks = int.parse(d['chunks'].toString());
    final host = 'https://egest.filen.io'; 

    final fileSize = meta['size'] ?? 0;

    final buffer = BytesBuilder(copy: false); 
    int bytesDownloaded = 0;

    for (var i = 0; i < chunks; i++) {
      final r = await http
          .get(Uri.parse('$host/${d['region']}/${d['bucket']}/$uuid/$i'));
      if (r.statusCode != 200) throw Exception('Chunk download failed: $i');

      final decrypted = await _decryptData(r.bodyBytes, keyBytes);
      buffer.add(decrypted);

      bytesDownloaded += decrypted.length;

      if (onProgress != null) {
        onProgress(bytesDownloaded, fileSize);
      }
    }

    return buffer.takeBytes();
  }

  /// Download file with range support
  Future<Uint8List> downloadFileRange(
    String uuid, {
    int? rangeStart,
    int? rangeEnd,
  }) async {
    _log('Downloading file range: $uuid ($rangeStart-$rangeEnd)');

    final info = await _post('/v3/file', {'uuid': uuid});
    final d = info['data'];
    final metaStr = await _tryDecrypt(d['metadata']);
    final meta = json.decode(metaStr);
    final keyBytes = _decodeUniversalKey(meta['key']);
    final chunks = int.parse(d['chunks'].toString());
    final host = 'https://egest.filen.io';
    final fileSize = meta['size'] ?? 0;

    // Calculate which chunks we need
    const chunkSize = 1048576;
    final startChunk = rangeStart != null ? rangeStart ~/ chunkSize : 0;
    final endChunk = rangeEnd != null ? rangeEnd ~/ chunkSize : chunks - 1;

    final buffer = BytesBuilder();

    for (var i = startChunk; i <= endChunk && i < chunks; i++) {
      final r = await http
          .get(Uri.parse('$host/${d['region']}/${d['bucket']}/$uuid/$i'));
      if (r.statusCode != 200) throw Exception('Chunk download failed');

      final decrypted = await _decryptData(r.bodyBytes, keyBytes);

      // Handle partial chunk at start
      if (i == startChunk && rangeStart != null) {
        final offset = rangeStart % chunkSize;
        buffer.add(decrypted.sublist(offset));
      }
      // Handle partial chunk at end
      else if (i == endChunk && rangeEnd != null) {
        final endOffset = rangeEnd % chunkSize + 1;
        buffer.add(decrypted.sublist(0, endOffset));
      }
      // Full chunk
      else {
        buffer.add(decrypted);
      }
    }

    return buffer.toBytes();
  }

  Future<Map<String, dynamic>> downloadFile(
    String uuid, {
    String? savePath,
    Function(int bytesDownloaded, int totalBytes)? onProgress,
  }) async {
    _log('Downloading file: $uuid');

    final info = await _post('/v3/file', {'uuid': uuid});
    final d = info['data'];
    final metaStr = await _tryDecrypt(d['metadata']);
    final meta = json.decode(metaStr);
    final keyBytes = _decodeUniversalKey(meta['key']);
    final chunks = int.parse(d['chunks'].toString());
    final host = 'https://egest.filen.io';

    final filename = meta['name'] ?? 'file';
    final fileSize = meta['size'] ?? 0;
    final modificationTime = meta['lastModified'];

    if (onProgress == null) {
      print('   📄 File: $filename (${formatSize(fileSize)})');
    }

    final targetPath = savePath ?? filename;
    final sink = File(targetPath).openWrite();

    int bytesDownloaded = 0;

    for (var i = 0; i < chunks; i++) {
      final r = await http
          .get(Uri.parse('$host/${d['region']}/${d['bucket']}/$uuid/$i'));
      if (r.statusCode != 200) throw Exception('Chunk fail');

      final decrypted = await _decryptData(r.bodyBytes, keyBytes);
      sink.add(decrypted);

      bytesDownloaded += decrypted.length;

      if (onProgress != null) {
        onProgress(bytesDownloaded, fileSize);
      }
    }

    await sink.close();

    return {
      'data': await File(targetPath).readAsBytes(),
      'filename': filename,
      'modificationTime': modificationTime,
    };
  }

  Future<void> downloadPath(
    String remotePath, {
    String? localDestination,
    required bool recursive,
    required String onConflict,
    required bool preserveTimestamps,
    required List<String> include,
    required List<String> exclude,
    required String batchId,
    Map<String, dynamic>? initialBatchState,
    required Future<void> Function(Map<String, dynamic>) saveStateCallback,
  }) async {
    // 1. Resolve Root Item
    final itemInfo = await resolvePath(remotePath);

    // 2. Handle Single File
    if (itemInfo['type'] == 'file') {
      final filename = p.basename(remotePath);
      if (!shouldIncludeFile(filename, include, exclude)) return;
      
      final localPath = localDestination != null && FileSystemEntity.isDirectorySync(localDestination)
          ? p.join(localDestination, filename)
          : (localDestination ?? filename);
          
      // Check conflict
      if (File(localPath).existsSync() && onConflict == 'skip') {
         print('⏭️  Skipping: $filename (exists)');
         return;
      }
      
      print('📥 Downloading: $filename');
      await downloadFile(itemInfo['uuid'], savePath: localPath);
      print('✅ Downloaded: $localPath');
      return;
    }

    // 3. Handle Folder (Batch)
    if (itemInfo['type'] != 'folder') throw Exception("Unknown type");
    if (!recursive) throw Exception("Use -r for recursive download");

    final baseDestPath = localDestination ?? (itemInfo['metadata']?['name'] ?? 'download');
    await Directory(baseDestPath).create(recursive: true);
    
    _log("Downloading folder: $remotePath to $baseDestPath");

    // 4. Batch Setup
    Map<String, dynamic> batchState;
    List<dynamic> tasks;

    if (initialBatchState != null) {
      print("🔄 Resuming batch...");
      batchState = initialBatchState;
      tasks = batchState['tasks'];
    } else {
      print("🔍 Building task list (Fast)...");
      tasks = [];

      try {
        // --- FAST TREE FETCH ---
        final treeData = await getFlatFolderTree(itemInfo['uuid']);
        
        final rawFolders = treeData['folders'] as List? ?? [];
        final rawFiles = (treeData['files'] as List?) ?? (treeData['uploads'] as List?) ?? [];

        _log("Tree response: ${rawFolders.length} folders, ${rawFiles.length} files");

        // Map Folders: UUID -> {name, parent}
        final folderMap = <String, Map<String, dynamic>>{};
        
        for (var f in rawFolders) {
          try {
            String uuid, encName, parent;
            
            // Handle List vs Dict format
            if (f is List) {
               if (f.length < 3) continue;
               uuid = f[0]; encName = f[1]; parent = f[2];
            } else {
               if (f['deleted'] == true || f['trash'] == true) continue;
               uuid = f['uuid']; encName = f['name']; parent = f['parent'];
            }

            var decName = await _tryDecrypt(encName);
            if (decName.startsWith('{')) {
               decName = json.decode(decName)['name'];
            }
            folderMap[uuid] = {'name': decName, 'parent': parent};
          } catch (_) {}
        }

        // Helper to reconstruct path
        String? getRelPath(String? parentUuid) {
           var parts = <String>[];
           var curr = parentUuid;
           var seen = <String>{};
           
           while (curr != null && curr != itemInfo['uuid']) {
              if (seen.contains(curr)) return null; // Cycle
              seen.add(curr);
              
              if (!folderMap.containsKey(curr)) return null; // Orphan
              final f = folderMap[curr]!;
              parts.add(f['name']);
              curr = f['parent'];
           }
           if (curr == null && itemInfo['uuid'] != 'root') return null; // Didn't reach target root
           return parts.reversed.join(Platform.pathSeparator);
        }

        // Process Files
        for (var f in rawFiles) {
           try {
             String uuid, encMeta, parent;
             
             // Handle List vs Dict
             if (f is List) {
                // Correct indices based on Python findings:
                // [uuid(0), bucket(1), region(2), chunks(3), parent(4), meta(5)]
                if (f.length < 6) continue;
                uuid = f[0]; parent = f[4]; encMeta = f[5];
             } else {
                if (f['deleted'] == true || f['trash'] == true) continue;
                uuid = f['uuid']; parent = f['parent']; encMeta = f['metadata'];
             }

             final decMeta = await _tryDecrypt(encMeta);
             final meta = json.decode(decMeta);
             final filename = meta['name'];
             final lastMod = meta['lastModified'] ?? 0;

             if (!shouldIncludeFile(filename, include, exclude)) continue;

             var relDir = getRelPath(parent);
             // Handle files in root of request
             if (parent == itemInfo['uuid']) relDir = '';
             else if (relDir == null) continue;

             final localPath = p.join(baseDestPath, relDir!, filename);
             
             tasks.add({
               'remoteUuid': uuid,
               'localPath': localPath,
               'status': 'pending',
               'remoteModificationTime': lastMod
             });

           } catch (e) {
             _log("File parse error: $e");
           }
        }

      } catch (e) {
        throw Exception("Failed to fetch tree: $e");
      }

      batchState = {
        'operationType': 'download',
        'remotePath': remotePath,
        'localDestination': baseDestPath,
        'tasks': tasks
      };
      await saveStateCallback(batchState);
      print("📝 Task list: ${tasks.length} files");
    }

    // 5. Execution Loop
    int successCount = 0;
    int skippedCount = 0;
    int errorCount = 0;
    int completedPreviously = 0;
    final totalTasks = tasks.length;

    for (int i = 0; i < totalTasks; i++) {
       final task = tasks[i] as Map<String, dynamic>;
       final localPath = task['localPath'] as String;
       final remoteUuid = task['remoteUuid'] as String;
       final status = task['status'] as String;
       final remoteModTime = task['remoteModificationTime'];
       final filename = p.basename(localPath);

       // Progress Bar
       final pct = ((i) / totalTasks * 100).toStringAsFixed(1);
       final width = 20;
       final filled = ((i / totalTasks) * width).round();
       final bar = '█' * filled + '░' * (width - filled);
       if (!debugMode) {
         stdout.write('\rDown: ${filename.padRight(20).substring(0, 20)} |$bar| ${i+1}/$totalTasks ($pct%)  ');
       }

       if (status == 'completed') {
         completedPreviously++;
         continue;
       }
       if (status.startsWith('skipped')) {
         skippedCount++;
         continue;
       }

       // Create dir
       await Directory(p.dirname(localPath)).create(recursive: true);
       final localFile = File(localPath);

       // Check conflict
       if (await localFile.exists()) {
          if (onConflict == 'skip') {
             if (debugMode) print("Skipping $filename");
             skippedCount++;
             task['status'] = 'skipped_conflict';
             await saveStateCallback(batchState);
             continue;
          }
          if (onConflict == 'newer' && remoteModTime != null) {
             final stat = await localFile.stat();
             if (stat.modified.millisecondsSinceEpoch >= (remoteModTime is int ? remoteModTime : int.parse(remoteModTime.toString()))) {
                skippedCount++;
                task['status'] = 'skipped_newer';
                await saveStateCallback(batchState);
                continue;
             }
          }
       }

       // Download
       try {
         if (debugMode) print("Downloading $filename");
         
         // Using a silenced downloadFile call would be ideal, but here we capture output
         final result = await downloadFile(remoteUuid, savePath: localPath);
         
         if (preserveTimestamps) {
            final mt = result['modificationTime'] ?? remoteModTime;
            if (mt != null) {
               try {
                 final dt = mt is int ? DateTime.fromMillisecondsSinceEpoch(mt) : DateTime.parse(mt.toString());
                 await localFile.setLastModified(dt);
               } catch (_) {}
            }
         }

         successCount++;
         task['status'] = 'completed';
       } catch (e) {
         if (debugMode) print("Error: $e");
         errorCount++;
         task['status'] = 'error_download';
       }
       
       await saveStateCallback(batchState);
    }

    print('\n' + '=' * 40);
    print('📊 Download Summary:');
    if (completedPreviously > 0) print('  ✅ Previous: $completedPreviously');
    print('  ✅ Downloaded: $successCount');
    print('  ⏭️  Skipped: $skippedCount');
    print('  ❌ Errors: $errorCount');
    print('=' * 40);
  }

  // --- Trash Operations ---

  Future<List<Map<String, dynamic>>> getTrashContent() async {
    // API Doc: POST /dir/content with uuid: "trash"
    final response =
        await _post('/v3/dir/content', {'uuid': 'trash', 'foldersOnly': false});

    final data = response['data'];
    final List<dynamic> rawFolders = data['folders'] ?? [];
    final List<dynamic> rawUploads = data['uploads'] ?? [];

    List<Map<String, dynamic>> results = [];

    // Process Folders
    for (var f in rawFolders) {
      String name = 'Unknown';
      try {
        // Folders have 'name' field which is encrypted
        var dec = await _tryDecrypt(f['name']);
        name = dec.startsWith('{') ? json.decode(dec)['name'] : dec;
      } catch (_) {
        name = '[Encrypted]';
      }

      results.add({
        'type': 'folder',
        'name': name,
        'uuid': f['uuid'],
        'size': 0, // Folders don't usually return size in this view
        'parent': f['parent'],
        'timestamp': f['timestamp'],
        'lastModified': f['lastModified'] ?? 0,
      });
    }

    // Process Files
    for (var f in rawUploads) {
      String name = 'Unknown';
      int size = 0;
      int lastModified = 0;

      try {
        // Files have 'metadata' field which is encrypted
        final m = json.decode(await _tryDecrypt(f['metadata']));
        name = m['name'];
        size = m['size'] ?? 0;
        lastModified = m['lastModified'] ?? 0;
      } catch (_) {
        name = '[Encrypted]';
      }

      results.add({
        'type': 'file',
        'name': name,
        'uuid': f['uuid'],
        'size': size,
        'parent': f['parent'],
        'timestamp': f['timestamp'],
        'lastModified': lastModified,
      });
    }

    return results;
  }

  // --- Search & Find ---

  Future<Map<String, List<Map<String, dynamic>>>> search(String query,
      {bool detailed = false}) async {
    // Filen doesn't have server-side search
    // This would need to be implemented as client-side search
    _log('Server-side search not available, using client-side...');

    final results = await findFiles('/', '*$query*', maxDepth: -1);

    return {
      'folders': [],
      'files': results,
    };
  }

  Future<List<Map<String, dynamic>>> findFiles(String startPath, String pattern,
      {int maxDepth = -1}) async {
    
    // 1. Resolve Root to get UUID
    final rootInfo = await resolvePath(startPath);
    if (rootInfo['type'] != 'folder') return [];
    
    // 2. Fetch Flattened Tree (One API Call - Fast)
    // This avoids making hundreds of API calls for recursive folders
    final treeData = await getFlatFolderTree(rootInfo['uuid']);
    final rawFolders = treeData['folders'] as List? ?? [];
    final rawFiles = (treeData['files'] as List?) ?? (treeData['uploads'] as List?) ?? [];
    
    // 3. Build Folder Map (UUID -> {name, parent})
    // We need this map to reconstruct full paths from parent UUIDs
    final folderMap = <String, Map<String, dynamic>>{};
    
    for (var f in rawFolders) {
       try {
          String uuid, encName, parent;
          
          // Handle Optimized List Format [uuid, name, parent]
          if (f is List) { 
             if (f.length < 3) continue;
             uuid = f[0]; encName = f[1]; parent = f[2]; 
          } else { 
             // Handle Standard Dict Format
             if (f['deleted'] == true || f['trash'] == true) continue;
             uuid = f['uuid']; encName = f['name']; parent = f['parent']; 
          }
          
          var decName = await _tryDecrypt(encName);
          if (decName.startsWith('{')) {
             decName = json.decode(decName)['name'];
          }
          folderMap[uuid] = {'name': decName, 'parent': parent};
       } catch (_) {}
    }

    final results = <Map<String, dynamic>>[];
    final glob = Glob(pattern, caseSensitive: false);
    
    // Helper to reconstruct full path by tracing parents upwards
    String? getFullPath(String? parentUuid) {
        var parts = <String>[];
        var curr = parentUuid;
        var seen = <String>{}; // Cycle detection

        while (curr != null && curr != rootInfo['uuid']) {
           if (seen.contains(curr)) return null;
           seen.add(curr);

           if (!folderMap.containsKey(curr)) return null; // Orphaned
           final f = folderMap[curr]!;
           parts.add(f['name']);
           curr = f['parent'];
        }
        
        // If we ran out of parents but didn't hit the requested root, it's outside the scope
        if (curr == null && rootInfo['uuid'] != 'root') return null;
        
        return p.join(startPath, parts.reversed.join('/'));
    }

    // 4. Process and Filter Files
    for (var f in rawFiles) {
       try {
          String uuid, encMeta, parent;
          
          // Handle Optimized List Format 
          // [uuid(0), bucket(1), region(2), chunks(3), parent(4), meta(5)]
          if (f is List) { 
             if (f.length < 6) continue;
             uuid = f[0]; parent = f[4]; encMeta = f[5];
          } else {
             // Handle Standard Dict Format
             if (f['deleted'] == true || f['trash'] == true) continue;
             uuid = f['uuid']; parent = f['parent']; encMeta = f['metadata'];
          }
          
          final meta = json.decode(await _tryDecrypt(encMeta));
          final name = meta['name'];
          
          // Check Pattern
          if (!glob.matches(name)) continue;
          
          // Reconstruct Path
          var dirPath = getFullPath(parent);
          
          // Special case: File is directly in the start folder
          if (parent == rootInfo['uuid']) dirPath = startPath;
          else if (dirPath == null) continue;
          
          // Check Depth
          if (maxDepth != -1) {
             final relDepth = dirPath!.split('/').length - startPath.split('/').length;
             if (relDepth >= maxDepth) continue;
          }

          results.add({
             'uuid': uuid,
             'name': name,
             'fullPath': p.join(dirPath!, name).replaceAll('\\', '/'),
             'size': meta['size'] ?? 0,
             'lastModified': meta['lastModified'] ?? 0
          });
       } catch (_) {}
    }
    
    return results;
  }

  Future<void> printTree(
    String path,
    void Function(String) printLine, {
    int maxDepth = 3,
  }) async {
    try {
      // 1. Resolve Root
      final root = await resolvePath(path);
      if (root['type'] != 'folder') {
        printLine("└── 📄 ${p.basename(path)}");
        return;
      }
      
      final rootUuid = root['uuid'];
      
      // 2. Fetch Data Structure (Fast)
      final adjacency = await _fetchAndParseTree(rootUuid);
      
      // 3. Recursive Print from Memory
      void printNode(String parentUuid, int currentDepth, String prefix) {
        if (currentDepth >= maxDepth) return;
        
        final children = adjacency[parentUuid] ?? [];
        
        // Sort: Folders first, then Files, alphabetically
        children.sort((a, b) {
          if (a['type'] != b['type']) {
            return a['type'] == 'folder' ? -1 : 1; // Folder first
          }
          return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
        });
        
        for (var i = 0; i < children.length; i++) {
          final item = children[i];
          final isLast = (i == children.length - 1);
          final connector = isLast ? "└── " : "├── ";
          
          if (item['type'] == 'folder') {
            printLine("$prefix$connector📁 ${item['name']}/");
            final childPrefix = prefix + (isLast ? "    " : "│   ");
            printNode(item['uuid'], currentDepth + 1, childPrefix);
          } else {
            final size = formatSize(item['size']);
            printLine("$prefix$connector📄 ${item['name']} ($size)");
          }
        }
      }

      // Start printing
      printNode(rootUuid, 0, "");
      
    } catch (e) {
      printLine("└── ❌ Error: $e");
    }
  }

  // --- Path Resolution ---

  Future<Map<String, dynamic>> resolvePath(String path) async {
    if (baseFolderUUID.isEmpty) throw Exception("Not logged in");

    var cleanPath = path.trim();
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);
    if (cleanPath.endsWith('/')) cleanPath = cleanPath.substring(0, cleanPath.length - 1);

    // Root check
    if (cleanPath.isEmpty || cleanPath == '.') {
      return {
        'type': 'folder',
        'uuid': baseFolderUUID,
        'metadata': {'uuid': baseFolderUUID, 'name': 'Root'},
        'path': '/'
      };
    }

    // --- CHECK CACHE ---
    if (_pathCache.containsKey(cleanPath)) {
      return _pathCache[cleanPath]!;
    }

    String currentUuid = baseFolderUUID;
    String resolvedPath = '/';
    Map<String, dynamic> currentMetadata = {'uuid': baseFolderUUID, 'name': 'Root'};
    
    final pathParts = cleanPath.split('/').where((p) => p.isNotEmpty).toList();

    for (var i = 0; i < pathParts.length; i++) {
      final part = pathParts[i];
      final isLastPart = (i == pathParts.length - 1);
      final currentPartPath = '$resolvedPath$part'.replaceAll('//', '/');

      // Check cache for intermediate steps
      if (_pathCache.containsKey(currentPartPath.replaceAll(RegExp(r'^/'), ''))) {
         final cached = _pathCache[currentPartPath.replaceAll(RegExp(r'^/'), '')]!;
         currentUuid = cached['uuid'];
         currentMetadata = cached['metadata'] ?? cached;
         resolvedPath = '$currentPartPath/';
         if (isLastPart) return cached;
         continue;
      }

      final folders = await listFoldersAsync(currentUuid, detailed: true);
      Map<String, dynamic>? foundFolder;
      
      for (var folder in folders) {
        if (folder['name'] == part) {
          foundFolder = folder;
          break;
        }
      }

      Map<String, dynamic>? foundFile;
      if (isLastPart) {
        final files = await listFolderFiles(currentUuid, detailed: true);
        for (var file in files) {
          if (file['name'] == part) {
            foundFile = file;
            break;
          }
        }
      }

      if (foundFolder != null && (!isLastPart || foundFile == null)) {
        currentUuid = foundFolder['uuid'];
        currentMetadata = foundFolder;
        resolvedPath = '$resolvedPath$part/'.replaceAll('//', '/');
        
        final result = {
          'type': 'folder',
          'uuid': foundFolder['uuid'],
          'metadata': foundFolder,
          'path': resolvedPath.substring(0, resolvedPath.length - 1),
          'parent': foundFolder['parent'],
        };
        
        // Populate Cache
        _pathCache[result['path']] = result;
        
        if (isLastPart) return result;
        
      } else if (foundFile != null && isLastPart) {
        resolvedPath = '$resolvedPath$part'.replaceAll('//', '/');
        return {
          'type': 'file',
          'uuid': foundFile['uuid'],
          'metadata': foundFile,
          'path': resolvedPath,
          'parent': currentUuid,
        };
      } else {
        throw Exception("Path not found: $resolvedPath$part");
      }
    }

    return {
      'type': 'folder',
      'uuid': currentUuid,
      'metadata': currentMetadata,
      'path': resolvedPath.isEmpty ? '/' : resolvedPath
    };
  }

  // --- List Operations with Caching ---

  Future<List<Map<String, dynamic>>> listFoldersAsync(String u,
      {bool detailed = false}) async {
    final cached = _folderCache[u];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _cacheDuration) {
      _log('Using cached folder list for $u');
      return List<Map<String, dynamic>>.from(cached.items);
    }

    final response = await _post('/v3/dir/content', {'uuid': u});
    // Handle case where 'folders' might be null
    final d = response['data']['folders'] ?? [];
    
    List<Map<String, dynamic>> res = [];

    for (var f in d) {
      // Basic Dict parsing (dir/content usually returns dicts, not lists)
      try {
        var dec = await _tryDecrypt(f['name']);
        var name = dec.startsWith('{') ? json.decode(dec)['name'] : dec;
        res.add({
          'type': 'folder',
          'name': name,
          'uuid': f['uuid'],
          'size': 0,
          'parent': f['parent'],
          'timestamp': f['timestamp'],
          'lastModified': f['lastModified'],
        });
      } catch (_) {
        res.add({
          'type': 'folder',
          'name': '[Encrypted]',
          'uuid': f['uuid'],
          'size': 0,
        });
      }
    }

    _folderCache[u] = _CacheEntry(items: res, timestamp: DateTime.now());

    if (!detailed) {
      return res.map((item) => {
        'type': item['type'],
        'name': item['name'],
        'uuid': item['uuid'],
        'size': item['size'],
      }).toList();
    }
    return res;
  }

  Future<List<Map<String, dynamic>>> listFolderFiles(String u,
      {bool detailed = false}) async {
    final cached = _fileCache[u];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _cacheDuration) {
      _log('Using cached file list for $u');
      return List<Map<String, dynamic>>.from(cached.items);
    }

    final response = await _post('/v3/dir/content', {'uuid': u});
    final d = response['data']['uploads'] ?? [];
    
    final res = await Future.wait((d as List).map((f) async {
      try {
        final m = json.decode(await _tryDecrypt(f['metadata']));
        return {
          'type': 'file',
          'name': m['name'],
          'uuid': f['uuid'],
          'size': m['size'],
          'parent': f['parent'],
          'timestamp': f['timestamp'],
          'lastModified': m['lastModified'],
        };
      } catch (_) {
        return {
          'type': 'file',
          'name': '[Encrypted]',
          'uuid': f['uuid'],
          'size': 0,
        };
      }
    }).toList());

    // Cast to correct type
    final typedRes = res.cast<Map<String, dynamic>>();

    _fileCache[u] = _CacheEntry(items: typedRes, timestamp: DateTime.now());

    if (!detailed) {
      return typedRes.map((item) => {
        'type': item['type'],
        'name': item['name'],
        'uuid': item['uuid'],
        'size': item['size'],
      }).toList();
    }
    return typedRes;
  }

  // --- CRYPTO PRIMITIVES ---

  Future<String> _encryptMetadata002(String t, String k) async {
    final ivStr = _randomString(12);
    final dk = _pbkdf2(utf8.encode(k), utf8.encode(k), 1, 32);
    final c = GCMBlockCipher(AESEngine())
      ..init(
          true,
          AEADParameters(KeyParameter(dk), 128,
              Uint8List.fromList(utf8.encode(ivStr)), Uint8List(0)));
    return '002$ivStr${base64.encode(c.process(Uint8List.fromList(utf8.encode(t))))}';
  }

  Future<String> _decryptMetadata002(String m, String k) async {
    if (!m.startsWith('002')) throw Exception('Invalid version');
    final iv = m.substring(3, 15);
    final dk = _pbkdf2(utf8.encode(k), utf8.encode(k), 1, 32);
    final c = GCMBlockCipher(AESEngine())
      ..init(
          false,
          AEADParameters(KeyParameter(dk), 128,
              Uint8List.fromList(utf8.encode(iv)), Uint8List(0)));
    return utf8.decode(c.process(base64.decode(m.substring(15))));
  }

  Future<Uint8List> _encryptData(Uint8List d, Uint8List k) async {
    if (kIsWeb) {
      try {
        final iv = _randomBytes(12);
        
        // FIX: Rename to webCrypto
        final webCrypto = html.window.crypto;
        final subtle = js_util.getProperty(webCrypto!, 'subtle');

        // Import Key
        final keyParams = js_util.newObject();
        js_util.setProperty(keyParams, 'name', 'AES-GCM');
        
        final keyPromise = js_util.callMethod(subtle, 'importKey', [
          'raw', k, keyParams, false, ['encrypt']
        ]);
        final keyObj = await js_util.promiseToFuture(keyPromise);

        // Encrypt
        final encryptParams = js_util.newObject();
        js_util.setProperty(encryptParams, 'name', 'AES-GCM');
        js_util.setProperty(encryptParams, 'iv', iv);

        final encPromise = js_util.callMethod(subtle, 'encrypt', [
          encryptParams, keyObj, d
        ]);
        
        final encryptedBuffer = await js_util.promiseToFuture(encPromise);
        final encryptedBytes = Uint8List.view(encryptedBuffer);
        
        return Uint8List.fromList([...iv, ...encryptedBytes]);
      } catch (e) {
        _log('WebCrypto encrypt error: $e');
      }
    }

    final iv = _randomBytes(12);
    final c = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(k), 128, iv, Uint8List(0)));
    return Uint8List.fromList([...iv, ...c.process(d)]);
  }

  Future<Uint8List> _decryptData(Uint8List d, Uint8List k) async {
    if (kIsWeb) {
      try {
        if (d.length < 12) throw Exception('Invalid data length');
        final iv = d.sublist(0, 12);
        final cipherText = d.sublist(12);
        
        // FIX: Rename to webCrypto
        final webCrypto = html.window.crypto;
        final subtle = js_util.getProperty(webCrypto!, 'subtle');

        // Import Key
        final keyParams = js_util.newObject();
        js_util.setProperty(keyParams, 'name', 'AES-GCM');
        
        final keyPromise = js_util.callMethod(subtle, 'importKey', [
          'raw', k, keyParams, false, ['decrypt']
        ]);
        final keyObj = await js_util.promiseToFuture(keyPromise);

        // Decrypt
        final decryptParams = js_util.newObject();
        js_util.setProperty(decryptParams, 'name', 'AES-GCM');
        js_util.setProperty(decryptParams, 'iv', iv);

        final decPromise = js_util.callMethod(subtle, 'decrypt', [
          decryptParams, keyObj, cipherText
        ]);
        
        final decryptedBuffer = await js_util.promiseToFuture(decPromise);
        return Uint8List.view(decryptedBuffer);
      } catch (e) {
        // Fallback silently if tags mismatch or other crypto errors
      }
    }

    final c = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(k), 128, d.sublist(0, 12), Uint8List(0)));
    return c.process(d.sublist(12));
  }

  Uint8List _decodeUniversalKey(String k) {
    if (k.length == 32 && k.contains(RegExp(r'[a-zA-Z0-9\-_]'))) {
      return Uint8List.fromList(utf8.encode(k));
    }
    try {
      return base64Url.decode(base64Url.normalize(k));
    } catch (_) {}
    try {
      return base64.decode(base64.normalize(k));
    } catch (_) {}
    try {
      return Uint8List.fromList(HEX.decode(k));
    } catch (_) {}
    throw Exception('Key decode failed');
  }

  Future<String> _tryDecrypt(String s) async {
    for (var k in masterKeys?.reversed ?? <String>[]) {
      try {
        return await _decryptMetadata002(s, k);
      } catch (_) {}
    }
    throw Exception('Decrypt failed');
  }

  // --- HELPERS ---

  Future<Map<String, dynamic>> _post(String ep, dynamic b,
      {bool auth = true}) async {
    final r = await _makeRequest(
      'POST',
      Uri.parse('$apiUrl$ep'),
      body: json.encode(b),
      useAuth: auth,
    );

    final d = json.decode(utf8.decode(r.bodyBytes, allowMalformed: true));
    if (d['status'] != true) throw Exception(d['message']);
    return d;
  }

  Future<Map<String, String>> _deriveKeys(String p, int v, String s) async {
    // --- WEB OPTIMIZATION: Safe JS Interop ---
    if (kIsWeb) {
      try {
        _log('🔑 [WebCrypto] Deriving keys via js_util...');
        final start = DateTime.now();

        final passwordBytes = Uint8List.fromList(utf8.encode(p));
        final saltBytes = Uint8List.fromList(utf8.encode(s));

        // FIX: Rename variable to webCrypto to avoid shadowing package:crypto
        final webCrypto = html.window.crypto;
        final subtle = js_util.getProperty(webCrypto!, 'subtle');

        // 1. Import Key
        final importParams = js_util.newObject();
        js_util.setProperty(importParams, 'name', 'PBKDF2');

        final keyMaterialPromise = js_util.callMethod(subtle, 'importKey', [
          'raw',
          passwordBytes,
          importParams,
          false,
          ['deriveBits'],
        ]);
        
        final keyMaterial = await js_util.promiseToFuture(keyMaterialPromise);

        // 2. Derive Bits
        final deriveParams = js_util.newObject();
        js_util.setProperty(deriveParams, 'name', 'PBKDF2');
        js_util.setProperty(deriveParams, 'salt', saltBytes);
        js_util.setProperty(deriveParams, 'iterations', 200000);
        js_util.setProperty(deriveParams, 'hash', 'SHA-512');

        final bitsPromise = js_util.callMethod(subtle, 'deriveBits', [
          deriveParams,
          keyMaterial,
          512 // 64 bytes * 8 bits
        ]);

        final derivedByteBuffer = await js_util.promiseToFuture(bitsPromise);
        final derivedList = Uint8List.view(derivedByteBuffer);
        
        final k = HEX.encode(derivedList).toLowerCase();

        print('✅ [WebCrypto] Key derived in ${DateTime.now().difference(start).inMilliseconds}ms');

        return (v == 2)
            ? {
                'masterKey': k.substring(0, 64),
                // Now 'crypto' correctly refers to the package import
                'password': HEX
                    .encode(crypto.sha512.convert(utf8.encode(k.substring(64))).bytes)
                    .toLowerCase()
              }
            : {'masterKey': k, 'password': k};
      } catch (e) {
        print('⚠️ [WebCrypto] Failed: $e');
        // Fallthrough to Dart implementation
      }
    }
    
    // Dart Fallback
    final k = HEX
        .encode(_pbkdf2(utf8.encode(p), utf8.encode(s), 200000, 64))
        .toLowerCase();
    return (v == 2)
        ? {
            'masterKey': k.substring(0, 64),
            'password': HEX
                .encode(crypto.sha512.convert(utf8.encode(k.substring(64))).bytes)
                .toLowerCase()
          }
        : {'masterKey': k, 'password': k};
  }

  Uint8List _pbkdf2(List<int> p, List<int> s, int iter, int len) {
    final mac = crypto.Hmac(crypto.sha512, p);
    final out = Uint8List(len);
    final blocks = (len / 64).ceil();
    for (var i = 1; i <= blocks; i++) {
      var u = mac.convert([
        ...s,
        ...Uint8List(4)..buffer.asByteData().setInt32(0, i, Endian.big)
      ]).bytes;
      var t = Uint8List.fromList(u);
      for (var j = 1; j < iter; j++) {
        u = mac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) t[k] ^= u[k];
      }
      final off = (i - 1) * 64;
      out.setRange(off, off + min(64, len - off), t);
    }
    return out;
  }

  Uint8List _randomBytes(int l) =>
      Uint8List.fromList(List.generate(l, (_) => Random.secure().nextInt(256)));

  String _uuid() {
    final b = _randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = HEX.encode(b);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  String _randomString(int l) => List.generate(
      l,
      (_) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'[
          Random.secure().nextInt(64)]).join();
}

// ============================================================================
// CONFIG SERVICE
// ============================================================================

class ConfigService {
  late final String configDir;
  late final String credentialsFile;
  late final String batchStateDir;
  late final String webdavPidFile; // ADD THIS

  ConfigService({required String configPath}) {
    configDir = configPath;
    credentialsFile = p.join(configDir, 'credentials.json');
    batchStateDir = p.join(configDir, 'batch_states');
    webdavPidFile = p.join(configDir, 'webdav.pid'); // ADD THIS

    try {
      Directory(configDir).createSync(recursive: true);
      Directory(batchStateDir).createSync(recursive: true);
    } catch (e) {
      print("⚠️ Warning: Could not create config directory: $e");
    }
  }

  Future<int?> readWebdavPid() async {
    final file = File(webdavPidFile);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        return int.tryParse(content.trim());
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> saveWebdavPid(int pid) async {
    final file = File(webdavPidFile);
    await file.writeAsString(pid.toString());
  }

  Future<void> clearWebdavPid() async {
    final file = File(webdavPidFile);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String generateBatchId(
      String operationType, List<String> sources, String target) {
    final input = '$operationType-${sources.join('|')}-$target';
    final bytes = utf8.encode(input);
    final digest = crypto.sha1.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  String getBatchStateFilePath(String batchId) {
    return p.join(batchStateDir, 'batch_state_$batchId.json');
  }

  Future<Map<String, dynamic>?> loadBatchState(String batchId) async {
    final filePath = getBatchStateFilePath(batchId);
    final file = File(filePath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      } catch (e) {
        print("⚠️ Could not read batch state: $e");
        await deleteBatchState(batchId);
        return null;
      }
    }
    return null;
  }

  Future<void> saveBatchState(
      String batchId, Map<String, dynamic> state) async {
    final filePath = getBatchStateFilePath(batchId);
    final file = File(filePath);
    try {
      await file.writeAsString(json.encode(state));
    } catch (e) {
      print("⚠️ Could not save batch state: $e");
    }
  }

  Future<void> deleteBatchState(String batchId) async {
    final filePath = getBatchStateFilePath(batchId);
    final file = File(filePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        print("⚠️ Could not delete batch state: $e");
      }
    }
  }

  Future<void> saveCredentials(Map<String, dynamic> d) async {
    await File(credentialsFile).writeAsString(json.encode(d));
  }

  Future<Map<String, dynamic>?> readCredentials() async {
    if (await File(credentialsFile).exists()) {
      return json.decode(await File(credentialsFile).readAsString());
    }
    return null;
  }

  Future<void> clearCredentials() async {
    if (await File(credentialsFile).exists()) {
      await File(credentialsFile).delete();
    }
  }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

String formatSize(dynamic b) {
  int bytes = (b is int) ? b : int.tryParse(b.toString()) ?? 0;
  if (bytes <= 0) return '0 B';
  const s = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  double v = bytes.toDouble();
  while (v >= 1024 && i < s.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(1)} ${s[i]}';
}

String formatDate(dynamic dateValue) {
  if (dateValue == null) return '';
  try {
    if (dateValue is int) {
      final dt = DateTime.fromMillisecondsSinceEpoch(dateValue);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (dateValue is String) {
      if (dateValue.length >= 10) {
        return dateValue.substring(0, 10);
      }
    }
    return dateValue.toString();
  } catch (e) {
    return '';
  }
}
