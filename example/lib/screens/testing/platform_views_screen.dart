import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PlatformViewsScreen extends StatelessWidget {
  const PlatformViewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Views'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('Native controls'),
            subtitle: const Text(
              'Custom AndroidView / UiKitView with label, field, and button',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/platform-views/native-controls'),
          ),
        ],
      ),
    );
  }
}
