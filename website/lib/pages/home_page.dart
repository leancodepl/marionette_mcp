import 'package:jaspr/jaspr.dart';
import 'package:marionette_website/components/hero.dart';
import 'package:marionette_website/components/landing_sections.dart';
import 'package:marionette_website/components/shell.dart';
import 'package:marionette_website/components/the_loop.dart';
import 'package:marionette_website/demo.dart';
import 'package:marionette_website/seo.dart';
import 'package:marionette_website/site.dart';

/// The landing page: what Marionette is, one real run, and where to go next.
class HomePage extends StatelessComponent {
  const HomePage({required this.version, required this.loop, super.key});

  final String version;
  final LoopDemo loop;

  @override
  Component build(BuildContext context) {
    return PageShell(
      page: .home,
      version: version,
      children: [
        pageHead(
          title: '$siteName — $tagline',
          description: description,
          path: '',
        ),
        Hero(version: version, loop: loop),
        TheLoop(loop: loop),
        const Pillars(),
        const WhatYouGetBack(),
        const QuickStart(),
        const DesignSystem(),
        const MoreThanTests(),
        const WhereItFits(),
      ],
    );
  }
}
