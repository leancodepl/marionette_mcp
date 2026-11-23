import 'package:flutter/material.dart';

/// Controls from the Flutter SDK's Material library, which core supports
/// without an integration, next to the extracted libraries in one app.
///
/// They bring the SDK's Material ancestor and localizations, which a
/// `material_ui` app does not provide.
class SdkMaterialControls extends StatefulWidget {
  const SdkMaterialControls({super.key});

  @override
  State<SdkMaterialControls> createState() => _SdkMaterialControlsState();
}

class _SdkMaterialControlsState extends State<SdkMaterialControls> {
  var _saves = 0;
  var _name = '';
  bool? _terms = false;

  @override
  Widget build(BuildContext context) {
    return Localizations.override(
      context: context,
      delegates: const [DefaultMaterialLocalizations.delegate],
      child: Material(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              key: const ValueKey('save'),
              onPressed: () => setState(() => _saves++),
              child: const Text('Save'),
            ),
            TextField(
              key: const ValueKey('name'),
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (name) => setState(() => _name = name),
            ),
            Checkbox(
              key: const ValueKey('terms'),
              value: _terms,
              onChanged: (terms) => setState(() => _terms = terms),
            ),
            Text(
              'saves: $_saves, name: "$_name", terms: $_terms',
              key: const ValueKey('status'),
            ),
          ],
        ),
      ),
    );
  }
}
