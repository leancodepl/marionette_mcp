import 'package:flutter/material.dart';

import 'native_demo_channel.dart';

/// A full native screen (Activity / UIViewController) opened from
/// Flutter; it returns the text typed into its native field.
class NativeScreenScreen extends StatefulWidget {
  const NativeScreenScreen({super.key});

  @override
  State<NativeScreenScreen> createState() => _NativeScreenScreenState();
}

class _NativeScreenScreenState extends State<NativeScreenScreen> {
  String _returned = 'none';

  Future<void> _open() async {
    final text = await NativeDemoChannel.openNativeScreen();
    if (mounted) setState(() => _returned = text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native screen'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Opens a native screen with a text field (id native_form_name) '
            'and a "Back to Flutter" button (id native_form_back).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _open,
            child: const Text('Open native screen'),
          ),
          Text('Returned: $_returned'),
        ],
      ),
    );
  }
}
