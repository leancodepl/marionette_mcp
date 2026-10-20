import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/card.dart';
import 'package:marionette_website/components/icons.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/styles.dart';

part 'feature_grid.scopes.dart';

/// One card of a [FeatureGrid]. [body] may quote identifiers in backticks;
/// [tools] are listed under it as chips, [href] links the card on.
class Feature {
  const Feature(
    this.icon,
    this.title,
    this.body, {
    this.tools = const [],
    this.href,
    this.linkLabel,
  });

  final Icon icon;
  final String title;
  final String body;
  final List<String> tools;
  final String? href;
  final String? linkLabel;
}

/// A responsive grid of icon cards.
@scopedCss
class FeatureGrid extends StatelessComponent {
  const FeatureGrid(this.features, {this.minWidth = 260, super.key});

  final List<Feature> features;

  /// The narrowest a card gets before the grid drops a column, in pixels.
  final int minWidth;

  static const _class = _$FeatureGridScope;

  static final _grid = _class('grid');
  static final _feature = _class('feature');
  static final _icon = _class('icon');
  static final _tools = _class('tools');
  static final _link = _class('link');

  @css
  static List<StyleRule> get styles => [
    css(_grid.selector, [
      css('&').styles(display: .grid, gap: .all(1.rem)),
      shrinkableChildren(),
    ]),
    css(_feature.selector, [
      css('&')
          .styles(display: .flex, flexDirection: .column, gap: .all(0.6.rem)),
      css('&:hover').styles(raw: {'border-color': 'var(--border-2)'}),
      css('& h3').styles(margin: .zero),
      css('& p:first-of-type').styles(raw: {'flex': '1'}),
    ]),
    css(_icon.selector).styles(
      display: .inlineGrid,
      width: 42.px,
      height: 42.px,
      margin: .only(bottom: 0.4.rem),
      border: hairline(accentAlpha(0.3)),
      radius: .circular(12.px),
      color: accentColor,
      backgroundColor: accentSoftColor,
      raw: {'place-items': 'center'},
    ),
    css(_tools.selector, [
      css('&').styles(
        display: .flex,
        margin: .only(top: 0.4.rem),
        flexWrap: .wrap,
        alignItems: .start,
        gap: .all(0.35.rem),
      ),
      css('& code').styles(fontSize: 0.74.rem, whiteSpace: .noWrap),
    ]),
    css(_link.selector).styles(
      margin: .only(top: 0.3.rem),
      color: accentColor,
      fontSize: 0.92.rem,
      fontWeight: .w500,
    ),
  ];

  @override
  Component build(BuildContext context) {
    return ul(
      classes: _grid.name,
      styles: .new(
        raw: {
          'grid-template-columns':
              'repeat(auto-fit, minmax(min(100%, ${minWidth}px), 1fr))',
        },
      ),
      [
        for (final feature in features)
          Card(classes: _feature, listItem: true, [
            span(classes: _icon.name, [feature.icon.build(size: 22)]),
            h3([.text(feature.title)]),
            p(rich(feature.body)),
            if (feature.tools.isNotEmpty)
              p(classes: _tools.name, [
                for (final tool in feature.tools) code([.text(tool)]),
              ]),
            if (feature.href case final href?)
              a(href: href, classes: _link.name, [
                .text(feature.linkLabel ?? 'Read more →'),
              ]),
          ]),
      ],
    );
  }
}
