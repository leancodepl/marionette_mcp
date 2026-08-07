import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../screens/in_app_camera_screen.dart';

class ProfilePictureSection extends StatefulWidget {
  const ProfilePictureSection({super.key});

  @override
  State<ProfilePictureSection> createState() => _ProfilePictureSectionState();
}

class _ProfilePictureSectionState extends State<ProfilePictureSection> {
  final _imagePicker = ImagePicker();
  XFile? _profilePicture;
  bool _busy = false;

  Future<bool> _ensurePermission(Permission permission) async {
    var status = await permission.status;
    if (status.isGranted || status.isLimited) {
      return true;
    }

    status = await permission.request();
    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${permission.title} permission is required.'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: openAppSettings,
        ),
      ),
    );
    return false;
  }

  Future<void> _pickFromGallery() async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);
    try {
      if (!kIsWeb && !await _ensurePermission(Permission.photos)) {
        return;
      }

      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (!mounted || image == null) {
        return;
      }

      setState(() => _profilePicture = image);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _takePhoto() async {
    if (_busy) {
      return;
    }

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('In-app camera is not supported on web.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      if (!await _ensurePermission(Permission.camera)) {
        return;
      }

      final image = await Navigator.of(context).push<XFile>(
        MaterialPageRoute(builder: (_) => const InAppCameraScreen()),
      );
      if (!mounted || image == null) {
        return;
      }

      setState(() => _profilePicture = image);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _removePhoto() {
    setState(() => _profilePicture = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Profile picture',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Center(child: ProfilePictureAvatar(image: _profilePicture)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
            ),
          ],
        ),
        if (_profilePicture != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _removePhoto,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove photo'),
          ),
        ],
        if (_profilePicture != null) ...[
          const SizedBox(height: 8),
          Text(
            'Selected: ${_profilePicture!.name}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class ProfilePictureAvatar extends StatelessWidget {
  const ProfilePictureAvatar({super.key, this.image});

  final XFile? image;

  @override
  Widget build(BuildContext context) {
    final selectedImage = image;
    if (selectedImage == null) {
      return CircleAvatar(
        radius: 48,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person_outline,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (kIsWeb) {
      return CircleAvatar(
        radius: 48,
        backgroundImage: NetworkImage(selectedImage.path),
      );
    }

    return CircleAvatar(
      radius: 48,
      backgroundImage: FileImage(File(selectedImage.path)),
    );
  }
}

extension on Permission {
  String get title => switch (this) {
        Permission.camera => 'Camera',
        Permission.photos => 'Photos',
        _ => 'Required',
      };
}
