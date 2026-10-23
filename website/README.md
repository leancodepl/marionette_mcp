# marionette.leancode.co

The Marionette landing page and docs, a static [Jaspr](https://jaspr.site)
site built on the [ciach](https://github.com/leancodepl/ciach/tree/main/website)
site's components and LeanCode palette.

```bash
dart pub global activate jaspr_cli 0.23.4
dart pub get
jaspr serve
```

`bash tool/build.sh` builds it into `build/jaspr`. The build reads the version
from `packages/marionette_mcp/pubspec.yaml`, so run it from the repository.

## Deployment

Netlify builds and serves the site through its GitHub App, as the project
`marionette-landing` with `website` as its base directory. `netlify.toml` points
it at `tool/netlify_build.sh`, which installs a pinned Dart SDK and the Jaspr
CLI, since Netlify's build image has no Dart, and then runs `tool/build.sh`.
Every pull request gets a Deploy Preview at
`https://deploy-preview-<number>--marionette-landing.netlify.app`, and a push
to `main` deploys to production. `tool/netlify_ignore.sh` skips builds that
change nothing in `website/` or the package version.

`.github/workflows/website_checks.yml` runs the analyzer, the formatter and
`dart test` on pull requests. `web/_headers` sets the response headers Netlify
sends.

Production pages load LeanCode's CookieScript consent banner and Google Tag
Manager container (`lib/tracking.dart`), first in `<head>`. Deploy Previews,
`jaspr serve` without `--release` and builds with any other `SITE_URL` load
neither, so they never count as visits.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/pages/home_page.dart` | The landing page, assembled from `lib/components/`. |
| `lib/pages/docs/` | The five docs pages. They are the documentation: `docs/*.md` in the repository only link here. |
| `lib/components/the_loop.dart`, `loop_player.dart` | The landing page's replay of one recorded run, and the island that plays it. |
| `lib/components/xray.dart` | The Concepts page's screenshot next to its element listing. CSS only. |
| `demo/loop.json`, `demo/xray.json` | The recorded data both of them show. |
| `web/images/loop/`, `web/images/xray/` | Their screenshots. |
| `web/images/brand/` | The Marionette logo and sygnet, from the Branding page, with coordinates rounded. |
| `tool/record_demo.sh` | Records the demo data again from the example app on an Android emulator. |

## The demo data

Every line, screen and `steps.md` entry in the replay comes from a real session
on `example/`. Re-record after a release that changes a tool's output:

```bash
bash tool/record_demo.sh
```

The script's header lists what it automates and what stays by hand: the
scenario, the agent's observations and `report.md` are fixed to the recorded
run.

## Assets

`dart test` renders the favicons and the social card again and compares them
with the committed files; `UPDATE_GOLDENS=1 dart test` rewrites them after an
intended change. Colors live in `lib/palette.dart`.

Each component's class names are scoped to it with
[jaspr_class_scope](https://pub.dev/packages/jaspr_class_scope). The
`.scopes.dart` part files are generated and committed; `jaspr serve` and
`jaspr build` rewrite them.
