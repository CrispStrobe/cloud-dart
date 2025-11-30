// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/file_browser_screen.dart';
import 'services/app_state.dart';
import 'services/cloud_storage_interface.dart'; //
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'services/filen_config_service.dart';
import 'services/internxt_client.dart' show ConfigService; //

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Determine the platform-specific config path
  String configPath;
  if (kIsWeb) {
    configPath = '/.cloud-storage-config-web';
  } else if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getApplicationSupportDirectory();
    configPath = p.join(dir.path, '.cloud-storage-config');
  } else {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    configPath = p.join(home, '.cloud-storage-config');
  }

  // Determine which provider to use
  CloudProvider defaultProvider = await _getDefaultProvider();

  // ROBUSTNESS CHECK: If Internxt is selected but disabled via flag, force Filen
  if (defaultProvider == CloudProvider.internxt && !CloudStorageFactory.isInternxtSupported) {
    print('⚠️ Internxt preference detected but provider is disabled. Forcing Filen.');
    defaultProvider = CloudProvider.filen;
  }
  
  // Create the appropriate config service based on provider
  final configService = await _createConfigService(configPath, defaultProvider);
  
  runApp(MyApp(
    configService: configService,
    initialProvider: defaultProvider,
  ));
}

// Helper to determine default provider from saved preference
Future<CloudProvider> _getDefaultProvider() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final providerName = prefs.getString('cloud_provider');
    
    if (providerName == null) {
      print('📂 No saved provider preference, defaulting to Filen');
      return CloudProvider.filen;
    }
    
    switch (providerName.toLowerCase()) {
      case 'filen':
        print('✅ Using saved provider: Filen');
        return CloudProvider.filen;
      case 'internxt':
        print('✅ Using saved provider: Internxt');
        return CloudProvider.internxt;
      default:
        print('⚠️ Unknown provider: $providerName, defaulting to Filen');
        return CloudProvider.filen;
    }
  } catch (e) {
    print('⚠️ Error reading provider preference: $e, defaulting to Filen');
    return CloudProvider.filen;
  }
}

// Helper to create appropriate config service
Future<dynamic> _createConfigService(String configPath, CloudProvider provider) async {
  // ROBUSTNESS: Wrap creation in try/catch to handle missing dependencies or logic errors
  try {
    switch (provider) {
      case CloudProvider.filen:
        print('🔧 Creating Filen config service');
        return FilenConfigService(configPath: configPath);
      case CloudProvider.internxt:
        // Only attempt to create if supported
        if (CloudStorageFactory.isInternxtSupported) {
          print('🔧 Creating Internxt config service');
          return ConfigService(configPath: configPath);
        } else {
           print('⚠️ Internxt config requested but disabled. Falling back to Filen config.');
           return FilenConfigService(configPath: configPath);
        }
    }
  } catch (e) {
    print('❌ Critical error creating config service: $e');
    print('   Falling back to Filen defaults.');
    return FilenConfigService(configPath: configPath);
  }
}

class MyApp extends StatelessWidget {
  final dynamic configService;
  final CloudProvider initialProvider;
  
  const MyApp({
    super.key, 
    required this.configService,
    required this.initialProvider,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(
        config: configService,
        initialProvider: initialProvider,
      ),
      child: MaterialApp(
        title: 'Cloud Storage Manager',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const FileBrowserScreen(),
      ),
    );
  }
}