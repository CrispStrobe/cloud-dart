// widgets/file_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
// --- FIX: Conditional import for dart:io ---
import 'dart:io' if (dart.library.html) 'dart:html' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb; // Import kIsWeb
// --- END FIX ---
import '../services/app_state.dart';
import '../models/file_item.dart';
import 'package:provider/provider.dart';
import '../screens/file_browser_screen.dart';
import 'package:path/path.dart' as p; 

class FilePanel extends StatefulWidget {
  final PanelSide side;
  final bool isActive;
  final VoidCallback onTap;

  const FilePanel({
    super.key,
    required this.side,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<FilePanel> createState() => _FilePanelState();
}

class _FilePanelState extends State<FilePanel> {
  bool _isDragging = false;
  late final ScrollController _scrollController; 

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(); 
  }

  @override
  void dispose() {
    _scrollController.dispose(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final appState = context.watch<AppState>();

    // Show error if present
    if (appState.lastError != null && widget.side == PanelSide.local) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appState.lastError!),
              action: SnackBarAction(
                label: 'Browse',
                onPressed: () => appState.pickLocalDirectory(),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      });
    }

    // --- FIX: Use new getter 'localFileItems' ---
    final files = widget.side == PanelSide.local ? appState.localFileItems : appState.remoteFiles;
    // --- END FIX ---
    
    final currentPath = widget.side == PanelSide.local ? appState.localPath : appState.remotePath;
    final selection = widget.side == PanelSide.local ? appState.localSelection : appState.remoteSelection;

    // --- Scroll logic ---
    FileItem? itemToScroll = appState.itemToScrollTo;

    if (itemToScroll != null && files != null) {
      final index = files.indexWhere((f) => 
        (f.uuid != null && f.uuid == itemToScroll.uuid) || 
        (f.path != null && f.path == itemToScroll.path)
      );
      
      if (index != -1) {
        bool belongsToPanel = (widget.side == PanelSide.local && itemToScroll.path != null && itemToScroll.path!.startsWith(appState.localPath)) || 
                              (widget.side == PanelSide.remote && itemToScroll.uuid != null && (itemToScroll.path ?? '/').startsWith(appState.remotePath));
        
        if (belongsToPanel) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final offset = index * 56.0;
              _scrollController.animateTo(
                offset,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
              appState.clearItemToScrollTo(); 
            }
          });
        }
      } else {
        appState.clearItemToScrollTo();
      }
    }
    // --- End scroll logic ---

    // --- FIX: Handle web local panel ---
    if (kIsWeb && widget.side == PanelSide.local) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.web_asset_off, size: 64, color: Colors.grey[700]),
              const SizedBox(height: 16),
              Text(
                'Local file browsing is not supported on Web.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }
    // --- END FIX ---

    return GestureDetector(
      onTap: widget.onTap,
      // --- FIX: Disable drop target on web ---
      child: kIsWeb ? _buildPanelContent(context, appState, files, currentPath, selection) : DropTarget(
      // --- END FIX ---
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (details) async {
          setState(() => _isDragging = false);
          if (widget.side == PanelSide.remote && appState.isConnected) {
            final items = details.files.map((xFile) => FileItem(
              name: xFile.name,
              path: xFile.path,
              isFolder: false,
            )).toList();
            await appState.uploadFiles(items);
          }
        },
        child: _buildPanelContent(context, appState, files, currentPath, selection),
      ),
    );
  }

  // --- NEW: Extracted panel content ---
  Widget _buildPanelContent(BuildContext context, AppState appState, List<FileItem>? files, String currentPath, Set<FileItem> selection) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isActive ? null : Colors.black.withOpacity(0.02),
        border: _isDragging 
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        children: [
          _buildHeader(context, appState, currentPath),
          if (currentPath != '/' && currentPath != '')
            _buildBreadcrumbs(context, appState, currentPath),
          if (selection.isNotEmpty)
            _buildSelectionBar(context, appState, selection),
          Expanded(
            child: files == null
                ? const Center(child: CircularProgressIndicator())
                : files.isEmpty
                    ? Center(
                        child: _isDragging && widget.side == PanelSide.remote
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.upload_file,
                                    size: 64,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Drop files here to upload',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              )
                            : const Text('Empty folder'),
                      )
                    : _buildFileList(context, appState, files),
          ),
        ],
      ),
    );
  }
  // --- END NEW ---

  Widget _buildHeader(BuildContext context, AppState appState, String currentPath) {
    final sortBy = appState.getSort(widget.side);
    final sortOrder = appState.getSortOrder(widget.side);
    
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(
            widget.side == PanelSide.local ? Icons.folder : Icons.cloud,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              currentPath,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          
          if (widget.side == PanelSide.local)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Browse...',
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: () => appState.pickLocalDirectory(),
            ),
          
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Up (Backspace)',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            onPressed: () => appState.navigateUp(widget.side),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh (F5)',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            onPressed: () => appState.refreshPanel(widget.side),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'New Folder (Ctrl+N)',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            onPressed: () => _showCreateFolderDialog(context, appState),
          ),
          
          if (widget.side == PanelSide.remote && appState.isConnected) ...[
            IconButton(
              icon: appState.isSearching 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : const Icon(Icons.search),
              tooltip: 'Fuzzy search all files',
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: appState.isSearching ? null : () => _showSearchDialog(context, appState),
            ),
            IconButton(
              icon: appState.isSearching
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.find_in_page),
              tooltip: 'Find files by pattern in this folder (e.g. *.pdf)',
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: appState.isSearching ? null : () => _showFindDialog(context, appState),
            ),
          ],

          PopupMenuButton<String>(
            icon: Icon(
              Icons.sort,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            tooltip: 'Sort',
            onSelected: (value) => _handleSortMenuAction(context, appState, value),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'name',
                child: Row(
                  children: [
                    Icon(
                      sortBy == SortBy.name ? Icons.check : Icons.sort_by_alpha,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Name'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'size',
                child: Row(
                  children: [
                    Icon(
                      sortBy == SortBy.size ? Icons.check : Icons.data_usage,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Size'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'date',
                child: Row(
                  children: [
                    Icon(
                      sortBy == SortBy.date ? Icons.check : Icons.access_time,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Date'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'extension',
                child: Row(
                  children: [
                    Icon(
                      sortBy == SortBy.extension ? Icons.check : Icons.category,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Extension'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'toggle_order',
                child: Row(
                  children: [
                    Icon(
                      sortOrder == SortOrder.ascending 
                          ? Icons.arrow_upward 
                          : Icons.arrow_downward,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      sortOrder == SortOrder.ascending 
                          ? 'Ascending' 
                          : 'Descending',
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'select_all',
                child: Row(
                  children: [
                    Icon(Icons.select_all),
                    SizedBox(width: 8),
                    Text('Select All'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'clear_selection',
                child: Row(
                  children: [
                    Icon(Icons.clear),
                    SizedBox(width: 8),
                    Text('Clear Selection'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleSortMenuAction(BuildContext context, AppState appState, String action) {
    switch (action) {
      case 'name':
        appState.setSortBy(widget.side, SortBy.name);
        break;
      case 'size':
        appState.setSortBy(widget.side, SortBy.size);
        break;
      case 'date':
        appState.setSortBy(widget.side, SortBy.date);
        break;
      case 'extension':
        appState.setSortBy(widget.side, SortBy.extension);
        break;
      case 'toggle_order':
        appState.toggleSortOrder(widget.side);
        break;
      case 'select_all':
        appState.selectAll(widget.side);
        break;
      case 'clear_selection':
        appState.clearSelection(widget.side);
        break;
    }
  }

  Widget _buildBreadcrumbs(BuildContext context, AppState appState, String currentPath) {
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS && widget.side == PanelSide.local && currentPath.contains('Containers')) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber,
              size: 16,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              'Sandboxed path - Use Browse button to select a real folder',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      );
    }
    
    List<Map<String, String>> breadcrumbs = [];
    
    if (widget.side == PanelSide.local) {
      // For local paths
      if (!kIsWeb && Platform.isWindows) {
        final parts = currentPath.split('\\');
        String accumulated = '';
        
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty) continue;
          
          accumulated = i == 0 
              ? parts[i]  
              : '$accumulated\\${parts[i]}';
          
          breadcrumbs.add({
            'name': parts[i],
            'path': accumulated,
          });
        }
      } else {
        final parts = currentPath.split('/');
        String accumulated = '';
        
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty && i != 0) continue; 
          
          if (i == 0) {
            breadcrumbs.add({
              'name': '/',
              'path': '/',
            });
            accumulated = '';
          } else {
            accumulated = accumulated.isEmpty 
                ? '/${parts[i]}' 
                : '$accumulated/${parts[i]}';
            
            breadcrumbs.add({
              'name': parts[i],
              'path': accumulated,
            });
          }
        }
      }
    } else {
      // For remote paths
      if (currentPath == '/') {
        breadcrumbs.add({
          'name': '/',
          'path': '/',
        });
      } else {
        final parts = currentPath.split('/');
        String accumulated = '';
        
        breadcrumbs.add({
          'name': '/',
          'path': '/',
        });
        
        for (int i = 1; i < parts.length; i++) {
          if (parts[i].isEmpty) continue;
          
          accumulated = accumulated.isEmpty 
              ? '/${parts[i]}' 
              : '$accumulated/${parts[i]}';
          
          breadcrumbs.add({
            'name': parts[i],
            'path': accumulated,
          });
        }
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          InkWell(
            onTap: () {
              if (widget.side == PanelSide.local) {
                if (!kIsWeb) {
                  appState.navigateToPath(PanelSide.local, Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/');
                }
              } else {
                appState.navigateToPath(PanelSide.remote, '/');
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(
                Icons.home,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          
          ...breadcrumbs.asMap().entries.map((entry) {
            final index = entry.key;
            final crumb = entry.value;
            final isLast = index == breadcrumbs.length - 1;
            
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                InkWell(
                  onTap: isLast ? null : () {
                    print('🔗 Breadcrumb clicked: ${crumb['name']} -> ${crumb['path']}');
                    appState.navigateToPath(widget.side, crumb['path']!);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      crumb['name']!,
                      style: TextStyle(
                        color: isLast 
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context, AppState appState, Set<FileItem> selection) {
    final totalSize = selection.fold<int>(
      0,
      (sum, file) => sum + (file.size ?? 0),
    );
    final files = selection.toList(); // For actions
    final theme = Theme.of(context);

    // Helper widget for responsive buttons
    Widget responsiveButton({
      required IconData icon,
      required String label,
      required String tooltip,
      required VoidCallback onPressed,
      required bool showLabel,
    }) {
      if (showLabel) {
        return TextButton.icon(
          icon: Icon(icon, size: 18),
          label: Text(label),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSecondaryContainer,
          ),
        );
      } else {
        return IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tooltip,
          color: theme.colorScheme.onSecondaryContainer,
          onPressed: onPressed,
        );
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.secondaryContainer,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Show labels if the bar is wide enough
          final bool showLabels = constraints.maxWidth > 450;
          
          return Row(
            children: [
              Icon(
                Icons.check_circle,
                size: 20,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                '${selection.length} selected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              if (totalSize > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '• ${_formatBytes(totalSize)}',
                  style: TextStyle(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
              const SizedBox(width: 16),

              // --- RESPONSIVE BUTTONS ---
              if (widget.side == PanelSide.local && appState.isConnected)
                responsiveButton(
                  icon: Icons.upload,
                  label: 'Upload',
                  tooltip: 'Upload',
                  showLabel: showLabels,
                  onPressed: () => appState.uploadFiles(files),
                ),
              
              if (widget.side == PanelSide.remote)
                responsiveButton(
                  icon: Icons.download,
                  label: 'Download',
                  tooltip: 'Download',
                  showLabel: showLabels,
                  onPressed: () => appState.downloadFiles(files),
                ),
              
              if (showLabels) const SizedBox(width: 8),

              // Other actions as icons
              IconButton(
                icon: const Icon(Icons.content_copy, size: 20),
                tooltip: 'Copy to...',
                color: theme.colorScheme.onSecondaryContainer,
                onPressed: () => _showCopyDialog(context, appState, files),
              ),
              IconButton(
                icon: const Icon(Icons.drive_file_move, size: 20),
                tooltip: 'Move to...',
                color: theme.colorScheme.onSecondaryContainer,
                onPressed: () => _showMoveDialog(context, appState, files),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                tooltip: 'Delete',
                color: theme.colorScheme.onSecondaryContainer,
                onPressed: () => _confirmDelete(context, appState, files),
              ),
              // --- END RESPONSIVE BUTTONS ---

              const Spacer(),
              responsiveButton(
                icon: Icons.clear,
                label: 'Clear',
                tooltip: 'Clear selection',
                showLabel: showLabels,
                onPressed: () => appState.clearSelection(widget.side),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFileList(BuildContext context, AppState appState, List<FileItem> files) {
    try {
      if (files.isEmpty) {
        return const Center(
          child: Text('Empty folder'),
        );
      }

      return ListView.builder(
        controller: _scrollController, // Assign controller
        itemCount: files.length,
        itemBuilder: (context, index) {
          try {
            final file = files[index];
            final isSelected = appState.isSelected(widget.side, file);
            
            return _FileListTile(
              file: file,
              side: widget.side,
              isSelected: isSelected,
              onTap: (shiftKey, ctrlKey) {
                appState.toggleSelection(widget.side, file, shiftKey: shiftKey, ctrlKey: ctrlKey);
              },
              onDoubleTap: () => appState.navigateInto(widget.side, file),
              onSecondaryTap: (details) => _showContextMenu(context, appState, file, details.globalPosition),
            );
          } catch (e) {
            print('Error building file tile at index $index: $e');
            return ListTile(
              title: Text('Error loading item: $e'),
              leading: const Icon(Icons.error, color: Colors.red),
            );
          }
        },
      );
    } catch (e, stackTrace) {
      print('Error building file list: $e');
      print('Stack trace: $stackTrace');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error loading files: $e'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => appState.refreshPanel(widget.side),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
  }

  void _handleHeaderMenuAction(BuildContext context, AppState appState, String action) {
    switch (action) {
      case 'select_all':
        appState.selectAll(widget.side);
        break;
      case 'clear_selection':
        appState.clearSelection(widget.side);
        break;
      case 'sort_name':
      case 'sort_date':
      case 'sort_size':
        // TODO: Implement sorting
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sorting by ${action.split('_')[1]} - Coming soon')),
        );
        break;
    }
  }

  void _showContextMenu(BuildContext context, AppState appState, FileItem file, Offset position) {
    final selection = widget.side == PanelSide.local 
        ? appState.localSelection 
        : appState.remoteSelection;
    
    final files = selection.contains(file) && selection.isNotEmpty
        ? selection.toList()
        : [file];
    
    if (!selection.contains(file)) {
      appState.clearSelection(widget.side);
      appState.toggleSelection(widget.side, file);
    }

    final isMultiSelect = files.length > 1;
    final isSingleFolder = files.length == 1 && files.first.isFolder;

    // Build items list dynamically
    final items = <PopupMenuEntry<dynamic>>[];

    // Open (folders only)
    if (isSingleFolder) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.folder_open),
              SizedBox(width: 8),
              Text('Open'),
            ],
          ),
          onTap: () => Future.delayed(
            Duration.zero,
            () => appState.navigateInto(widget.side, file),
          ),
        ),
      );
    }

    // Upload to Remote
    if (widget.side == PanelSide.local && appState.isConnected) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.upload),
              const SizedBox(width: 8),
              Text('Upload${isMultiSelect ? ' (${files.length})' : ''}'),
            ],
          ),
          onTap: () => Future.delayed(
            Duration.zero,
            () => appState.uploadFiles(files),
          ),
        ),
      );
    }

    // Download to Local
    if (widget.side == PanelSide.remote) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.download),
              const SizedBox(width: 8),
              Text('Download${isMultiSelect ? ' (${files.length})' : ''}'),
            ],
          ),
          onTap: () => Future.delayed(
            Duration.zero,
            () => appState.downloadFiles(files),
          ),
        ),
      );
    }

    // Share (mobile platforms only)
    if ((Platform.isAndroid || Platform.isIOS) && widget.side == PanelSide.local) {
      items.add(
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.share),
              const SizedBox(width: 8),
              Text('Share${isMultiSelect ? ' (${files.length})' : ''}'),
            ],
          ),
          onTap: () => Future.delayed(
            Duration.zero,
            () => appState.shareFiles(files),
          ),
        ),
      );
    }

    // Divider
    if ((widget.side == PanelSide.local && appState.isConnected) || 
        widget.side == PanelSide.remote) {
      items.add(const PopupMenuDivider());
    }

    // Copy to...
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.content_copy),
            const SizedBox(width: 8),
            Text('Copy to...${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => _showCopyDialog(context, appState, files),
        ),
      ),
    );

    // Move to...
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.drive_file_move),
            const SizedBox(width: 8),
            Text('Move to...${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => _showMoveDialog(context, appState, files),
        ),
      ),
    );

    // Rename (single item only)
    if (!isMultiSelect) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.edit),
              const SizedBox(width: 8),
              Text('Rename (F2)'),
            ],
          ),
          onTap: () => Future.delayed(
            Duration.zero,
            () => _showRenameDialog(context, appState, file),
          ),
        ),
      );
    }

    items.add(const PopupMenuDivider());

    // Properties / Info
    if (!isMultiSelect) {
      items.add(
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.info_outline),
              SizedBox(width: 8),
              Text('Properties'),
            ],
          ),
          onTap: () => Future.delayed(
            Duration.zero,
            () => _showPropertiesDialog(context, file),
          ),
        ),
      );
    }

    items.add(const PopupMenuDivider());

    // Delete
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(
              'Delete${isMultiSelect ? ' (${files.length})' : ''}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => _confirmDelete(context, appState, files),
        ),
      ),
    );

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: items,
    );
  }

  void _showCreateFolderDialog(BuildContext context, AppState appState) {
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
            prefixIcon: Icon(Icons.folder),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            if (value.isNotEmpty) {
              await appState.createFolder(widget.side, value);
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
                await appState.createFolder(widget.side, controller.text);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, AppState appState, FileItem file) {
    final controller = TextEditingController(text: file.name);
    
    // Select filename without extension
    final dotIndex = file.name.lastIndexOf('.');
    if (dotIndex > 0 && !file.isFolder) {
      controller.selection = TextSelection(baseOffset: 0, extentOffset: dotIndex);
    } else {
      controller.selection = TextSelection(baseOffset: 0, extentOffset: file.name.length);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'New name',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(file.isFolder ? Icons.folder : Icons.insert_drive_file),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            if (value.isNotEmpty && value != file.name) {
              await appState.renameFile(widget.side, file, value);
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
                await appState.renameFile(widget.side, file, controller.text);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showCopyDialog(BuildContext context, AppState appState, List<FileItem> files) {
    _showPathDialog(context, appState, files, 'Copy', appState.copyFiles);
  }

  void _showMoveDialog(BuildContext context, AppState appState, List<FileItem> files) {
    _showPathDialog(context, appState, files, 'Move', appState.moveFiles);
  }

  void _showPathDialog(
    BuildContext context,
    AppState appState,
    List<FileItem> files,
    String operation,
    Future<void> Function(PanelSide, List<FileItem>, String) action,
  ) {
    final controller = TextEditingController(
      text: widget.side == PanelSide.local ? appState.localPath : appState.remotePath,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$operation ${files.length} item(s)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Items:',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            ...files.take(3).map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    f.isFolder ? Icons.folder : Icons.insert_drive_file,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            )),
            if (files.length > 3)
              Text(
                '... and ${files.length - 3} more',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Target path',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder_open),
              ),
              autofocus: true,
              onSubmitted: (value) async {
                if (value.isNotEmpty) {
                  await action(widget.side, files, value);
                  if (context.mounted) Navigator.pop(context);
                }
              },
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
              if (controller.text.isNotEmpty) {
                await action(widget.side, files, controller.text);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text(operation),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState appState, List<FileItem> files) {
    final totalSize = files.fold<int>(0, (sum, file) => sum + (file.size ?? 0));
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning,
          color: Theme.of(context).colorScheme.error,
          size: 48,
        ),
        title: const Text('Confirm Delete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete ${files.length} item(s)?',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            if (totalSize > 0)
              Text(
                'Total size: ${_formatBytes(totalSize)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
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
              await appState.deleteFiles(widget.side, files);
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

  void _showPropertiesDialog(BuildContext context, FileItem file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(file.isFolder ? Icons.folder : Icons.insert_drive_file),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _propertyRow(context, 'Type', file.isFolder ? 'Folder' : 'File'),
              if (file.size != null)
                _propertyRow(context, 'Size', _formatBytes(file.size!)),
              if (file.path != null)
                _propertyRow(context, 'Path', file.path!, mono: true),
              if (file.uuid != null)
                _propertyRow(context, 'UUID', file.uuid!, mono: true),
              if (file.updatedAt != null)
                _propertyRow(
                  context,
                  'Modified',
                  _formatDate(file.updatedAt!),
                ),
              if (!file.isFolder && file.name.contains('.'))
                _propertyRow(
                  context,
                  'Extension',
                  file.name.split('.').last.toUpperCase(),
                ),
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

  Widget _propertyRow(BuildContext context, String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: TextStyle(
              fontFamily: mono ? 'monospace' : null,
              fontSize: mono ? 12 : null,
            ),
          ),
        ],
      ),
    );
  }

  // --- NEW SEARCH DIALOGS ---

  void _showSearchDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();
    // --- FIX: Save the valid parent context BEFORE showing the dialog ---
    final BuildContext panelContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog( // Use a different name for the dialog's context
        title: const Text('Fuzzy Search (All Files)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Search query',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            if (value.isNotEmpty) {
              Navigator.pop(dialogContext); // Close dialog using its own context
              final results = await appState.searchFiles(value);
              // --- FIX: Use the saved, valid parent context ---
              if (panelContext.mounted) {
                _showSearchResultsDialog(panelContext, appState, value, results['folders'] ?? [], results['files'] ?? []);
              }
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext), // Use dialog's context
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                Navigator.pop(dialogContext); // Close dialog using its own context
                final results = await appState.searchFiles(controller.text);
                // --- FIX: Use the saved, valid parent context ---
                if (panelContext.mounted) {
                  _showSearchResultsDialog(panelContext, appState, controller.text, results['folders'] ?? [], results['files'] ?? []);
                }
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  void _showFindDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();
    // --- FIX: Save the valid parent context BEFORE showing the dialog ---
    final BuildContext panelContext = context;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog( // Use a different name for the dialog's context
        title: Text('Find in "${p.basename(appState.remotePath)}"'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Pattern (e.g. *.pdf, report-*)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.find_in_page),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            if (value.isNotEmpty) {
              Navigator.pop(dialogContext); // Close dialog
              final results = await appState.findFiles(value);
              // --- FIX: Use the saved, valid parent context ---
              if (panelContext.mounted) {
                _showSearchResultsDialog(panelContext, appState, value, [], results); // No folders from find
              }
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext), // Use dialog's context
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                Navigator.pop(dialogContext); // Close dialog
                final results = await appState.findFiles(controller.text);
                // --- FIX: Use the saved, valid parent context ---
                if (panelContext.mounted) {
                  _showSearchResultsDialog(panelContext, appState, controller.text, [], results); // No folders from find
                }
              }
            },
            child: const Text('Find'),
          ),
        ],
      ),
    );
  }


  void _showSearchResultsDialog(BuildContext context, AppState appState, String query, List<FileItem> folders, List<FileItem> files) {
    final allItems = [...folders, ...files];
    
    showDialog(
      context: context,
      // Use a larger dialog
      builder: (context) => AlertDialog(
        title: Text('Search Results for "$query"'),
        content: Container(
          width: double.maxFinite,
          height: 400, // Give it some space
          child: allItems.isEmpty
              ? const Center(child: Text('No results found.'))
              : ListView.builder(
                  itemCount: allItems.length,
                  itemBuilder: (context, index) {
                    final item = allItems[index];
                    return ListTile(
                      leading: Icon(item.isFolder ? Icons.folder : _getFileIcon(item.name)),
                      title: Text(p.basename(item.name)),
                      subtitle: Text(
                        // Show parent path, not full name
                        p.dirname(item.path ?? '/'), 
                        overflow: TextOverflow.ellipsis
                      ),
                      onTap: () {
                        // On tap, navigate to the item's parent folder
                        if (item.path != null) {
                          final parentPath = p.dirname(item.path!);
                          // --- FIX: Pass the item to be selected ---
                          appState.navigateToPath(PanelSide.remote, parentPath, selectItem: item); 
                          Navigator.pop(context); // Close results dialog
                        }
                      },
                    );
                  },
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

  // Helper method copied from _FileListTile to show icons in search results
  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
      case 'md':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
      case 'webm':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
      case 'm4a':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.archive;
      case 'html':
      case 'css':
      case 'js':
      case 'json':
      case 'xml':
      case 'py':
      case 'java':
      case 'cpp':
      case 'c':
      case 'dart':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final fileDate = DateTime(date.year, date.month, date.day);

    String dateStr;
    if (fileDate == today) {
      dateStr = 'Today';
    } else if (fileDate == yesterday) {
      dateStr = 'Yesterday';
    } else {
      dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }

    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$dateStr at $timeStr';
  }
}

class _FileListTile extends StatelessWidget {
  final FileItem file;
  final PanelSide side;
  final bool isSelected;
  final Function(bool shiftKey, bool ctrlKey) onTap;
  final VoidCallback onDoubleTap;
  final Function(TapDownDetails)? onSecondaryTap;

  const _FileListTile({
    required this.file,
    required this.side,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: onSecondaryTap,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              onDoubleTap();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
          leading: Icon(
            file.isFolder ? Icons.folder : _getFileIcon(file.name),
            color: file.isFolder ? Colors.amber : null,
            size: 32,
          ),
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              if (!file.isFolder && file.size != null) ...[
                Text(_formatBytes(file.size!)),
                if (file.updatedAt != null) ...[
                  const Text(' • '),
                  Text(_formatDate(file.updatedAt!)),
                ],
              ] else if (file.updatedAt != null)
                Text(_formatDate(file.updatedAt!)),
            ],
          ),
          trailing: file.isFolder 
              ? IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: onDoubleTap, // Click arrow to open
                )
              : null,
          onTap: () {
            final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
            final ctrlPressed = HardwareKeyboard.instance.isControlPressed ||
                              HardwareKeyboard.instance.isMetaPressed;
            onTap(shiftPressed, ctrlPressed);
          },
          onLongPress: onDoubleTap, // Long press to open on mobile
        ),
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
      case 'md':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
      case 'webm':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
      case 'm4a':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.archive;
      case 'html':
      case 'css':
      case 'js':
      case 'json':
      case 'xml':
      case 'py':
      case 'java':
      case 'cpp':
      case 'c':
      case 'dart':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }
}