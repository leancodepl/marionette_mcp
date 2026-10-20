// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:marionette_website/components/button.dart' as _button;
import 'package:marionette_website/components/card.dart' as _card;
import 'package:marionette_website/components/code_block.dart' as _code_block;
import 'package:marionette_website/components/copy_button.dart' as _copy_button;
import 'package:marionette_website/components/docs_layout.dart' as _docs_layout;
import 'package:marionette_website/components/docs_toc.dart' as _docs_toc;
import 'package:marionette_website/components/docs_widgets.dart'
    as _docs_widgets;
import 'package:marionette_website/components/faq.dart' as _faq;
import 'package:marionette_website/components/feature_grid.dart'
    as _feature_grid;
import 'package:marionette_website/components/footer.dart' as _footer;
import 'package:marionette_website/components/hero.dart' as _hero;
import 'package:marionette_website/components/icons.dart' as _icons;
import 'package:marionette_website/components/landing_sections.dart'
    as _landing_sections;
import 'package:marionette_website/components/loop_player.dart' as _loop_player;
import 'package:marionette_website/components/nav_bar.dart' as _nav_bar;
import 'package:marionette_website/components/pill.dart' as _pill;
import 'package:marionette_website/components/section.dart' as _section;
import 'package:marionette_website/components/shell.dart' as _shell;
import 'package:marionette_website/components/tabs.dart' as _tabs;
import 'package:marionette_website/components/the_loop.dart' as _the_loop;
import 'package:marionette_website/components/xray.dart' as _xray;
import 'package:marionette_website/styles.dart' as _styles;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _copy_button.CopyButton: ClientTarget<_copy_button.CopyButton>(
      'copy_button',
      params: __copy_buttonCopyButton,
    ),
    _docs_toc.DocsToc: ClientTarget<_docs_toc.DocsToc>(
      'docs_toc',
      params: __docs_tocDocsToc,
    ),
    _loop_player.LoopPlayer: ClientTarget<_loop_player.LoopPlayer>(
      'loop_player',
      params: __loop_playerLoopPlayer,
    ),
  },
  styles: () => [
    ..._styles.styles,
    ..._button.Button.styles,
    ..._card.Card.styles,
    ..._code_block.CodeBlock.styles,
    ..._copy_button.CopyButton.styles,
    ..._docs_layout.Callout.styles,
    ..._docs_layout.DocTable.styles,
    ..._docs_layout.DocsLayout.styles,
    ..._docs_widgets.Flow.styles,
    ..._docs_widgets.PromptCards.styles,
    ..._faq.Faq.styles,
    ..._feature_grid.FeatureGrid.styles,
    ..._footer.SiteFooter.styles,
    ..._hero.Hero.styles,
    ..._icons.Logo.styles,
    ..._landing_sections.BridgeOptions.styles,
    ..._landing_sections.DesignSystem.styles,
    ..._landing_sections.QuickStart.styles,
    ..._landing_sections.WhatYouGetBack.styles,
    ..._landing_sections.WhereItFits.styles,
    ..._loop_player.LoopPlayer.styles,
    ..._nav_bar.NavBar.styles,
    ..._pill.Pill.styles,
    ..._section.DocSection.styles,
    ..._section.Prose.styles,
    ..._section.Section.styles,
    ..._shell.PageShell.styles,
    ..._tabs.Tabs.styles,
    ..._the_loop.TheLoop.styles,
    ..._xray.XRay.styles,
  ],
);

Map<String, Object?> __copy_buttonCopyButton(_copy_button.CopyButton c) => {
  'text': c.text,
  'label': c.label,
};
Map<String, Object?> __docs_tocDocsToc(_docs_toc.DocsToc c) => {
  'path': c.path,
  'ids': c.ids,
  'labels': c.labels,
};
Map<String, Object?> __loop_playerLoopPlayer(_loop_player.LoopPlayer c) => {
  'targetId': c.targetId,
  'beats': c.beats,
};
