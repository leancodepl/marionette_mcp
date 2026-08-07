import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class InAppCameraScreen extends StatefulWidget {
  const InAppCameraScreen({super.key});

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  XFile? _capturedImage;
  bool _capturing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _errorMessage = 'In-app camera is not supported on web.';
      return;
    }
    _initializeFuture = _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras found on this device.');
    }

    final camera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
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

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing || controller.value.isTakingPicture) {
      return;
    }

    setState(() => _capturing = true);
    try {
      final image = await controller.takePicture();
      if (!mounted) {
        return;
      }
      setState(() => _capturedImage = image);
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
      }
    }
  }

  void _retake() {
    setState(() => _capturedImage = null);
  }

  void _usePhoto() {
    final image = _capturedImage;
    if (image != null) {
      Navigator.of(context).pop(image);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return CameraUnavailableScaffold(message: _errorMessage!);
    }

    if (_capturedImage != null) {
      return CameraPhotoPreviewScaffold(
        image: _capturedImage!,
        onRetake: _retake,
        onUsePhoto: _usePhoto,
      );
    }

    return CameraCaptureScaffold(
      initializeFuture: _initializeFuture,
      controller: _controller,
      capturing: _capturing,
      onCapture: _capture,
    );
  }
}

class CameraUnavailableScaffold extends StatelessWidget {
  const CameraUnavailableScaffold({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take photo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class CameraPhotoPreviewScaffold extends StatelessWidget {
  const CameraPhotoPreviewScaffold({
    super.key,
    required this.image,
    required this.onRetake,
    required this.onUsePhoto,
  });

  final XFile image;
  final VoidCallback onRetake;
  final VoidCallback onUsePhoto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: Image.file(
              File(image.path),
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRetake,
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onUsePhoto,
                    child: const Text('Use photo'),
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

class CameraCaptureScaffold extends StatelessWidget {
  const CameraCaptureScaffold({
    super.key,
    required this.initializeFuture,
    required this.controller,
    required this.capturing,
    required this.onCapture,
  });

  final Future<void>? initializeFuture;
  final CameraController? controller;
  final bool capturing;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take photo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: FutureBuilder<void>(
        future: initializeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || controller == null || !controller!.value.isInitialized) {
            final message = snapshot.error?.toString() ?? 'Camera unavailable.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: CameraPreview(controller!),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton.icon(
                  onPressed: capturing ? null : onCapture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Capture'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
