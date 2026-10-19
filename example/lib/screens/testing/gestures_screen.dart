import 'dart:async';

import 'package:flutter/material.dart';

/// Native-lane test cases that are not tied to one requirement section:
/// element state, gestures, waiting, and scrolling inside a container.
///
/// Every target reports what happened in visible text, so the native lane can
/// verify the effect with native_get_elements.
class GesturesScreen extends StatefulWidget {
  const GesturesScreen({super.key});

  @override
  State<GesturesScreen> createState() => _GesturesScreenState();
}

class _GesturesScreenState extends State<GesturesScreen> {
  bool _wifi = true;
  bool _terms = false;
  int _longPresses = 0;
  int _doubleTaps = 0;
  double _scale = 1;
  double _scaleAtStart = 1;
  bool _delayedVisible = false;
  Timer? _showTimer;
  Timer? _hideTimer;

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleDelayedMessage() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    setState(() => _delayedVisible = false);
    _showTimer = Timer(const Duration(seconds: 2), () {
      setState(() => _delayedVisible = true);
      _hideTimer = Timer(const Duration(seconds: 4), () {
        setState(() => _delayedVisible = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final outline = Theme.of(context).colorScheme.outline;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text(title, style: textTheme.titleMedium),
        );

    Widget target(String label, String status, {double height = 96}) =>
        Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$label\n$status', textAlign: TextAlign.center),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestures & inspection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Targets for native_get_elements (state), native_long_press, '
            'native_double_tap, native_pinch, native_wait_for and native_scroll '
            'inside a container (within: {"id": "horizontal_list"} or '
            '{"id": "vertical_list"}). Each target shows the result as text.',
            style: textTheme.bodyMedium,
          ),
          section('Element state'),
          SwitchListTile(
            title: const Text('Wi-Fi'),
            value: _wifi,
            onChanged: (value) => setState(() => _wifi = value),
          ),
          CheckboxListTile(
            title: const Text('Accept terms'),
            value: _terms,
            onChanged: (value) => setState(() => _terms = value ?? false),
          ),
          const ElevatedButton(
            onPressed: null,
            child: Text('Disabled action'),
          ),
          section('Gestures'),
          GestureDetector(
            onLongPress: () => setState(() => _longPresses++),
            child: target('Long press here', 'Long presses: $_longPresses'),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onDoubleTap: () => setState(() => _doubleTaps++),
            child: target('Double tap here', 'Double taps: $_doubleTaps'),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onScaleStart: (_) => _scaleAtStart = _scale,
            onScaleUpdate: (details) =>
                setState(() => _scale = _scaleAtStart * details.scale),
            child: target(
              'Pinch here',
              'Scale: ${_scale.toStringAsFixed(2)}',
              height: 200,
            ),
          ),
          section('Waiting'),
          ElevatedButton(
            onPressed: _scheduleDelayedMessage,
            child: const Text('Show message in 2 s'),
          ),
          SizedBox(
            height: 48,
            child: Center(
              child: _delayedVisible
                  ? const Text('Delayed message (visible for 4 s)')
                  : const SizedBox.shrink(),
            ),
          ),
          section('Scrolling inside a container'),
          Semantics(
            identifier: 'horizontal_list',
            container: true,
            child: SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 30,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.all(8),
                  child: Chip(label: Text('Chip ${index + 1}')),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            identifier: 'vertical_list',
            container: true,
            child: Container(
              height: 240,
              decoration: BoxDecoration(border: Border.all(color: outline)),
              child: ListView.builder(
                itemCount: 60,
                itemBuilder: (context, index) =>
                    ListTile(title: Text('Row ${index + 1}')),
              ),
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }
}
