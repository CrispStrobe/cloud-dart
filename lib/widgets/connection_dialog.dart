// lib/widgets/connection_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/cloud_storage_interface.dart';

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  // General Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tfaController = TextEditingController();
  
  // SFTP Specific Controllers
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22'); // Default SFTP port
  final _sftpUserController = TextEditingController();

  

  bool _isLoading = false;
  bool _needs2fa = false;
  String? _error;
  
  // Default to Filen, or SFTP if preferred
  CloudProvider _selectedProvider = CloudProvider.filen;

  @override
  Widget build(BuildContext context) {
    // Determine which fields to show based on provider
    final isSftp = _selectedProvider == CloudProvider.sftp; // Ensure CloudProvider.sftp exists in your enum
    final isInternxt = _selectedProvider == CloudProvider.internxt;
    final isWebDav = _selectedProvider == CloudProvider.webdav;

    return AlertDialog(
      title: const Text('Connect to Cloud Storage'),
      scrollable: true, // Allow scrolling if keyboard covers fields
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- 1. Provider Selection ---
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
                // SFTP / Storage Box
                const DropdownMenuItem(
                  value: CloudProvider.sftp, 
                  child: Text('SFTP / Storage Box'),
                ),
                // WebDAV
                const DropdownMenuItem(
                  value: CloudProvider.webdav,
                  child: Text('WebDAV'),
                ),
                // Internxt (Conditional)
                DropdownMenuItem(
                  value: CloudProvider.internxt,
                  enabled: CloudStorageFactory.isInternxtSupported, 
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
                  if (value == CloudProvider.internxt && !CloudStorageFactory.isInternxtSupported) {
                    return; 
                  }
                  setState(() {
                    _selectedProvider = value;
                    _error = null;
                    _needs2fa = false;
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // --- 2. Error Message ---
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                color: Colors.red.shade100,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ],
                ),
              ),

            // --- 3. Dynamic Fields ---
            
            if (isSftp) ...[
              // SFTP: Host & Port Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        hintText: 'u123.your-storagebox.de',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '22',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      enabled: !_isLoading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // SFTP: Username
              TextField(
                controller: _sftpUserController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'u12345',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                enabled: !_isLoading,
              ),
            ] else if (isWebDav) ...[
               // WebDAV Fields
               TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://cloud.example.com/remote.php/dav/files/user/',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController, // Reuse as Username
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                enabled: !_isLoading,
              ),
            
            ] else ...[
              // Standard: Email
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: isInternxt ? 'Email' : 'Email Address',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                enabled: !_isLoading,
              ),
            ],

            const SizedBox(height: 16),

            // --- 4. Password (Common) ---
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              enabled: !_isLoading,
            ),

            // --- 5. 2FA (Conditional) ---
            if (_needs2fa) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _tfaController,
                decoration: const InputDecoration(
                  labelText: '2FA Code',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.security),
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
      // 1. Switch provider if needed
      if (appState.currentProvider != _selectedProvider) {
        await appState.switchProvider(_selectedProvider);
      }

      // 2. Prepare Credentials
      String identity;
      if (_selectedProvider == CloudProvider.sftp) {
        // SFTP Validation
        if (_hostController.text.isEmpty || _sftpUserController.text.isEmpty) {
          throw Exception('Host and Username are required');
        }
        
        // Construct composite identity for SFTP Adapter: "username@host:port"
        // The adapter must parse this format.
        final port = _portController.text.isEmpty ? '22' : _portController.text;
        identity = '${_sftpUserController.text}@${_hostController.text}:$port';
      } else if (_selectedProvider == CloudProvider.webdav) {
         if (_hostController.text.isEmpty || _emailController.text.isEmpty) {
            throw Exception('Server URL and Username are required');
         }
         // Pack as: username@https://server.com/dav
         identity = '${_emailController.text}@${_hostController.text}';
      } else {
        // Standard Email
        if (_emailController.text.isEmpty) {
          throw Exception('Email is required');
        }
        identity = _emailController.text;
      }

      // 3. Check 2FA (Internxt/Filen only)
      if (!_needs2fa && _selectedProvider != CloudProvider.sftp && appState.client.isAuthenticated == false) {
        // Only check 2FA if we aren't already halfway through a login
        try {
          final needs2fa = await appState.client.is2faNeeded(identity);
          if (needs2fa) {
            setState(() {
              _needs2fa = true;
              _isLoading = false;
            });
            return; // Stop here, wait for user to enter code
          }
        } catch (e) {
          // Ignore pre-check errors, let login fail normally if needed
          print('2FA check skipped/failed: $e');
        }
      }

      // 4. Perform Login
      await appState.login(
        identity,
        _passwordController.text,
        _tfaController.text.isEmpty ? null : _tfaController.text,
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _tfaController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _sftpUserController.dispose();
    super.dispose();
  }
}