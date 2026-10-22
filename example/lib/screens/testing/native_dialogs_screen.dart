import 'package:flutter/material.dart';

import 'native_demo_channel.dart';

/// A native dialog from platform code: an AlertDialog / UIAlertController
/// shown over MethodChannel. It is not in the Flutter tree.
class NativeDialogsScreen extends StatefulWidget {
  const NativeDialogsScreen({super.key});

  @override
  State<NativeDialogsScreen> createState() => _NativeDialogsScreenState();
}

class _NativeDialogsScreenState extends State<NativeDialogsScreen> {
  String _alertResult = 'none';

  Future<void> _showAlert() async {
    final result = await NativeDemoChannel.showAlert(
      title: 'Native alert',
      message: 'Shown by platform code, outside Flutter.',
    );
    if (mounted) setState(() => _alertResult = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native dialogs'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Dialogs drawn by the platform, not by Flutter: use '
            'native_get_elements / native_tap while they are open.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _showAlert,
            child: const Text('Show native alert'),
          ),
          Text('Alert result: $_alertResult'),
        ],
      ),
    );
  }
}
