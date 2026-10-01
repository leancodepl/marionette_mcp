import 'package:flutter/material.dart';

/// A tiny stand-in for an app's design system, used to show how
/// `MarionetteConfiguration` recognizes custom widgets. See `main.dart`.

/// Base class of the app's buttons. Marionette recognizes every subclass
/// with a single `element.widget is DsButton` check.
abstract class DsButton extends StatelessWidget {
  const DsButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  Color backgroundColor(ColorScheme colors);
  Color foregroundColor(ColorScheme colors);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor(colors),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(color: foregroundColor(colors))),
      ),
    );
  }
}

class DsPrimaryButton extends DsButton {
  const DsPrimaryButton(
      {super.key, required super.label, required super.onTap});

  @override
  Color backgroundColor(ColorScheme colors) => colors.primary;

  @override
  Color foregroundColor(ColorScheme colors) => colors.onPrimary;
}

class DsSecondaryButton extends DsButton {
  const DsSecondaryButton({
    super.key,
    required super.label,
    required super.onTap,
  });

  @override
  Color backgroundColor(ColorScheme colors) => colors.secondaryContainer;

  @override
  Color foregroundColor(ColorScheme colors) => colors.onSecondaryContainer;
}

/// A generic select. Tapping it moves to the next option.
///
/// Its runtime type is `DsSelect<String>`, `DsSelect<int>`, … — a Type-based
/// check (`type == DsSelect`) matches none of them, `is DsSelect` matches all.
class DsSelect<T> extends StatelessWidget {
  const DsSelect({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> options;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  String get selectedLabel => labelOf(value);

  @override
  Widget build(BuildContext context) {
    final next = options[(options.indexOf(value) + 1) % options.length];
    return GestureDetector(
      onTap: () => onChanged(next),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selectedLabel),
            const Icon(Icons.unfold_more, size: 18),
          ],
        ),
      ),
    );
  }
}

/// A list tile that is interactive only when [onTap] is set.
class DsTile extends StatelessWidget {
  const DsTile({super.key, required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          if (onTap != null) const Icon(Icons.chevron_right),
        ],
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}
