import 'package:material_ui/material_ui.dart';

import 'cupertino_ui_controls.dart';
import 'material_ui_controls.dart';
import 'sdk_material_controls.dart';

/// The SDK Material, `material_ui` and `cupertino_ui` controls side by side,
/// in sections keyed `sdk`, `material` and `cupertino` whose controls share
/// keys.
class MixedControls extends StatelessWidget {
  const MixedControls({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 24,
      runSpacing: 24,
      children: [
        _Section(
          title: 'SDK Material',
          child: SdkMaterialControls(key: ValueKey('sdk')),
        ),
        _Section(
          title: 'material_ui',
          child: MaterialUiControls(key: ValueKey('material')),
        ),
        _Section(
          title: 'cupertino_ui',
          child: CupertinoUiControls(key: ValueKey('cupertino')),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  static const _width = 320.0;

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(title), child],
      ),
    );
  }
}
