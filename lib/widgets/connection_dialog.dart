// lib/widgets/connection_dialog.dart
import 'package:flutter/material.dart';
import '../services/app_state.dart';
import '../services/cloud_storage_interface.dart'; //
import 'package:provider/provider.dart';

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tfaController = TextEditingController();
  bool _isLoading = false;
  bool _needs2fa = false;
  String? _error;
  CloudProvider _selectedProvider = CloudProvider.filen;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to Cloud Storage'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Provider selection
            DropdownButtonFormField<CloudProvider>(
              value: _selectedProvider,
              decoration: const InputDecoration(
                labelText: 'Provider',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: CloudProvider.filen,
                  child: Text('Filen'),
                ),
                // Only show/enable Internxt if supported
                DropdownMenuItem(
                  value: CloudProvider.internxt,
                  enabled: CloudStorageFactory.isInternxtSupported, // GREY OUT LOGIC
                  child: Text(
                    CloudStorageFactory.isInternxtSupported 
                      ? 'Internxt' 
                      : 'Internxt (Disabled)',
                    style: TextStyle(
                      color: CloudStorageFactory.isInternxtSupported 
                          ? null 
                          : Theme.of(context).disabledColor,
                    ),
                  ),
                ),
              ],
              onChanged: _isLoading ? null : (value) {
                if (value != null) {
                  // Double check safety
                  if (value == CloudProvider.internxt && !CloudStorageFactory.isInternxtSupported) {
                    return; 
                  }
                  setState(() => _selectedProvider = value);
                }
              },
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                color: Colors.red.shade100,
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              enabled: !_isLoading,
            ),
            if (_needs2fa) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _tfaController,
                decoration: const InputDecoration(
                  labelText: '2FA Code',
                  border: OutlineInputBorder(),
                ),
                enabled: !_isLoading,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleLogin,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final appState = context.read<AppState>();

    try {
      // Switch provider if needed
      if (appState.currentProvider != _selectedProvider) {
        await appState.switchProvider(_selectedProvider);
      }

      // Check 2FA if supported
      if (!_needs2fa && appState.client != null) {
        final needs2fa = await appState.client!.is2faNeeded(_emailController.text);
        if (needs2fa) {
          setState(() {
            _needs2fa = true;
            _isLoading = false;
          });
          return;
        }
      }

      // Perform login
      await appState.login(
        _emailController.text,
        _passwordController.text,
        _tfaController.text.isEmpty ? null : _tfaController.text,
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _tfaController.dispose();
    super.dispose();
  }
}