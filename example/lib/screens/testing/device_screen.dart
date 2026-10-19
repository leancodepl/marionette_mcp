import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

/// Targets for the native lane's device shortcuts: the status of every
/// permission group native_permissions can change, the screen orientation
/// (native_set_orientation), and the query of the deep link that opened the
/// screen (native_open_url).
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

/// A permission group as named by native_permissions, and the
/// permission_handler permission that reports it.
typedef _Group = ({String name, Permission permission});

class _DeviceScreenState extends State<DeviceScreen>
    with WidgetsBindingObserver {
  static final List<_Group> _groups = [
    (name: 'camera', permission: Permission.camera),
    (name: 'microphone', permission: Permission.microphone),
    (name: 'photos', permission: Permission.photos),
    // Before Android 13 the photos group is storage; permission_handler
    // reports it separately.
    if (Platform.isAndroid)
      (name: 'photos (storage)', permission: Permission.storage),
    (name: 'location', permission: Permission.locationWhenInUse),
    (name: 'contacts', permission: Permission.contacts),
    (name: 'calendar', permission: Permission.calendarFullAccess),
    (name: 'notifications', permission: Permission.notification),
  ];

  final Map<String, PermissionStatus> _statuses = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Statuses change outside the app (native_permissions grant does not
  /// restart it on Android), so they are re-read when it comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final statuses = {
      for (final group in _groups) group.name: await group.permission.status,
    };
    if (mounted)
      setState(() => _statuses
        ..clear()
        ..addAll(statuses));
  }

  Future<void> _request(Permission permission) async {
    await permission.request();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final orientation = MediaQuery.orientationOf(context);
    final query = GoRouterState.of(context).uri.query;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device & permissions'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Targets for native_permissions (every group it supports), '
              'native_set_orientation and native_open_url. Statuses are '
              're-read when the app comes back to the foreground. Open with '
              'marionette-example://app/testing/device?from=link to see the '
              'deep link query below.',
              style: textTheme.bodyMedium,
            ),
          ),
          ListTile(
            title: const Text('Orientation'),
            subtitle: Text('Orientation: ${orientation.name}'),
          ),
          ListTile(
            title: const Text('Deep link query'),
            subtitle: Text(query.isEmpty ? 'Query: none' : 'Query: $query'),
          ),
          const Divider(),
          for (final group in _groups)
            ListTile(
              title: Text('Permission ${group.name}'),
              subtitle: Text(
                '${group.name}: ${_statuses[group.name]?.name ?? '…'}',
              ),
              trailing: FilledButton.tonal(
                onPressed: () => _request(group.permission),
                child: Text('Request ${group.name}'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: _refresh,
              child: const Text('Refresh statuses'),
            ),
          ),
        ],
      ),
    );
  }
}
