import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// §3 Permission dialogs — OS-owned alerts (permissioncontroller / SpringBoard).
class PermissionDialogsScreen extends StatefulWidget {
  const PermissionDialogsScreen({super.key});

  @override
  State<PermissionDialogsScreen> createState() => _PermissionDialogsScreenState();
}

class _PermissionDialogsScreenState extends State<PermissionDialogsScreen> {
  PermissionStatus? _notificationStatus;
  PermissionStatus? _cameraStatus;
  PermissionStatus? _photosStatus;
  Permission? _requesting;

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    final results = await Future.wait([
      Permission.notification.status,
      Permission.camera.status,
      Permission.photos.status,
    ]);
    if (!mounted) return;
    setState(() {
      _notificationStatus = results[0];
      _cameraStatus = results[1];
      _photosStatus = results[2];
    });
  }

  Future<void> _request(Permission permission) async {
    setState(() => _requesting = permission);
    try {
      await permission.request();
      await _refreshStatuses();
    } finally {
      if (mounted) setState(() => _requesting = null);
    }
  }

  Future<void> _onNotificationChanged(bool enabled) async {
    if (enabled) {
      await _request(Permission.notification);
      return;
    }
    await openAppSettings();
    await _refreshStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final notificationGranted = _notificationStatus?.isGranted ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permission dialogs'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Trigger system permission dialogs via permission_handler. '
              'Reset between runs: adb shell pm reset-permissions (Android) or '
              'xcrun simctl privacy booted reset all <bundle id> (iOS).',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SwitchListTile(
            title: const Text('Notifications'),
            subtitle: Text(_statusLine('Push notifications', _notificationStatus)),
            value: notificationGranted,
            onChanged: _requesting == Permission.notification
                ? null
                : _onNotificationChanged,
          ),
          const Divider(),
          ListTile(
            title: const Text('Camera'),
            subtitle: Text(_statusLine('Camera access', _cameraStatus)),
            trailing: FilledButton(
              onPressed: _requesting == Permission.camera
                  ? null
                  : () => _request(Permission.camera),
              child: const Text('Request'),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Photos'),
            subtitle: Text(_statusLine('Photo library access', _photosStatus)),
            trailing: FilledButton(
              onPressed: _requesting == Permission.photos
                  ? null
                  : () => _request(Permission.photos),
              child: const Text('Request'),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLine(String label, PermissionStatus? status) {
    if (status == null) return '$label · checking…';
    return '$label · ${status.name}';
  }
}
