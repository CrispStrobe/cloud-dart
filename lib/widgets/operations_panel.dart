// widgets/operations_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../models/operation_progress.dart';

class OperationsPanel extends StatefulWidget {
  const OperationsPanel({super.key});

  @override
  State<OperationsPanel> createState() => _OperationsPanelState();
}

class _OperationsPanelState extends State<OperationsPanel> {
  String? _expandedOperationId;
  bool _isPanelExpanded = true;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    
    if (appState.operations.isEmpty) {
      // If there are no operations, don't show the panel at all.
      return const SizedBox.shrink();
    }

    // Calculate overall progress
    int totalBytes = 0;
    int transferredBytes = 0;
    int activeCount = 0;
    int completeCount = 0;
    int errorCount = 0;

    for (final op in appState.operations) {
      totalBytes += op.totalBytes;
      transferredBytes += op.transferredBytes;
      
      if (op.isCancelled) {
        errorCount++;
      } else if (op.error != null) {
        errorCount++;
      } else if (op.isComplete) {
        completeCount++;
      } else {
        activeCount++;
      }
    }

    final overallProgress = totalBytes > 0 ? transferredBytes / totalBytes : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ExpansionTile(
        title: _buildPanelHeader(context, appState, activeCount, completeCount, errorCount, overallProgress, transferredBytes, totalBytes),
        initiallyExpanded: true,
        onExpansionChanged: (isExpanded) {
          setState(() => _isPanelExpanded = isExpanded);
        },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (completeCount > 0 || errorCount > 0)
              IconButton(
                icon: const Icon(Icons.clear_all, size: 20),
                tooltip: 'Clear completed',
                onPressed: () => appState.clearCompletedOperations(),
              ),
            Icon(
              _isPanelExpanded ? Icons.expand_less : Icons.expand_more,
            ),
          ],
        ),
        children: [
          // Constrain the height of the list view
          Container(
            constraints: const BoxConstraints(maxHeight: 250), // Max height for the list
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: appState.operations.length,
              itemBuilder: (context, index) {
                final op = appState.operations[index];
                final isExpanded = _expandedOperationId == op.id;
                
                return _OperationTile(
                  operation: op,
                  isExpanded: isExpanded,
                  onToggleExpanded: () {
                    setState(() {
                      _expandedOperationId = isExpanded ? null : op.id;
                    });
                  },
                  onRemove: () => appState.removeOperation(op.id),
                  onCancel: !op.isComplete && !op.isCancelled 
                      ? () => appState.cancelOperation(op.id)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(
    BuildContext context,
    AppState appState,
    int activeCount,
    int completeCount,
    int errorCount,
    double overallProgress,
    int transferredBytes,
    int totalBytes,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            activeCount > 0 ? Icons.sync : Icons.check_circle,
            size: 20,
            color: errorCount > 0 
                ? Theme.of(context).colorScheme.error
                : activeCount > 0
                    ? Theme.of(context).colorScheme.primary
                    : Colors.green,
          ),
          const SizedBox(width: 12),
          
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${appState.operations.length} operation(s)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (activeCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '• ${(overallProgress * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatBytes(transferredBytes)} / ${_formatBytes(totalBytes)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (completeCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '✓ $completeCount',
                        style: TextStyle(color: Colors.green[700]),
                      ),
                    ],
                    if (errorCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '✗ $errorCount',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                
                // Segmented progress bar
                SizedBox(
                  height: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(color: Colors.grey[300]),
                        Row(
                          children: appState.operations.map((op) {
                            final segmentWidth = totalBytes > 0 
                                ? op.totalBytes / totalBytes 
                                : 1.0 / appState.operations.length;
                            
                            Color segmentColor;
                            if (op.isCancelled) {
                              segmentColor = Colors.orange;
                            } else if (op.error != null) {
                              segmentColor = Theme.of(context).colorScheme.error;
                            } else if (op.isComplete) {
                              segmentColor = Colors.green;
                            } else {
                              segmentColor = Theme.of(context).colorScheme.primary;
                            }

                            return Expanded(
                              flex: (segmentWidth * 1000).toInt(),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                                child: LinearProgressIndicator(
                                  value: op.progress,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(segmentColor),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Action buttons are no longer needed here
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _OperationTile extends StatelessWidget {
  final OperationProgress operation;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onRemove;
  final VoidCallback? onCancel;

  const _OperationTile({
    required this.operation,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onRemove,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color? color;

    if (operation.isCancelled) {
      icon = Icons.cancel;
      color = Colors.orange;
    } else if (operation.isPaused) {
      icon = Icons.pause_circle;
      color = Colors.blue;
    } else if (operation.isComplete) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (operation.error != null) {
      icon = Icons.error;
      color = Colors.red;
    } else {
      icon = operation.type == OperationType.upload 
          ? Icons.upload 
          : Icons.download;
      color = Theme.of(context).colorScheme.primary;
    }

    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(icon, size: 20, color: color),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  operation.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (operation.isBatch) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${operation.completedFiles}/${operation.totalFiles} files',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!operation.isComplete && operation.error == null && !operation.isCancelled)
                LinearProgressIndicator(
                  value: operation.progress,
                  backgroundColor: Colors.grey[300],
                ),
              const SizedBox(height: 2),
              Text(
                operation.isCancelled 
                    ? 'Cancelled'
                    : operation.isPaused
                        ? 'Paused'
                        : operation.error ?? _getStatusText(operation),
                style: TextStyle(
                  fontSize: 11,
                  color: operation.error != null ? Colors.red : 
                        operation.isCancelled ? Colors.orange :
                        operation.isPaused ? Colors.blue : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pause/Resume button for in-progress operations
              if (!operation.isComplete && !operation.isCancelled)
                IconButton(
                  icon: Icon(
                    operation.isPaused ? Icons.play_arrow : Icons.pause,
                    size: 16,
                  ),
                  tooltip: operation.isPaused ? 'Resume' : 'Pause',
                  color: Colors.blue,
                  onPressed: operation.isPaused
                      ? () => context.read<AppState>().resumeOperation(operation.id)
                      : () => context.read<AppState>().pauseOperation(operation.id),
                ),
              // Cancel button for in-progress operations
              if (!operation.isComplete && !operation.isCancelled && onCancel != null)
                IconButton(
                  icon: const Icon(Icons.cancel, size: 16),
                  tooltip: 'Cancel',
                  color: Colors.red,
                  onPressed: onCancel,
                ),
              // Expand button for batch operations
              if (operation.isBatch)
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                  onPressed: onToggleExpanded,
                ),
              // Remove button for completed/failed/cancelled operations
              if (operation.isComplete || operation.error != null || operation.isCancelled)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
        
        // Expanded batch details
        if (isExpanded && operation.isBatch && operation.files != null)
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            constraints: const BoxConstraints(maxHeight: 150), // Max height for sub-list
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: operation.files!.length,
              itemBuilder: (context, index) {
                final file = operation.files![index];
                return Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Row(
                    children: [
                      Icon(
                        file.error != null 
                            ? Icons.error
                            : file.isComplete 
                                ? Icons.check_circle 
                                : Icons.pending,
                        size: 12,
                        color: file.error != null
                            ? Colors.red
                            : file.isComplete
                                ? Colors.green
                                : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.name,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatBytes(file.size),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _getStatusText(OperationProgress op) {
    if (op.isComplete) return 'Complete';
    if (op.error != null) return 'Error: ${op.error}';
    
    final percent = (op.progress * 100).toStringAsFixed(0);
    return '$percent% • ${_formatBytes(op.transferredBytes)} / ${_formatBytes(op.totalBytes)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}