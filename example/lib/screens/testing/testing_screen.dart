import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TestingScreen extends StatelessWidget {
  const TestingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Testing'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: const Text('WebView'),
            subtitle: const Text('Embedded browser (§2)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/webview'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.view_in_ar_outlined),
            title: const Text('Platform Views'),
            subtitle: const Text('Embedded native surfaces (§1)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/platform-views'),
          ),
        ],
      ),
    );
  }
}
