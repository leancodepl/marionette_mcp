import 'package:cupertino_ui/cupertino_ui.dart';

/// One control of each kind from `cupertino_ui`, with keys that repeat in
/// `MaterialUiControls`, and a status line that shows what the controls
/// received.
class CupertinoUiControls extends StatefulWidget {
  const CupertinoUiControls({super.key});

  @override
  State<CupertinoUiControls> createState() => _CupertinoUiControlsState();
}

class _CupertinoUiControlsState extends State<CupertinoUiControls> {
  var _saves = 0;
  var _name = '';
  bool? _terms;
  var _notifications = false;
  String? _size;
  var _period = 'day';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupertinoButton(
          key: const ValueKey('save'),
          onPressed: () => setState(() => _saves++),
          child: const Text('Save'),
        ),
        CupertinoTextField(
          key: const ValueKey('name'),
          placeholder: 'Name',
          onChanged: (name) => setState(() => _name = name),
        ),
        CupertinoCheckbox(
          key: const ValueKey('terms'),
          tristate: true,
          value: _terms,
          onChanged: (terms) => setState(() => _terms = terms),
        ),
        CupertinoSwitch(
          key: const ValueKey('notifications'),
          value: _notifications,
          onChanged: (on) => setState(() => _notifications = on),
        ),
        RadioGroup<String>(
          groupValue: _size,
          onChanged: (size) => setState(() => _size = size),
          child: const Row(
            children: [
              CupertinoRadio(key: ValueKey('size_s'), value: 's'),
              CupertinoRadio(key: ValueKey('size_m'), value: 'm'),
            ],
          ),
        ),
        CupertinoSlidingSegmentedControl<String>(
          key: const ValueKey('period'),
          groupValue: _period,
          onValueChanged: (period) {
            if (period case final period?) setState(() => _period = period);
          },
          children: const {'day': Text('Day'), 'week': Text('Week')},
        ),
        Text(
          'saves: $_saves, name: "$_name", terms: $_terms, '
          'notifications: $_notifications, size: $_size, period: $_period',
          key: const ValueKey('status'),
        ),
      ],
    );
  }
}
