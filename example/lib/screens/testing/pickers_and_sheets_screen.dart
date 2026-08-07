import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

/// §4 Pickers and sheets — OS-owned file/photo/camera/share UI.
class PickersAndSheetsScreen extends StatefulWidget {
  const PickersAndSheetsScreen({super.key});

  @override
  State<PickersAndSheetsScreen> createState() => _PickersAndSheetsScreenState();
}

class _PickersAndSheetsScreenState extends State<PickersAndSheetsScreen> {
  final _imagePicker = ImagePicker();
  bool _busy = false;
  String? _lastResult;

  Future<void> _run(String action, Future<void> Function() task) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() => _lastResult = '$action failed: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _ensurePermission(Permission permission) async {
    var status = await permission.status;
    if (status.isGranted || status.isLimited) {
      return true;
    }

    status = await permission.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> _pickFile() async {
    await _run('File picker', () async {
      final result = await FilePicker.platform.pickFiles();
      if (!mounted) return;

      if (result == null || result.files.isEmpty) {
        setState(() => _lastResult = 'File picker cancelled');
        return;
      }

      final file = result.files.single;
      setState(() => _lastResult = 'File: ${file.name}');
    });
  }

  Future<void> _pickPhoto() async {
    await _run('Photo picker', () async {
      if (!kIsWeb && !await _ensurePermission(Permission.photos)) {
        if (mounted) {
          setState(() => _lastResult = 'Photos permission denied');
        }
        return;
      }

      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (!mounted) return;

      setState(
        () => _lastResult = image == null
            ? 'Photo picker cancelled'
            : 'Photo: ${image.name}',
      );
    });
  }

  Future<void> _takePhoto() async {
    await _run('Camera capture', () async {
      if (kIsWeb) {
        if (mounted) {
          setState(() => _lastResult = 'Camera capture is not supported on web');
        }
        return;
      }

      if (!await _ensurePermission(Permission.camera)) {
        if (mounted) {
          setState(() => _lastResult = 'Camera permission denied');
        }
        return;
      }

      final image = await _imagePicker.pickImage(source: ImageSource.camera);
      if (!mounted) return;

      setState(
        () => _lastResult = image == null
            ? 'Camera capture cancelled'
            : 'Photo: ${image.name}',
      );
    });
  }

  Future<void> _share(BuildContext buttonContext) async {
    await _run('Share sheet', () async {
      final box = buttonContext.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;

      final result = await SharePlus.instance.share(
        ShareParams(
          text: 'Marionette MCP example — pickers & sheets demo',
          sharePositionOrigin: origin,
        ),
      );
      if (!mounted) return;

      setState(() => _lastResult = 'Share: ${result.status.name}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pickers & sheets'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Opens native pickers and sheets via file_picker, image_picker, '
              'and share_plus. Not part of the Flutter widget tree — use the '
              'native lane while a sheet is open.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (_lastResult != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _lastResult!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ListTile(
            title: const Text('Files'),
            subtitle: const Text('SAF DocumentsUI / UIDocumentPickerViewController'),
            trailing: FilledButton(
              onPressed: _busy ? null : _pickFile,
              child: const Text('Pick file'),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Photos'),
            subtitle: const Text('Android photo picker / PHPickerViewController'),
            trailing: FilledButton(
              onPressed: _busy ? null : _pickPhoto,
              child: const Text('Pick photo'),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Camera capture'),
            subtitle: const Text('Camera intent / UIImagePickerController'),
            trailing: FilledButton(
              onPressed: _busy ? null : _takePhoto,
              child: const Text('Take photo'),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Share'),
            subtitle: const Text('Intent chooser / UIActivityViewController'),
            trailing: Builder(
              builder: (buttonContext) => FilledButton(
                onPressed: _busy ? null : () => _share(buttonContext),
                child: const Text('Share'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
