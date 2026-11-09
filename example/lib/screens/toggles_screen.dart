import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../custom_widgets.dart';

/// Every kind of toggle whose state `get_interactive_elements` reports:
/// checkboxes and switches as `value`, radios as `selected`.
class TogglesScreen extends StatefulWidget {
  const TogglesScreen({super.key});

  @override
  State<TogglesScreen> createState() => _TogglesScreenState();
}

class _TogglesScreenState extends State<TogglesScreen> {
  bool _switch = false;
  bool _adaptiveSwitch = false;
  bool _switchTile = false;
  bool _cupertinoSwitch = false;
  // Tristate: null is the indeterminate "mixed" state.
  bool? _cupertinoCheckbox;
  String _cupertinoRadio = 'a';
  int _legacyRadio = 1;
  bool _rememberMe = false;
  bool _darkMode = false;

  @override
  Widget build(BuildContext context) {
    final sectionStyle = Theme.of(context).textTheme.titleSmall;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Toggles'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Material', style: sectionStyle),
          Row(
            children: [
              Switch(
                key: const ValueKey('switch'),
                value: _switch,
                onChanged: (value) => setState(() => _switch = value),
              ),
              const Text('Switch'),
            ],
          ),
          Row(
            children: [
              Switch.adaptive(
                key: const ValueKey('switch_adaptive'),
                value: _adaptiveSwitch,
                onChanged: (value) => setState(() => _adaptiveSwitch = value),
              ),
              const Text('Switch.adaptive'),
            ],
          ),
          SwitchListTile(
            key: const ValueKey('switch_tile'),
            title: const Text('SwitchListTile'),
            value: _switchTile,
            onChanged: (value) => setState(() => _switchTile = value),
          ),
          const Row(
            children: [
              Checkbox(
                key: ValueKey('checkbox_disabled'),
                value: true,
                onChanged: null,
              ),
              Text('Disabled Checkbox'),
            ],
          ),
          const Divider(),
          Text('Cupertino', style: sectionStyle),
          Row(
            children: [
              CupertinoSwitch(
                key: const ValueKey('cupertino_switch'),
                value: _cupertinoSwitch,
                onChanged: (value) => setState(() => _cupertinoSwitch = value),
              ),
              const SizedBox(width: 12),
              const Text('CupertinoSwitch'),
            ],
          ),
          Row(
            children: [
              CupertinoCheckbox(
                key: const ValueKey('cupertino_checkbox'),
                tristate: true,
                value: _cupertinoCheckbox,
                onChanged: (value) =>
                    setState(() => _cupertinoCheckbox = value),
              ),
              const Text('CupertinoCheckbox (tristate)'),
            ],
          ),
          RadioGroup<String>(
            groupValue: _cupertinoRadio,
            onChanged: (value) =>
                setState(() => _cupertinoRadio = value ?? _cupertinoRadio),
            child: const Row(
              children: [
                CupertinoRadio<String>(
                  key: ValueKey('cupertino_radio_a'),
                  value: 'a',
                ),
                Text('A'),
                SizedBox(width: 12),
                CupertinoRadio<String>(
                  key: ValueKey('cupertino_radio_b'),
                  value: 'b',
                ),
                Text('B'),
              ],
            ),
          ),
          const Divider(),
          Text('Radio with groupValue (pre-RadioGroup API)',
              style: sectionStyle),
          Row(
            children: [
              for (final option in [1, 2]) ...[
                Radio<int>(
                  key: ValueKey('legacy_radio_$option'),
                  value: option,
                  // Apps on Flutter versions before RadioGroup use these.
                  // ignore: deprecated_member_use
                  groupValue: _legacyRadio,
                  // ignore: deprecated_member_use
                  onChanged: (value) =>
                      setState(() => _legacyRadio = value ?? _legacyRadio),
                ),
                Text('Option $option'),
              ],
            ],
          ),
          const Divider(),
          Text('Wrappers', style: sectionStyle),
          // The InkWell passes traversal through, so the Checkbox is listed on
          // its own and the InkWell must not claim its state.
          InkWell(
            key: const ValueKey('remember_me_row'),
            onTap: () => setState(() => _rememberMe = !_rememberMe),
            child: Row(
              children: [
                Checkbox(
                  key: const ValueKey('remember_me_checkbox'),
                  value: _rememberMe,
                  onChanged: (value) =>
                      setState(() => _rememberMe = value ?? false),
                ),
                const Text('Remember me (InkWell row)'),
              ],
            ),
          ),
          DsToggle(
            key: const ValueKey('ds_toggle'),
            label: 'Dark mode (DsToggle)',
            value: _darkMode,
            onChanged: (value) => setState(() => _darkMode = value),
          ),
        ],
      ),
    );
  }
}
