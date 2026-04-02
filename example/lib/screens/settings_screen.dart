import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.view_list_outlined),
            title: const Text('Items'),
            subtitle: const Text('Browse the scrollable items list'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/items'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Manage notification preferences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/notifications'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.swipe_outlined),
            title: const Text('Page View'),
            subtitle: const Text('Horizontal swipe between pages'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/page-view'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Dismissible List'),
            subtitle: const Text('Swipe to dismiss list items'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/dismissible'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.zoom_in_outlined),
            title: const Text('Pinch Zoom'),
            subtitle: const Text('Test pinch zoom gesture'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/pinch-zoom'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Appearance'),
            subtitle: Text('Theme and display settings'),
            trailing: Icon(Icons.chevron_right),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('App version and info'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/about'),
          ),
        ],
      ),
    );
  }
}
