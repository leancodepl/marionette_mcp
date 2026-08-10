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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Permission dialogs'),
            subtitle: const Text('OS permission prompts (§3)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/permission-dialogs'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Pickers & sheets'),
            subtitle: const Text('File, photo, camera, share (§4)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/pickers-and-sheets'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.keyboard_outlined),
            title: const Text('Keyboard / IME'),
            subtitle: const Text('Numeric, return, done keyboards (§8)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/keyboard'),
          ),
        ],
      ),
    );
  }
}
