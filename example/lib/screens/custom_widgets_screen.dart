import 'package:flutter/material.dart';

import '../custom_widgets.dart';

/// Shows custom design-system widgets recognized through
/// `MarionetteConfiguration.isInteractiveElement` (see `main.dart`), next to
/// built-in generic widgets Marionette recognizes out of the box.
class CustomWidgetsScreen extends StatefulWidget {
  const CustomWidgetsScreen({super.key});

  @override
  State<CustomWidgetsScreen> createState() => _CustomWidgetsScreenState();
}

class _CustomWidgetsScreenState extends State<CustomWidgetsScreen> {
  String _lastAction = 'none';
  String _size = 'Medium';
  int _quantity = 1;
  String _fruit = 'Apple';
  int _radio = 1;

  void _record(String action) => setState(() => _lastAction = action);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Widgets'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: RadioGroup<int>(
        groupValue: _radio,
        onChanged: (value) => setState(() => _radio = value ?? _radio),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              key: const ValueKey('last_action'),
              'Last action: $_lastAction',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text('Design system',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                DsPrimaryButton(
                  key: const ValueKey('ds_primary_button'),
                  label: 'Primary',
                  onTap: () => _record('primary'),
                ),
                DsSecondaryButton(
                  key: const ValueKey('ds_secondary_button'),
                  label: 'Secondary',
                  onTap: () => _record('secondary'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                DsSelect<String>(
                  key: const ValueKey('ds_size_select'),
                  value: _size,
                  options: const ['Small', 'Medium', 'Large'],
                  labelOf: (size) => 'Size: $size',
                  onChanged: (size) => setState(() => _size = size),
                ),
                DsSelect<int>(
                  key: const ValueKey('ds_quantity_select'),
                  value: _quantity,
                  options: const [1, 2, 3],
                  labelOf: (quantity) => 'Quantity: $quantity',
                  onChanged: (quantity) => setState(() => _quantity = quantity),
                ),
              ],
            ),
            DsTile(
              title: 'Tappable tile',
              onTap: () => _record('tile'),
            ),
            const DsTile(
              title: 'Static tile',
            ),
            const Divider(),
            Text(
              'Built-in generic widgets',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Row(
              children: [
                DropdownButton<String>(
                  key: const ValueKey('fruit_dropdown'),
                  value: _fruit,
                  items: const [
                    DropdownMenuItem(value: 'Apple', child: Text('Apple')),
                    DropdownMenuItem(value: 'Banana', child: Text('Banana')),
                    DropdownMenuItem(value: 'Cherry', child: Text('Cherry')),
                  ],
                  onChanged: (fruit) =>
                      setState(() => _fruit = fruit ?? _fruit),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  key: const ValueKey('actions_menu'),
                  onSelected: _record,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'share', child: Text('Share')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Actions'),
                  ),
                ),
              ],
            ),
            const Row(
              children: [
                Radio<int>(key: ValueKey('radio_1'), value: 1),
                Text('One'),
                Radio<int>(key: ValueKey('radio_2'), value: 2),
                Text('Two'),
              ],
            ),
            const RadioListTile<int>(
              key: ValueKey('radio_tile_3'),
              value: 3,
              title: Text('Three'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                key: const ValueKey('icon_button'),
                onPressed: () => _record('icon button'),
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
