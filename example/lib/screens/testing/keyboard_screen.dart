import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// §8 Keyboard / IME — native keyboard occludes layout; test via native lane.
class KeyboardScreen extends StatefulWidget {
  const KeyboardScreen({super.key});

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends State<KeyboardScreen> {
  final _numericController = TextEditingController();
  final _multilineController = TextEditingController();
  final _doneController = TextEditingController();

  final _numericFocus = FocusNode();
  final _multilineFocus = FocusNode();
  final _doneFocus = FocusNode();

  @override
  void dispose() {
    _numericController.dispose();
    _multilineController.dispose();
    _doneController.dispose();
    _numericFocus.dispose();
    _multilineFocus.dispose();
    _doneFocus.dispose();
    super.dispose();
  }

  void _unfocusAll() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _unfocusAll,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Keyboard / IME'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Each field opens a different native keyboard. Tap a field to focus '
              'it, then use native_get_elements / native_tap on keyboard keys. '
              'The keyboard is not in the Flutter tree — use native_take_screenshot '
              'to verify it is open.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Text(
              'Numeric keyboard',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _numericController,
              focusNode: _numericFocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Amount',
                hintText: 'Digits only',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _unfocusAll(),
            ),
            const SizedBox(height: 24),
            Text(
              'Return key inserts newline',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _multilineController,
              focusNode: _multilineFocus,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Multiline — keyboard shows return',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Done action dismisses keyboard',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _doneController,
              focusNode: _doneFocus,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Single line — keyboard shows Done',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _unfocusAll(),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _unfocusAll,
              child: const Text('Unfocus (Flutter — hides keyboard)'),
            ),
          ],
        ),
      ),
    );
  }
}
