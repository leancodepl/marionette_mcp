import 'package:material_ui/material_ui.dart';

/// One control of each kind from `material_ui`, with keys that repeat in
/// `CupertinoUiControls`, and a status line that shows what the controls
/// received.
///
/// The adaptive toggles sit under an iOS theme, so they build their
/// Cupertino look on any host.
class MaterialUiControls extends StatefulWidget {
  const MaterialUiControls({super.key});

  @override
  State<MaterialUiControls> createState() => _MaterialUiControlsState();
}

class _MaterialUiControlsState extends State<MaterialUiControls> {
  var _saves = 0;
  var _name = '';
  bool? _terms;
  var _notifications = false;
  String? _size;
  bool? _adaptiveCheckbox = false;
  var _adaptiveSwitch = true;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          tristate: true,
          value: _terms,
          onChanged: (terms) => setState(() => _terms = terms),
        ),
        Switch(
          key: const ValueKey('notifications'),
          value: _notifications,
          onChanged: (on) => setState(() => _notifications = on),
        ),
        RadioGroup<String>(
          groupValue: _size,
          onChanged: (size) => setState(() => _size = size),
          child: const Row(
            children: [
              Radio(key: ValueKey('size_s'), value: 's'),
              Radio(key: ValueKey('size_m'), value: 'm'),
            ],
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(platform: TargetPlatform.iOS),
          child: Row(
            children: [
              Checkbox.adaptive(
                key: const ValueKey('adaptive_checkbox'),
                value: _adaptiveCheckbox,
                onChanged: (checked) =>
                    setState(() => _adaptiveCheckbox = checked),
              ),
              Switch.adaptive(
                key: const ValueKey('adaptive_switch'),
                value: _adaptiveSwitch,
                onChanged: (on) => setState(() => _adaptiveSwitch = on),
              ),
            ],
          ),
        ),
        Text(
          'saves: $_saves, name: "$_name", terms: $_terms, '
          'notifications: $_notifications, size: $_size, '
          'adaptive: $_adaptiveCheckbox/$_adaptiveSwitch',
          key: const ValueKey('status'),
        ),
      ],
    );
  }
}
