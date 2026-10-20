import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';

import 'native_demo_channel.dart';

/// §11 Native dialogs from plugins and platform code: an AlertDialog /
/// UIAlertController shown over MethodChannel, and the iOS App Tracking
/// Transparency prompt. Neither is in the Flutter tree.
class NativeDialogsScreen extends StatefulWidget {
  const NativeDialogsScreen({super.key});

  @override
  State<NativeDialogsScreen> createState() => _NativeDialogsScreenState();
}

class _NativeDialogsScreenState extends State<NativeDialogsScreen> {
  String _alertResult = 'none';
  String _trackingStatus = 'not requested';

  Future<void> _showAlert() async {
    final result = await NativeDemoChannel.showAlert(
      title: 'Native alert',
      message: 'Shown by platform code, outside Flutter.',
    );
    if (mounted) setState(() => _alertResult = result);
  }

  Future<void> _requestTracking() async {
    final status = await AppTrackingTransparency.requestTrackingAuthorization();
    if (mounted) setState(() => _trackingStatus = status.name);
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
          if (Platform.isIOS) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _requestTracking,
              child: const Text('Request tracking'),
            ),
            Text('Tracking: $_trackingStatus'),
          ],
        ],
      ),
    );
  }
}
