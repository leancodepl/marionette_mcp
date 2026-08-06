import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  PermissionStatus? _notificationStatus;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final status = await Permission.notification.status;
    if (!mounted) return;
    setState(() => _notificationStatus = status);
  }

  Future<void> _requestNotificationPermission() async {
    setState(() => _requesting = true);
    try {
      final status = await Permission.notification.request();
      if (!mounted) return;
      setState(() => _notificationStatus = status);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _onPushNotificationsChanged(bool enabled) async {
    if (enabled) {
      await _requestNotificationPermission();
      return;
    }

    await openAppSettings();
    await _refreshStatus();
  }

  String get _statusLabel {
    final status = _notificationStatus;
    if (status == null) return 'checking…';
    return status.name;
  }

  @override
  Widget build(BuildContext context) {
    final pushEnabled = _notificationStatus?.isGranted ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Push Notifications'),
            subtitle: Text(
              _notificationStatus == null ? 'Receive push notifications' : 'Receive push notifications · $_statusLabel',
            ),
            value: pushEnabled,
            onChanged: _requesting ? null : _onPushNotificationsChanged,
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Email Notifications'),
            subtitle: const Text('Receive email updates'),
            value: false,
            onChanged: (_) {},
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('In-App Notifications'),
            subtitle: const Text('Show in-app notification banners'),
            value: true,
            onChanged: (_) {},
          ),
        ],
      ),
    );
  }
}
