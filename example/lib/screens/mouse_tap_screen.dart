import 'package:flutter/material.dart';

/// Demonstrates the secondary (right) and tertiary (middle) mouse tap
/// gestures driven by the `secondary_tap` / `tertiary_tap` MCP tools.
class MouseTapScreen extends StatefulWidget {
  const MouseTapScreen({super.key});

  @override
  State<MouseTapScreen> createState() => _MouseTapScreenState();
}

class _MouseTapScreenState extends State<MouseTapScreen> {
  int _secondary = 0;
  int _tertiary = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mouse Buttons'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              key: const ValueKey('secondary_tap_count'),
              'Secondary (right) taps: $_secondary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              key: const ValueKey('tertiary_tap_count'),
              'Tertiary (middle) taps: $_tertiary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                key: const ValueKey('mouse_tap_target'),
                onSecondaryTapUp: (_) => setState(() => _secondary++),
                onTertiaryTapUp: (_) => setState(() => _tertiary++),
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
                        Icons.mouse_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Right- or middle-click me',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use the secondary/tertiary mouse button\n'
                        'or the secondary_tap / tertiary_tap MCP tools',
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
            child: FilledButton.tonal(
              onPressed: () => setState(() {
                _secondary = 0;
                _tertiary = 0;
              }),
              child: const Text('Reset'),
            ),
          ),
        ],
      ),
    );
  }
}
