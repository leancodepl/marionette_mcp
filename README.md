<a href="https://marionette.leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp" align="center">
  <img alt="marionette_mcp" src="https://github.com/user-attachments/assets/12726942-57b3-4967-a1c8-bea06b397500" />
</a>

# Marionette MCP

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![marionette_mcp pub.dev badge](https://img.shields.io/pub/v/marionette_mcp)](https://pub.dev/packages/marionette_mcp)

**Your agent's hands and eyes on a running Flutter app.**

Marionette connects Claude Code, Cursor, Codex, Gemini CLI, Copilot or any MCP client to the Flutter app you run in debug mode. The agent sees the screen, taps, types, scrolls, reads the logs, hot reloads, and writes a report of what it did. If you know Playwright MCP: this is that, for Flutter.

**[Website](https://marionette.leancode.co)** · **[Docs](https://marionette.leancode.co/docs/)** · [Video](https://youtu.be/JYsFDbKTJ54) · [Article](https://leancode.co/blog/marionette-mcp-in-flutter-apps?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-readme)

## Quick start

1. Add the package to your app and initialize the binding in debug builds:

   ```bash
   flutter pub add marionette_flutter
   ```

   ```dart
   void main() {
     if (kDebugMode) {
       MarionetteBinding.ensureInitialized();
     } else {
       WidgetsFlutterBinding.ensureInitialized();
     }
     runApp(const MyApp());
   }
   ```

2. Give your agent a bridge: the MCP server or the `marionette` CLI, whichever you prefer ([every agent](https://marionette.leancode.co/docs/#bridge)):

   ```bash
   # MCP server, registered with Claude Code
   dart pub global activate marionette_mcp
   claude mcp add --transport stdio marionette -- marionette_mcp

   # or the CLI
   dart pub global activate marionette_cli
   ```

3. Run the app with `flutter run` and paste the `ws://…/ws` VM service URI it prints into the prompt, or ask the agent to run the app itself:

   > Connect to ws://127.0.0.1:9101/…/ws. On Profile, a malformed email must show an error and keep Submit disabled, and a valid one must submit.

> [!IMPORTANT]
> Flutter's own widgets work as is. **A custom design system needs one configuration step**, or the agent cannot see your buttons and fields: see [Configure](https://marionette.leancode.co/docs/configure/).

## What the agent can do

| | Tools |
| --- | --- |
| **See** | `get_interactive_elements`, `take_screenshots` |
| **Act** | `tap`, `enter_text`, `scroll_to`, `swipe`, `long_press`, `double_tap`, `pinch_zoom`, `press_key`, `press_back_button` |
| **Verify** | `get_logs`, `set_device_config` (text scale, bold text, dark mode) |
| **Iterate** | `hot_reload`, `hot_restart` |
| **Extend** | your app's own actions, registered with `registerMarionetteExtension` |

With `MarionetteConfiguration(enableSessionReports: true)`, every run leaves a folder: a `steps.md` the server writes, one line per tool call, and a `report.md` the agent writes from it. See [Reports](https://marionette.leancode.co/docs/reports/).

The `marionette` CLI drives the app with the same actions as shell commands: see [Drive](https://marionette.leancode.co/docs/drive/#cli).

## Agent Skill

`marionette_flutter` ships an [Agent Skill](https://github.com/leancodepl/marionette_mcp/blob/main/packages/marionette_flutter/skills/marionette-flutter-drive-app/SKILL.md) that teaches an agent to set up an app for Marionette, drive it and write the report:

```bash
dart run skills@ get                     # in an app that depends on marionette_flutter
npx skills add leancodepl/marionette_mcp # without the Dart toolchain
```

## Documentation

Contributors: see [Server and runtime architecture](https://github.com/leancodepl/marionette_mcp/blob/main/docs/architecture.md) for
package boundaries, tool registration, resource ownership, and verification.

| Page | What is inside |
| --- | --- |
| [Start](https://marionette.leancode.co/docs/) | Setup, every agent's config, the first prompt, the example app, FAQ |
| [Concepts](https://marionette.leancode.co/docs/concepts/) | How the agent sees a screen, selectors, compaction, the single-binding rule |
| [Configure](https://marionette.leancode.co/docs/configure/) | Custom design systems, Semantics, logs, device config, custom extensions |
| [Drive](https://marionette.leancode.co/docs/drive/) | Prompts for common jobs, every tool with its CLI command, the CLI |
| [Reports](https://marionette.leancode.co/docs/reports/) | Session folders, `steps.md`, `report.md`, the verdict |

## Packages

| Package | Role |
| --- | --- |
| [`marionette_flutter`](https://pub.dev/packages/marionette_flutter) | The binding in your app. **Required.** |
| [`marionette_mcp`](https://pub.dev/packages/marionette_mcp) | The MCP server your agent runs. |
| [`marionette_cli`](https://pub.dev/packages/marionette_cli) | The `marionette` CLI, for shell-only agents. |
| [`marionette_logging`](https://pub.dev/packages/marionette_logging) | Log collection from the `logging` package. |
| [`marionette_logger`](https://pub.dev/packages/marionette_logger) | Log collection from the `logger` package. |

---

## 🛠️ Maintained by LeanCode

<div align="center">
  <a href="https://leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp">
    <img src="https://leancodepublic.blob.core.windows.net/public/wide.png" alt="LeanCode Logo" height="100" />
  </a>
</div>

Marionette is built by **[LeanCode](https://leancode.co?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp)**, the creators of [Patrol](https://patrol.leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp), the testing framework for Flutter. We build Flutter products from scratch to long-term maintenance.

<div align="center">

[**👉 Hire our team**](https://leancode.co/get-estimate?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp)
&nbsp;&nbsp;•&nbsp;&nbsp;
[Check our other packages](https://pub.dev/packages?q=publisher%3Aleancode.co&sort=downloads)

</div>
