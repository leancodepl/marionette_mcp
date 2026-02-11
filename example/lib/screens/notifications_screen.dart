import 'package:flutter/material.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Push Notifications'),
            subtitle: const Text('Receive push notifications'),
            value: true,
            onChanged: (_) {},
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Email Notifications'),
            subtitle: const Text('Receive email updates'),
            value: false,
            onChanged: (_) {},
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('In-App Notifications'),
            subtitle: const Text('Show in-app notification banners'),
            value: true,
            onChanged: (_) {},
          ),
        ],
      ),
    );
  }
}
