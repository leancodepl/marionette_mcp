import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// §1b GPU-backed platform view — [GoogleMap] ([MapView] / Metal map surface).
///
/// Reports the camera (center and zoom) and marker taps as Flutter text, so
/// native gestures on the map (native_pinch, native_swipe, native_tap via
/// native_map_flutter_rect) and native_set_location (my-location button) can
/// be verified. Needs a Maps API key: without one the map is not initialized
/// (blank, no marker, no camera events).
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
  CameraPosition _camera = GoogleMapsPlatformViewScreen.initialCamera;
  int _markerTaps = 0;

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
              'Needs a Maps API key (google.maps.api.key in '
              'android/local.properties, GOOGLE_MAPS_API_KEY in Info.plist): '
              'without one the map stays blank and does not react.',
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
                  child: GoogleMap(
                    initialCameraPosition:
                        GoogleMapsPlatformViewScreen.initialCamera,
                    // The blue dot and button need the location permission
                    // (native_permissions grant location).
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: true,
                    onCameraMove: (camera) => setState(() => _camera = camera),
                    markers: {
                      Marker(
                        markerId: const MarkerId('warsaw'),
                        position:
                            GoogleMapsPlatformViewScreen.initialCamera.target,
                        infoWindow: const InfoWindow(title: 'Warsaw'),
                        onTap: () => setState(() => _markerTaps++),
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Camera: ${_camera.target.latitude.toStringAsFixed(4)}, '
              '${_camera.target.longitude.toStringAsFixed(4)} · '
              'zoom ${_camera.zoom.toStringAsFixed(2)}\n'
              'Marker taps: $_markerTaps',
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
