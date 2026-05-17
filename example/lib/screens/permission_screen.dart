import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// A helper screen that lets automated tests exercise native permission dialogs.
///
/// Tapping "Request Camera Permission" calls [Permission.camera.request]
/// which, on Android, surfaces the OS permission dialog that lives outside
/// the Flutter widget tree. Use the `accept_permission` marionette tool to
/// accept the dialog from the host machine.
class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  PermissionStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh the status when the user returns from the permission settings.
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    final status = await Permission.camera.status;
    if (mounted) setState(() => _status = status);
  }

  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (mounted) setState(() => _status = status);
  }

  String get _statusLabel {
    return switch (_status) {
      null => 'Unknown',
      PermissionStatus.granted => 'Granted ✅',
      PermissionStatus.denied => 'Denied ❌',
      PermissionStatus.permanentlyDenied => 'Permanently denied 🚫',
      PermissionStatus.restricted => 'Restricted',
      PermissionStatus.limited => 'Limited',
      PermissionStatus.provisional => 'Provisional',
      _ => _status.toString(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permission Helper'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This screen triggers an Android camera permission dialog '
              'so that the marionette `accept_permission` tool can be tested.',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.camera_alt_outlined, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Camera Permission',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Status: $_statusLabel',
                            key: const ValueKey('camera_permission_status'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('request_camera_permission_button'),
              onPressed: _requestPermission,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Request Camera Permission'),
            ),
          ],
        ),
      ),
    );
  }
}
