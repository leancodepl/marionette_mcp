import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marionette_example/widgets/native_controls_platform_view.dart';

const _nativeControlsChannel =
    MethodChannel('marionette_example/native_controls');

class NativeControlsPlatformViewScreen extends StatefulWidget {
  const NativeControlsPlatformViewScreen({super.key});

  @override
  State<NativeControlsPlatformViewScreen> createState() =>
      _NativeControlsPlatformViewScreenState();
}

class _NativeControlsPlatformViewScreenState
    extends State<NativeControlsPlatformViewScreen> {
  int _nativeTapCount = 0;

  @override
  void initState() {
    super.initState();
    _nativeControlsChannel.setMethodCallHandler((call) async {
      if (call.method == 'nativeButtonTapped') {
        setState(() => _nativeTapCount++);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native controls'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Flutter label above native view'),
                const SizedBox(height: 8),
                Text('Native button taps: $_nativeTapCount'),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const NativeControlsPlatformView(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () {},
              child: const Text('Flutter button below'),
            ),
          ),
        ],
      ),
    );
  }
}
