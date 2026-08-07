import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// §1b GPU-backed platform view — [GoogleMap] ([MapView] / Metal map surface).
class GoogleMapsPlatformViewScreen extends StatefulWidget {
  const GoogleMapsPlatformViewScreen({super.key});

  static const initialCamera = CameraPosition(
    target: LatLng(52.2297, 21.0122),
    zoom: 14,
  );

  @override
  State<GoogleMapsPlatformViewScreen> createState() =>
      _GoogleMapsPlatformViewScreenState();
}

class _GoogleMapsPlatformViewScreenState
    extends State<GoogleMapsPlatformViewScreen> {
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Google Maps'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Google Maps platform view is not exercised on web in this demo.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Maps'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Map tiles via google_maps_flutter (GPU-backed MapView). '
              'Requires a Maps API key in AndroidManifest / AppDelegate.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const GoogleMap(
                    initialCameraPosition: GoogleMapsPlatformViewScreen.initialCamera,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () {},
              child: const Text('Flutter button below map'),
            ),
          ),
        ],
      ),
    );
  }
}
