import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PlatformViewsScreen extends StatelessWidget {
  const PlatformViewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Views'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '§1a — Plain native controls',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('Native controls'),
            subtitle: const Text(
              'Custom AndroidView / UiKitView with label, field, and button',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/platform-views/native-controls'),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '§1b — Surface / GPU-backed views',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Camera preview'),
            subtitle: const Text('camera plugin — live preview surface'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/platform-views/camera'),
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Google Maps'),
            subtitle: const Text('google_maps_flutter — MapView / MKMapView'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/platform-views/google-maps'),
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Video player'),
            subtitle: const Text('video_player — ExoPlayer / AVPlayerLayer'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/testing/platform-views/video-player'),
          ),
        ],
      ),
    );
  }
}
