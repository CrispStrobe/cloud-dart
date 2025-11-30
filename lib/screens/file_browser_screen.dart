// screens/file_browser_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../widgets/file_panel.dart';
import '../widgets/connection_dialog.dart';
import '../widgets/operations_panel.dart';
import '../services/app_state.dart';
import '../models/file_item.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  PanelSide _activePanelMobile = PanelSide.local;
  bool _hasShownPermissionDialog = false;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      appState.initializeReceiving();
      appState.addListener(_onAppStateChanged);
    });
  }

  @override
  void dispose() {
    final appState = context.read<AppState>();
    appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    final appState = context.read<AppState>();
    
    // no longer needed, as AppState already handles asking for permission during initialization now
    /* Show initial permission request dialog
    if (!_hasShownPermissionDialog && 
        appState.lastError != null && 
        appState.lastError!.contains('Please select a base directory')) {
      _hasShownPermissionDialog = true;
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showInitialPermissionDialog(context, appState);
        }
      });
    } */
    
    // Handle received files
    if (appState.receivedFiles.isNotEmpty) {
      _showReceivedFilesDialog(appState.receivedFiles);
      appState.clearReceivedFiles();
    }
  }

  void _showPermissionDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.folder_open, size: 32),
            SizedBox(width: 12),
            Text('Select Folder'),
          ],
        ),
        content: const Text(
          'To browse your files, please select a folder you want to access.\n\n'
          'Due to macOS security, the app cannot access folders without your permission.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Try to use Documents folder as fallback
              final home = Platform.environment['HOME'] ?? '/';
              appState.navigateToPath(PanelSide.local, '$home/Documents');
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Select Folder'),
            onPressed: () {
              Navigator.pop(context);
              appState.pickLocalDirectory();
            },
          ),
        ],
      ),
    );
  }

  void _showInitialPermissionDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, size: 32),
            SizedBox(width: 12),
            Text('Grant Folder Access'),
          ],
        ),
        content: const Text(
          'To browse your files, please select a base folder to grant access to.\n\n'
          'Recommended: Select your Home folder or Documents folder.\n\n'
          'Once granted, you can navigate freely within that folder and its subfolders.',
        ),
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Select Folder'),
            onPressed: () {
              Navigator.pop(context);
              appState.pickLocalDirectory();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
          
          return Scaffold(
            appBar: AppBar(
              title: const Text('Cloud Drive'),
              actions: [
                // Keyboard shortcuts info
                IconButton(
                  icon: const Icon(Icons.keyboard),
                  tooltip: 'Keyboard Shortcuts',
                  onPressed: () => _showKeyboardShortcuts(context),
                ),

                // --- NEW INFO BUTTON ---
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'About this app',
                  onPressed: () => _showAboutDialog(context),
                ),
                // --- END NEW BUTTON ---
                
                const SizedBox(width: 8),
                
                // Connection status
                if (!appState.isConnected)
                  TextButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Connect'),
                    onPressed: () => _showConnectionDialog(context),
                  )
                else
                 Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'logout') {
                        _confirmLogout(context, appState);
                      }
                    },
                    itemBuilder: (context) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appState.userEmail ?? 'User',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Logged in',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 20),
                            SizedBox(width: 12),
                            Text('Logout'),
                          ],
                        ),
                      ),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.account_circle, size: 20),
                      label: Text(
                        appState.userEmail ?? 'Connected',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: Focus(
              autofocus: true,
              onKeyEvent: (node, event) => _handleKeyEvent(context, appState, event),
              child: Column(
                children: [
                  // Main content area with panels
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWideScreen = constraints.maxWidth > 800;
                        
                        if (isWideScreen) {
                          // Two-column layout for wider screens
                          return Row(
                            children: [
                              // Left panel (Local)
                              Expanded(
                                child: FilePanel(
                                  side: PanelSide.local,
                                  isActive: appState.activePanel == PanelSide.local,
                                  onTap: () => appState.setActivePanel(PanelSide.local),
                                ),
                              ),
                              // Divider
                              Container(
                                width: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                              // Right panel (Remote)
                              Expanded(
                                child: FilePanel(
                                  side: PanelSide.remote,
                                  isActive: appState.activePanel == PanelSide.remote,
                                  onTap: () => appState.setActivePanel(PanelSide.remote),
                                ),
                              ),
                            ],
                          );
                        } else {
                          // Single panel for smaller screens with tab switcher
                          return Column(
                            children: [
                              // Panel switcher tabs
                              Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceVariant,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _PanelTab(
                                        label: 'Local',
                                        icon: Icons.folder,
                                        isActive: _activePanelMobile == PanelSide.local,
                                        onTap: () {
                                          setState(() => _activePanelMobile = PanelSide.local);
                                          appState.setActivePanel(PanelSide.local);
                                        },
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 40,
                                      color: Theme.of(context).dividerColor,
                                    ),
                                    Expanded(
                                      child: _PanelTab(
                                        label: 'Remote',
                                        icon: Icons.cloud,
                                        isActive: _activePanelMobile == PanelSide.remote,
                                        enabled: appState.isConnected,
                                        onTap: () {
                                          if (appState.isConnected) {
                                            setState(() => _activePanelMobile = PanelSide.remote);
                                            appState.setActivePanel(PanelSide.remote);
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Please connect to access remote files'),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Active panel
                              Expanded(
                                child: FilePanel(
                                  side: _activePanelMobile,
                                  isActive: true,
                                  onTap: () {},
                                ),
                              ),
                            ],
                          );
                        }
                      },
                    ),
                  ),
                  
                  // Operations panel at bottom
                  const OperationsPanel(),
                  
                  // Status bar showing operation count when panel is hidden
                  /* if (appState.hasActiveOperations)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${appState.operations.where((op) => !op.isComplete).length} operation(s) in progress...',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              // This will force the operations panel to rebuild and show
                              setState(() {});
                            },
                            child: const Text('Show Details'),
                          ),
                        ],
                      ),
                    ), */
                ], 
              ),
            ),
            
            // Floating action buttons
            // floatingActionButton: _buildFAB(context, appState),
            
            // Drawer for mobile (optional)
            drawer: MediaQuery.of(context).size.width <= 800
                ? _buildDrawer(context, appState)
                : null,
          );
        }
      
    
  

  Widget _buildDrawer(BuildContext context, AppState appState) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.cloud,
                  size: 48,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  'Cloud Drive',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                if (appState.isConnected) ...[
                  const SizedBox(height: 4),
                  Text(
                    appState.userEmail ?? 'Connected',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!appState.isConnected)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Connect to Cloud'),
              onTap: () {
                Navigator.pop(context);
                _showConnectionDialog(context);
              },
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.sync_alt),
              title: const Text('Operations'),
              subtitle: appState.operations.isEmpty
                  ? const Text('No active operations')
                  : Text('${appState.operations.length} operation(s)'),
              onTap: () {
                Navigator.pop(context);
                if (appState.operations.isNotEmpty) {
                  _showOperationsMenu(context, appState);
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh All'),
              onTap: () {
                Navigator.pop(context);
                appState.refreshPanel(PanelSide.local);
                appState.refreshPanel(PanelSide.remote);
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Clear Selections'),
              onTap: () {
                Navigator.pop(context);
                appState.clearSelection(PanelSide.local);
                appState.clearSelection(PanelSide.remote);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: const Text('Keyboard Shortcuts'),
              onTap: () {
                Navigator.pop(context);
                _showKeyboardShortcuts(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                _showAboutDialog(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Logout',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmLogout(context, appState);
              },
            ),
          ],
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout from Cloud?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await appState.logout();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logged out successfully')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // --- UPDATED ABOUT DIALOG ---
  void _showAboutDialog(BuildContext context) {
    final githubUrl = Uri.parse('https://github.com/CrispStrobe/dart-cloud');

    showAboutDialog(
      context: context,
      applicationName: 'Cloud Drive (Unofficial Client)',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.cloud, size: 48),
      applicationLegalese: '© 2025 CrispStrobe\nThis app is not affiliated with Filen.io or Internxt, Inc.',
      children: [
        const Text(
          'This is an unofficial, open-source client for Filen.io and Internxt Drive, built with Flutter and Dart.',
        ),
        const SizedBox(height: 24),
        const Text(
          'Author / Impressum:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'CrispStrobe',
        ),
        const SizedBox(height: 16),
        const Text(
          'Source Code on GitHub:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        InkWell(
          child: Text(
            githubUrl.toString(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
          onTap: () async {
            if (await canLaunchUrl(githubUrl)) {
              await launchUrl(githubUrl);
            }
          },
        ),
      ],
    );
  }
  // --- END UPDATED DIALOG ---

  KeyEventResult _handleKeyEvent(BuildContext context, AppState appState, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.isControlPressed || 
                   HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Ctrl+A - Select All
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      appState.selectAll(appState.activePanel);
      return KeyEventResult.handled;
    }

    // Escape - Clear selection
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      appState.clearSelection(appState.activePanel);
      return KeyEventResult.handled;
    }

    // Delete - Delete selected files
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      _confirmDeleteSelected(context, appState);
      return KeyEventResult.handled;
    }

    // F2 - Rename (if single file selected)
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      _renameSelected(context, appState);
      return KeyEventResult.handled;
    }

    // Ctrl+C - Copy
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      _showCopyDialog(context, appState);
      return KeyEventResult.handled;
    }

    // Ctrl+X - Move
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyX) {
      _showMoveDialog(context, appState);
      return KeyEventResult.handled;
    }

    // Ctrl+N - New folder
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyN) {
      _showCreateFolderDialog(context, appState, appState.activePanel);
      return KeyEventResult.handled;
    }

    // Ctrl+R or F5 - Refresh
    if ((isCtrl && event.logicalKey == LogicalKeyboardKey.keyR) ||
        event.logicalKey == LogicalKeyboardKey.f5) {
      appState.refreshPanel(appState.activePanel);
      return KeyEventResult.handled;
    }

    // Backspace - Navigate up
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      appState.navigateUp(appState.activePanel);
      return KeyEventResult.handled;
    }

    // Tab - Switch panels
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final newPanel = appState.activePanel == PanelSide.local 
          ? PanelSide.remote 
          : PanelSide.local;
      appState.setActivePanel(newPanel);
      if (MediaQuery.of(context).size.width <= 800) {
        setState(() => _activePanelMobile = newPanel);
      }
      return KeyEventResult.handled;
    }

    // Ctrl+U - Upload
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyU && appState.isConnected) {
      _uploadSelected(context, appState);
      return KeyEventResult.handled;
    }

    // Ctrl+D - Download
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyD && appState.isConnected) {
      _downloadSelected(context, appState);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildFAB(BuildContext context, AppState appState) {
    if (!appState.isConnected) {
      return FloatingActionButton.extended(
        onPressed: () => _showConnectionDialog(context),
        icon: const Icon(Icons.cloud_off),
        label: const Text('Connect'),
      );
    }

    final hasLocalSelection = appState.localSelection.isNotEmpty;
    final hasRemoteSelection = appState.remoteSelection.isNotEmpty;
    final isWideScreen = MediaQuery.of(context).size.width > 800;

    // No selection - show options menu
    if (!hasLocalSelection && !hasRemoteSelection) {
      return FloatingActionButton(
        onPressed: () => _showOperationsMenu(context, appState),
        tooltip: 'Operations',
        child: const Icon(Icons.more_horiz),
      );
    }

    // Has selection - show transfer buttons
    if (isWideScreen && hasLocalSelection && hasRemoteSelection) {
      // Both panels have selections - show both buttons
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'upload',
            onPressed: () => _uploadSelected(context, appState),
            tooltip: 'Upload ${appState.localSelection.length} item(s)',
            child: Badge(
              label: Text('${appState.localSelection.length}'),
              child: const Icon(Icons.upload),
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'download',
            onPressed: () => _downloadSelected(context, appState),
            tooltip: 'Download ${appState.remoteSelection.length} item(s)',
            child: Badge(
              label: Text('${appState.remoteSelection.length}'),
              child: const Icon(Icons.download),
            ),
          ),
        ],
      );
    } else if (hasLocalSelection) {
      // Only local selection
      return FloatingActionButton.extended(
        heroTag: 'upload',
        onPressed: () => _uploadSelected(context, appState),
        icon: const Icon(Icons.upload),
        label: Text('Upload (${appState.localSelection.length})'),
      );
    } else if (hasRemoteSelection) {
      // Only remote selection
      return FloatingActionButton.extended(
        heroTag: 'download',
        onPressed: () => _downloadSelected(context, appState),
        icon: const Icon(Icons.download),
        label: Text('Download (${appState.remoteSelection.length})'),
      );
    }

    return const SizedBox.shrink();
  }

  void _showConnectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ConnectionDialog(),
    );
  }

  void _showUserMenu(BuildContext context, AppState appState) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>( // Add type parameter here
      context: context,
      position: position,
      items: <PopupMenuEntry<String>>[ // Add type annotation HERE!
        PopupMenuItem<String>(
          enabled: false,
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(appState.userEmail ?? 'User'),
            subtitle: const Text('Logged in'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: const ListTile(
            leading: Icon(Icons.logout),
            title: Text('Logout'),
          ),
          onTap: () => Future.delayed(Duration.zero, () {
            appState.logout();
          }),
        ),
      ],
    );
  }

  void _showOperationsMenu(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.upload),
              title: const Text('Upload Selected to Remote'),
              subtitle: Text('${appState.localSelection.length} item(s)'),
              enabled: appState.localSelection.isNotEmpty,
              onTap: () {
                Navigator.pop(context);
                _uploadSelected(context, appState);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download Selected to Local'),
              subtitle: Text('${appState.remoteSelection.length} item(s)'),
              enabled: appState.remoteSelection.isNotEmpty,
              onTap: () {
                Navigator.pop(context);
                _downloadSelected(context, appState);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.select_all),
              title: const Text('Select All (Ctrl+A)'),
              onTap: () {
                Navigator.pop(context);
                appState.selectAll(appState.activePanel);
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh (F5)'),
              onTap: () {
                Navigator.pop(context);
                appState.refreshPanel(appState.activePanel);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showKeyboardShortcuts(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keyboard Shortcuts'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shortcutRow('Ctrl+A', 'Select all'),
              _shortcutRow('Escape', 'Clear selection'),
              _shortcutRow('Delete', 'Delete selected'),
              _shortcutRow('F2', 'Rename'),
              _shortcutRow('Ctrl+C', 'Copy to...'),
              _shortcutRow('Ctrl+X', 'Move to...'),
              _shortcutRow('Ctrl+N', 'New folder'),
              _shortcutRow('Ctrl+R / F5', 'Refresh'),
              _shortcutRow('Backspace', 'Navigate up'),
              _shortcutRow('Tab', 'Switch panels'),
              _shortcutRow('Ctrl+U', 'Upload'),
              _shortcutRow('Ctrl+D', 'Download'),
              _shortcutRow('Enter', 'Open folder'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _shortcutRow(String keys, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              keys,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(child: Text(description)),
        ],
      ),
    );
  }

  void _uploadSelected(BuildContext context, AppState appState) {
    if (appState.localSelection.isEmpty) return;
    appState.uploadFiles(appState.localSelection.toList());
  }

  void _downloadSelected(BuildContext context, AppState appState) {
    if (appState.remoteSelection.isEmpty) return;
    appState.downloadFiles(appState.remoteSelection.toList());
  }

  void _confirmDeleteSelected(BuildContext context, AppState appState) {
    final panel = appState.activePanel;
    final selection = panel == PanelSide.local 
        ? appState.localSelection 
        : appState.remoteSelection;
    
    if (selection.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete ${selection.length} item(s)? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await appState.deleteFiles(panel, selection.toList());
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _renameSelected(BuildContext context, AppState appState) {
    final panel = appState.activePanel;
    final selection = panel == PanelSide.local 
        ? appState.localSelection 
        : appState.remoteSelection;
    
    if (selection.length != 1) return;

    final file = selection.first;
    final controller = TextEditingController(text: file.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            if (value.isNotEmpty && value != file.name) {
              await appState.renameFile(panel, file, value);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty && controller.text != file.name) {
                await appState.renameFile(panel, file, controller.text);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showCopyDialog(BuildContext context, AppState appState) {
    final panel = appState.activePanel;
    final selection = panel == PanelSide.local 
        ? appState.localSelection 
        : appState.remoteSelection;
    
    if (selection.isEmpty) return;

    _showPathDialog(
      context,
      appState,
      selection.toList(),
      'Copy',
      appState.copyFiles,
    );
  }

  void _showMoveDialog(BuildContext context, AppState appState) {
    final panel = appState.activePanel;
    final selection = panel == PanelSide.local 
        ? appState.localSelection 
        : appState.remoteSelection;
    
    if (selection.isEmpty) return;

    _showPathDialog(
      context,
      appState,
      selection.toList(),
      'Move',
      appState.moveFiles,
    );
  }

  void _showPathDialog(
    BuildContext context,
    AppState appState,
    List<FileItem> files,
    String operation,
    Future<void> Function(PanelSide, List<FileItem>, String) action,
  ) {
    final panel = appState.activePanel;
    final controller = TextEditingController(
      text: panel == PanelSide.local ? appState.localPath : appState.remotePath,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$operation ${files.length} item(s)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Target path',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            if (value.isNotEmpty) {
              await action(panel, files, value);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await action(panel, files, controller.text);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text(operation),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context, AppState appState, PanelSide side) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            if (value.isNotEmpty) {
              await appState.createFolder(side, value);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // --- FIX ---
              // Was: if (controller.text.isNotEmpty) {
              //        await appState.createFolder(side, value); ...
              // Should be:
              if (controller.text.isNotEmpty) {
                await appState.createFolder(side, controller.text);
              // --- END FIX ---
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showReceivedFilesDialog(List<String> files) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Received Files'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upload ${files.length} file(s) to Cloud?'),
            const SizedBox(height: 8),
            ...files.take(5).map((path) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• ${p.basename(path)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )),
            if (files.length > 5)
              Text(
                '... and ${files.length - 5} more',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final appState = context.read<AppState>();
              final items = files.map((path) => FileItem(
                name: p.basename(path),
                path: path,
                isFolder: Directory(path).existsSync(),
              )).toList();
              await appState.uploadFiles(items);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final bool enabled;

  const _PanelTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive 
                  ? Theme.of(context).colorScheme.primary 
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: !enabled
                  ? Theme.of(context).disabledColor
                  : isActive 
                      ? Theme.of(context).colorScheme.primary 
                      : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: !enabled
                    ? Theme.of(context).disabledColor
                    : isActive 
                        ? Theme.of(context).colorScheme.primary 
                        : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum PanelSide { local, remote }