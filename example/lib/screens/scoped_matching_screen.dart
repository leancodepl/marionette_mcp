import 'package:flutter/material.dart';

/// Screens that repeat the same keys across identical subtrees, for the
/// `ancestor_keys` field of the matcher-based tools.
///
/// Every scenario reports what was hit in the `scoped.status` text, so an
/// agent (or a test) can check that a scoped tap landed where it was aimed.
class ScopedMatchingScreen extends StatefulWidget {
  const ScopedMatchingScreen({super.key});

  @override
  State<ScopedMatchingScreen> createState() => _ScopedMatchingScreenState();
}

enum _Scenario {
  grid,
  lazyList,
  sections,
  columns,
  sessions,
  gestures,
  discovery
}

class _ScopedMatchingScreenState extends State<ScopedMatchingScreen> {
  _Scenario _scenario = _Scenario.grid;
  String _status = 'Nothing tapped yet';

  void _report(String status) => setState(() => _status = status);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scoped Matching'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (scenario, label) in const [
                  (_Scenario.grid, 'Grid'),
                  (_Scenario.lazyList, 'Lazy list'),
                  (_Scenario.sections, 'Sections'),
                  (_Scenario.columns, 'Columns'),
                  (_Scenario.sessions, 'Sessions'),
                  (_Scenario.gestures, 'Gestures'),
                  (_Scenario.discovery, 'Discovery'),
                ])
                  ChoiceChip(
                    key: ValueKey('scoped.show.${scenario.name}'),
                    label: Text(label),
                    selected: _scenario == scenario,
                    onSelected: (_) => setState(() => _scenario = scenario),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              key: const ValueKey('scoped.status'),
              _status,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(),
          Expanded(
            child: switch (_scenario) {
              _Scenario.grid => _GridScenario(onReport: _report),
              _Scenario.lazyList => _LazyListScenario(onReport: _report),
              _Scenario.sections => _SectionsScenario(onReport: _report),
              _Scenario.columns => _ColumnsScenario(onReport: _report),
              _Scenario.sessions => _SessionsScenario(onReport: _report),
              _Scenario.gestures => _GesturesScenario(onReport: _report),
              _Scenario.discovery => _DiscoveryScenario(onReport: _report),
            },
          ),
        ],
      ),
    );
  }
}

/// Two sessions that embed the same grid, so even the cell keys repeat and
/// only `["session_2", "grid.cell_2"]` names one cell. Below: a key repeated
/// on two adjacent levels, and two cards with identical text fields.
class _GridScenario extends StatelessWidget {
  const _GridScenario({required this.onReport});

  final ValueChanged<String> onReport;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final session in ['session_1', 'session_2'])
                Expanded(
                  child: Card(
                    key: ValueKey(session),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Text(session),
                          for (final cell in ['grid.cell_1', 'grid.cell_2'])
                            Padding(
                              key: ValueKey(cell),
                              padding: const EdgeInsets.all(4),
                              child: ElevatedButton(
                                key: const ValueKey('cell.joinButton'),
                                onPressed: () =>
                                    onReport('Joined $session · $cell'),
                                onLongPress: () =>
                                    onReport('Long-pressed $session · $cell'),
                                child: Text('Join ${cell.split('_').last}'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            key: const ValueKey('node'),
            padding: const EdgeInsets.all(8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                ElevatedButton(
                  key: const ValueKey('node.button'),
                  onPressed: () => onReport('Tapped the outer node'),
                  child: const Text('Outer node'),
                ),
                Container(
                  key: const ValueKey('node'),
                  padding: const EdgeInsets.all(8),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: ElevatedButton(
                    key: const ValueKey('node.button'),
                    onPressed: () => onReport('Tapped the inner node'),
                    child: const Text('Inner node'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final card in ['card_a', 'card_b'])
            Card(
              key: ValueKey(card),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  key: const ValueKey('card.field'),
                  decoration: InputDecoration(labelText: 'Note for $card'),
                  onChanged: (value) => onReport('$card: $value'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A lazily built list whose rows repeat the same `row.action` key, so a row
/// far down does not exist until the list scrolls to it.
class _LazyListScenario extends StatelessWidget {
  const _LazyListScenario({required this.onReport});

  final ValueChanged<String> onReport;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 30,
      itemBuilder: (context, index) => SizedBox(
        key: ValueKey('row_$index'),
        height: 72,
        child: Center(
          child: TextButton(
            key: const ValueKey('row.action'),
            onPressed: () => onReport('Action $index tapped'),
            child: Text('Action $index'),
          ),
        ),
      ),
    );
  }
}

/// Two sections of one page that repeat the same item keys. The list that
/// moves an item sits above its section, not inside it.
class _SectionsScenario extends StatelessWidget {
  const _SectionsScenario({required this.onReport});

  final ValueChanged<String> onReport;

  @override
  Widget build(BuildContext context) {
    Widget section(String name, int itemCount) {
      return KeyedSubtree(
        key: ValueKey(name),
        child: SliverList.builder(
          itemCount: itemCount,
          itemBuilder: (context, index) => ListTile(
            key: ValueKey('item_$index'),
            title: Text('$name · item $index'),
            onTap: () => onReport('$name · item_$index'),
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: ListTile(title: Text('Section A'))),
        section('section_a', 12),
        const SliverToBoxAdapter(child: ListTile(title: Text('Section B'))),
        section('section_b', 30),
      ],
    );
  }
}

/// Three identical lists side by side, each reporting its scroll offset, so
/// it shows which one a scoped scroll_to dragged.
class _ColumnsScenario extends StatefulWidget {
  const _ColumnsScenario({required this.onReport});

  final ValueChanged<String> onReport;

  @override
  State<_ColumnsScenario> createState() => _ColumnsScenarioState();
}

class _ColumnsScenarioState extends State<_ColumnsScenario> {
  final _controllers = List.generate(3, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offsets = [
      for (final controller in _controllers)
        controller.hasClients ? controller.offset.round() : 0,
    ];

    return Column(
      children: [
        Text(
          key: const ValueKey('columns.offsets'),
          'Offsets: ${offsets.join(' / ')}',
        ),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey('grid.cell_${i + 1}'),
                    child: ListView.builder(
                      controller: _controllers[i],
                      itemCount: 20,
                      itemBuilder: (context, index) => ListTile(
                        key: ValueKey('item_$index'),
                        title: Text('${i + 1}·$index'),
                        onTap: () =>
                            widget.onReport('Column ${i + 1} · item_$index'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Two cards whose gesture pads repeat the same keys, and a tappable `pick`
/// nested in another `pick` whose centre lies outside the inner one.
///
/// Deliberately without a Scrollable, so a scoped scroll_to here shows the
/// missing-scope error rather than a missing-Scrollable one.
class _GesturesScenario extends StatelessWidget {
  const _GesturesScenario({required this.onReport});

  final ValueChanged<String> onReport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget pad(String key, String label, Widget Function(Widget) wrap) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: wrap(
          Container(
            key: ValueKey(key),
            height: 64,
            alignment: Alignment.center,
            color: colors.secondaryContainer,
            child: Text(label),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final card in ['gesture_a', 'gesture_b'])
            Card(
              key: ValueKey(card),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    Text(card),
                    Row(
                      children: [
                        Expanded(
                          child: pad(
                            'gesture.double',
                            'Double',
                            (child) => GestureDetector(
                              onDoubleTap: () => onReport('$card: double tap'),
                              child: child,
                            ),
                          ),
                        ),
                        Expanded(
                          child: pad(
                            'gesture.secondary',
                            'Right-click',
                            (child) => GestureDetector(
                              onSecondaryTap: () =>
                                  onReport('$card: secondary tap'),
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: pad(
                            'gesture.swipe',
                            'Swipe',
                            (child) => _SwipeDetector(
                              onSwipe: (direction) =>
                                  onReport('$card: swipe $direction'),
                              child: child,
                            ),
                          ),
                        ),
                        Expanded(
                          child: pad(
                            'gesture.pinch',
                            'Pinch',
                            (child) => _PinchDetector(
                              onPinch: (scale) => onReport(
                                '$card: pinch ${scale > 1 ? 'in' : 'out'}',
                              ),
                              child: child,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          GestureDetector(
            key: const ValueKey('pick'),
            onTap: () => onReport('Tapped the outer pick'),
            child: Container(
              height: 96,
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.all(8),
              color: colors.surfaceContainerHighest,
              child: GestureDetector(
                key: const ValueKey('pick'),
                onTap: () => onReport('Tapped the inner pick'),
                child: Container(
                  width: 120,
                  height: 40,
                  alignment: Alignment.center,
                  color: colors.primaryContainer,
                  child: const Text('Inner pick'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeDetector extends StatefulWidget {
  const _SwipeDetector({required this.onSwipe, required this.child});

  final ValueChanged<String> onSwipe;
  final Widget child;

  @override
  State<_SwipeDetector> createState() => _SwipeDetectorState();
}

class _SwipeDetectorState extends State<_SwipeDetector> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: (_) => _dx = 0,
      onHorizontalDragUpdate: (details) => _dx += details.delta.dx,
      onHorizontalDragEnd: (_) => widget.onSwipe(_dx > 0 ? 'right' : 'left'),
      child: widget.child,
    );
  }
}

class _PinchDetector extends StatefulWidget {
  const _PinchDetector({required this.onPinch, required this.child});

  final ValueChanged<double> onPinch;
  final Widget child;

  @override
  State<_PinchDetector> createState() => _PinchDetectorState();
}

class _PinchDetectorState extends State<_PinchDetector> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (_) => _scale = 1,
      onScaleUpdate: (details) => _scale = details.scale,
      onScaleEnd: (_) => widget.onPinch(_scale),
      child: widget.child,
    );
  }
}

/// Three sessions side by side, each embedding the same lazily built list, so
/// `["session_3", "row_20"]` names a row whose last link is not built yet and
/// whose session is not the first one in the tree.
class _SessionsScenario extends StatefulWidget {
  const _SessionsScenario({required this.onReport});

  final ValueChanged<String> onReport;

  @override
  State<_SessionsScenario> createState() => _SessionsScenarioState();
}

class _SessionsScenarioState extends State<_SessionsScenario> {
  final _controllers = List.generate(3, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offsets = [
      for (final controller in _controllers)
        controller.hasClients ? controller.offset.round() : 0,
    ];

    return Column(
      children: [
        Text(
          key: const ValueKey('sessions.offsets'),
          'Offsets: ${offsets.join(' / ')}',
        ),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey('session_${i + 1}'),
                    child: ListView.builder(
                      controller: _controllers[i],
                      itemCount: 30,
                      itemBuilder: (context, index) => SizedBox(
                        key: ValueKey('row_$index'),
                        height: 64,
                        child: Center(
                          child: TextButton(
                            key: const ValueKey('row.action'),
                            onPressed: () => widget.onReport(
                              'session_${i + 1} · Action $index',
                            ),
                            child: Text('${i + 1}·$index'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Edge cases of a scoped get_interactive_elements: a scope key sitting on an
/// interactive widget, which must list itself, and a cell the user cannot
/// reach, which must list nothing even though an identical cell next to it
/// is reachable.
class _DiscoveryScenario extends StatelessWidget {
  const _DiscoveryScenario({required this.onReport});

  final ValueChanged<String> onReport;

  @override
  Widget build(BuildContext context) {
    Widget cell(String key, String label) {
      return Column(
        key: ValueKey(key),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          ElevatedButton(
            key: const ValueKey('disc.action'),
            onPressed: () => onReport('Tapped $key'),
            child: const Text('Act'),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            key: const ValueKey('solo.button'),
            onPressed: () => onReport('Tapped solo.button'),
            child: const Text('A scope key on the button itself'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: cell('disc.cell_1', 'Reachable')),
              Expanded(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.4,
                    child: cell('disc.cell_2', 'Not reachable'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
