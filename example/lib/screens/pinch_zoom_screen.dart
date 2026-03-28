import 'package:flutter/material.dart';

class PinchZoomScreen extends StatefulWidget {
  const PinchZoomScreen({super.key});

  @override
  State<PinchZoomScreen> createState() => _PinchZoomScreenState();
}

class _PinchZoomScreenState extends State<PinchZoomScreen> {
  double _scale = 1.0;
  double _baseScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pinch Zoom'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Scale: ${_scale.toStringAsFixed(2)}x',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onScaleStart: (details) {
                  _baseScale = _scale;
                },
                onScaleUpdate: (details) {
                  setState(() {
                    _scale = (_baseScale * details.scale).clamp(0.5, 5.0);
                  });
                },
                child: InteractiveViewer(
                  key: const ValueKey('zoomable'),
                  minScale: 0.5,
                  maxScale: 5.0,
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
                          Icons.zoom_in,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Pinch to zoom',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use two fingers or the\npinch_zoom MCP tool',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FilledButton.tonal(
              onPressed: () => setState(() => _scale = 1.0),
              child: const Text('Reset Zoom'),
            ),
          ),
        ],
      ),
    );
  }
}
