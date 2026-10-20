import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/styles.dart';

part 'tabs.scopes.dart';

/// One tab of [Tabs]: its [label] and the [children] of its panel.
class TabItem {
  const TabItem(this.id, this.label, this.children);

  final String id;
  final String label;
  final List<Component> children;
}

/// A tab switcher built from radio inputs and CSS alone, so every panel is in
/// the HTML for crawlers and the page needs no script for it.
///
/// The rules match tabs by position, so they hold for any group of up to
/// [maxTabs] tabs, and several groups can share a page as long as their
/// [name]s differ.
@scopedCss
class Tabs extends StatelessComponent {
  const Tabs({
    required this.name,
    required this.groupLabel,
    required this.tabs,
    super.key,
  });

  /// The radio group's name; unique per page.
  final String name;

  /// What the group switches between, for assistive technology.
  final String groupLabel;

  /// At most [maxTabs].
  final List<TabItem> tabs;

  static const maxTabs = 8;

  static const _class = _$TabsScope;

  static final _root = _class.root;
  static final _input = _class('input');
  static final _list = _class('list');
  static final _tab = _class('tab');
  static final _panels = _class('panels');
  static final _panel = _class('panel');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector).styles(position: const .relative(), minWidth: .zero),
    css(_input.selector).styles(
      position: const .absolute(),
      width: 1.px,
      height: 1.px,
      margin: .all((-1).px),
      opacity: 0,
      overflow: .hidden,
      raw: {'clip': 'rect(0 0 0 0)'},
    ),
    css(_list.selector).styles(
      display: .flex,
      maxWidth: 100.percent,
      padding: .all(0.3.rem),
      margin: .only(bottom: 1.rem),
      border: hairline(borderColor),
      radius: .circular(14.px),
      flexWrap: .wrap,
      gap: .all(0.25.rem),
      backgroundColor: surfaceColor,
      raw: {'width': 'fit-content'},
    ),
    css(_tab.selector, [
      css('&').styles(
        padding: .symmetric(vertical: 0.45.rem, horizontal: 0.9.rem),
        radius: .circular(10.px),
        cursor: .pointer,
        transition: .combine([
          .new('background-color', duration: 150.ms, curve: .ease),
          .new('color', duration: 150.ms, curve: .ease),
        ]),
        color: text2Color,
        fontSize: 0.9.rem,
        fontWeight: .w500,
      ),
      css('&:hover').styles(color: textColor),
    ]),
    // A panel may hold a wide code sample, which scrolls instead.
    css(_panel.selector).styles(display: .none, minWidth: .zero),
    // The checked radio selects its tab and panel by position.
    for (var i = 1; i <= maxTabs; i++) ...[
      css(
        '${_input.selector}:nth-of-type($i):checked ~ ${_list.selector} '
        '${_tab.selector}:nth-of-type($i)',
      ).styles(color: accentInkColor, backgroundColor: accentColor),
      css(
        '${_input.selector}:nth-of-type($i):focus-visible ~ ${_list.selector} '
        '${_tab.selector}:nth-of-type($i)',
      ).styles(
        outline: .new(
          color: accentColor,
          style: .solid,
          width: .new(2.px),
          offset: 2.px,
        ),
      ),
      css(
        '${_input.selector}:nth-of-type($i):checked ~ ${_panels.selector} '
        '> ${_panel.selector}:nth-of-type($i)',
      ).styles(display: .grid, gap: .all(1.rem)),
    ],
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: _root.name, [
      for (final (index, tab) in tabs.indexed)
        input(
          type: .radio,
          name: name,
          id: '$name-${tab.id}',
          classes: _input.name,
          checked: index == 0 ? true : null,
        ),
      div(
        classes: _list.name,
        // Radio inputs with labels are what assistive technology already
        // sees; a tablist would promise tab roles the labels do not have.
        attributes: {'role': 'group', 'aria-label': groupLabel},
        [
          for (final tab in tabs)
            label(
              classes: _tab.name,
              attributes: {'for': '$name-${tab.id}'},
              [.text(tab.label)],
            ),
        ],
      ),
      div(classes: _panels.name, [
        for (final tab in tabs) div(classes: _panel.name, tab.children),
      ]),
    ]);
  }
}
