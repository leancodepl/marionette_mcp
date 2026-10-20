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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.touch_app_outlined),
            title: const Text('Gestures & inspection'),
            subtitle: const Text('State, gestures, waiting, scrolling'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/gestures'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.phone_android_outlined),
            title: const Text('Device & permissions'),
            subtitle: const Text('Permissions, orientation, deep links'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/device'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Auth UI'),
            subtitle: const Text('Biometrics, autofill (§5)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/auth'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('OAuth'),
            subtitle: const Text('Sign-in in the system browser (§7)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/oauth'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Local notifications, toasts (§9)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/notifications'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Native screen'),
            subtitle: const Text('Activity / UIViewController (§10)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/native-screen'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('Native dialogs'),
            subtitle: const Text('Platform alerts, tracking prompt (§11)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/native-dialogs'),
          ),
        ],
      ),
    );
  }
}
