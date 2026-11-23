import 'package:flutter/material.dart';

class ReorderableListScreen extends StatefulWidget {
  const ReorderableListScreen({super.key});

  @override
  State<ReorderableListScreen> createState() => _ReorderableListScreenState();
}

class _ReorderableListScreenState extends State<ReorderableListScreen> {
  final _items = List.generate(6, (i) => 'Item ${i + 1}');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorderable List'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Order: ${_items.join(', ')}',
              key: const ValueKey('reorderable_order'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) => setState(
                () => _items.insert(newIndex, _items.removeAt(oldIndex)),
              ),
              children: [
                for (final (index, item) in _items.indexed)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey('reorderable_$item'),
                    index: index,
                    child: ListTile(
                      title: Text(item),
                      subtitle: const Text('Long press, then drag to reorder'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
