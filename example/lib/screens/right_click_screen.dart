import 'package:flutter/material.dart';

class RightClickScreen extends StatefulWidget {
  const RightClickScreen({super.key});

  @override
  State<RightClickScreen> createState() => _RightClickScreenState();
}

class _RightClickScreenState extends State<RightClickScreen> {
  int _count = 0;
  Offset? _lastPosition;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Right Click'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              key: const ValueKey('right_click_count'),
              'Right-clicks: $_count',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                key: const ValueKey('right_click_target'),
                onSecondaryTapUp: (details) {
                  setState(() {
                    _count++;
                    _lastPosition = details.globalPosition;
                  });
                },
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.ads_click,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Right-click me',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use the secondary mouse button\nor the right_click MCP tool',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _lastPosition == null
                  ? 'No right-click yet'
                  : 'Last position: '
                      '(${_lastPosition!.dx.toStringAsFixed(0)}, '
                      '${_lastPosition!.dy.toStringAsFixed(0)})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FilledButton.tonal(
              onPressed: () => setState(() {
                _count = 0;
                _lastPosition = null;
              }),
              child: const Text('Reset'),
            ),
          ),
        ],
      ),
    );
  }
}
