import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_rounded,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text('Marionette Example', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Version 1.0.0', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              Text(
                'A demo app showcasing Marionette — '
                'a Flutter UI automation framework.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('about settings')),
                  );
                },
                child: const Text('Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
