import 'package:flutter/material.dart';

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key});

  static const _itemCount = 40;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Items'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: _itemCount,
        itemBuilder: (context, index) {
          return ListTile(
            key: ValueKey('item_$index'),
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text('Item $index'),
            subtitle: const Text('Scroll target for marionette.scrollTo'),
          );
        },
      ),
    );
  }
}
