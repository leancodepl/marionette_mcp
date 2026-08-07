import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// §1b GPU-backed platform view — [CameraPreview] ([TextureView] / preview layer).
class CameraPlatformViewScreen extends StatefulWidget {
  const CameraPlatformViewScreen({super.key});

  @override
  State<CameraPlatformViewScreen> createState() =>
      _CameraPlatformViewScreenState();
}

class _CameraPlatformViewScreenState extends State<CameraPlatformViewScreen> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _errorMessage = 'Camera preview is not supported on web.';
      return;
    }
    _initializeFuture = _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      throw StateError(
        'Camera permission is required. Grant it in Settings and reopen this screen.',
      );
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras found on this device.');
    }

    final camera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _controller = controller;
    await controller.initialize();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera preview'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Live camera feed via the camera plugin (GPU / TextureView platform view).',
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
                  child: _CameraPreviewBody(
                    errorMessage: _errorMessage,
                    initializeFuture: _initializeFuture,
                    controller: _controller,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () {},
              child: const Text('Flutter button below preview'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewBody extends StatelessWidget {
  const _CameraPreviewBody({
    required this.errorMessage,
    required this.initializeFuture,
    required this.controller,
  });

  final String? errorMessage;
  final Future<void>? initializeFuture;
  final CameraController? controller;

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(errorMessage!, textAlign: TextAlign.center),
        ),
      );
    }

    return FutureBuilder<void>(
      future: initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final activeController = controller;
        if (snapshot.hasError ||
            activeController == null ||
            !activeController.value.isInitialized) {
          final message = snapshot.error?.toString() ?? 'Camera unavailable.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(message, textAlign: TextAlign.center),
            ),
          );
        }

        return ColoredBox(
          color: Colors.black,
          child: Center(child: CameraPreview(activeController)),
        );
      },
    );
  }
}
