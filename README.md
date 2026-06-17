<a href="https://leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp" align="center">
  <img alt="marionette_mcp" src="https://github.com/user-attachments/assets/12726942-57b3-4967-a1c8-bea06b397500" />
</a>

# Marionette MCP

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![marionette_mcp pub.dev badge](https://img.shields.io/pub/v/marionette_mcp)](https://pub.dev/packages/marionette_mcp)

**"Playwright MCP/Cursor Browser, but for Flutter apps"**

Marionette MCP enables AI agents (Claude Code, Copilot, Cursor, Gemini CLI, and more) to inspect and interact with running Flutter applications. It connects your AI agent directly to a running app via the Model Context Protocol (MCP), so it can see the widget tree, tap elements, enter text, scroll, and capture screenshots for automated AI-driven smoke testing and interaction.

Marionette MCP keeps the surface area intentionally small. It exposes only a handful of high-signal actions and returns the minimum actionable data, which helps keep prompts focused and context sizes under control.

![](https://github.com/leancodepl/marionette_mcp_attachments/blob/master/promo.gif)

## Marionette MCP vs Flutter MCP

The official [Dart & Flutter MCP server](https://docs.flutter.dev/ai/mcp-server) focuses on **development-time** tasks: searching pub.dev, managing dependencies, analyzing code, and inspecting runtime errors. It can also drive the UI, but it does so through Flutter Driver, which introduces extra instrumentation in your app. Marionette MCP focuses solely (and in an opinionated way) on **runtime interaction**: tapping buttons, entering text, scrolling, and taking screenshots, while requiring minimal changes to your app. Use Flutter MCP to build your app, use Marionette MCP to test and interact with it with minimal code changes.

## Quick Start

> [!NOTE]
> Your Flutter app must be prepared to be compatible with Marionette. The steps below are the short version — the [Getting Started guide](https://github.com/leancodepl/marionette_mcp/blob/main/docs/getting-started.md) walks through each one.

1. **Prepare your app** — add `marionette_flutter` and initialize `MarionetteBinding` in `main.dart`:

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

2. **Install the bridge** — activate the MCP server (for the CLI alternative, see the [CLI guide](https://github.com/leancodepl/marionette_mcp/blob/main/docs/cli.md)):

   ```bash
   dart pub global activate marionette_mcp
   ```

3. **Configure your AI tool** — e.g. for Claude Code:

   ```bash
   claude mcp add --transport stdio marionette -- marionette_mcp
   ```

   Other tools (Cursor, Gemini CLI, Copilot, Antigravity): see [Configuring your AI tool](https://github.com/leancodepl/marionette_mcp/blob/main/docs/mcp-tools.md#configuring-your-ai-tool).

4. **Run your app in debug mode** — `flutter run`, then copy the VM service URI from the console (e.g. `ws://127.0.0.1:9101/ws`).

5. **Connect and interact** — ask your agent to connect using that URI and start driving the app.

> [!IMPORTANT]
> Standard Material widgets work out of the box. **If your app uses a custom design system, configuration is required** — otherwise the agent can't see or tap your custom buttons and fields. Start with the [Production Setup Checklist](https://github.com/leancodepl/marionette_mcp/blob/main/docs/configuration.md#production-setup-checklist).

## What you can do

Once connected, an agent can drive your app with a small, focused toolset: inspect the widget tree (`get_interactive_elements`), `tap` / `secondary_tap` / `double_tap` / `long_press` / `swipe` / `pinch_zoom` / `scroll_to`, `enter_text`, `press_back_button`, `take_screenshots`, read `get_logs`, and `hot_reload`. Full list: [MCP Tools](https://github.com/leancodepl/marionette_mcp/blob/main/docs/mcp-tools.md).

Your app can also expose its own actions to the agent via [Custom Extensions](https://github.com/leancodepl/marionette_mcp/blob/main/docs/custom-extensions.md) — navigate by route name, seed test data, toggle feature flags, and more.

Some real-world prompts:

> "I implemented the Forgot Password screen — connect, navigate to login, tap 'Forgot Password', enter a valid email, submit, and check the logs that the API call fired."

> "I refactored the routing. Run a smoke test: cycle through all bottom-nav tabs and verify each screen loads without exceptions in the logs."

> "Investigate the unresponsive 'Clear Cache' button on Settings — find it via `get_interactive_elements`, tap it, and analyze the logs."

## Documentation

| Guide | What's inside |
| --- | --- |
| [Getting Started](https://github.com/leancodepl/marionette_mcp/blob/main/docs/getting-started.md) | Zero-to-driving in 5 steps. |
| [Flutter Setup](https://github.com/leancodepl/marionette_mcp/blob/main/docs/flutter-setup.md) | The binding, debug-only init, the single-binding rule. |
| [Configuration](https://github.com/leancodepl/marionette_mcp/blob/main/docs/configuration.md) | **Custom design systems, production checklist, complete `main.dart`.** |
| [Log Collection](https://github.com/leancodepl/marionette_mcp/blob/main/docs/logging.md) | Wire up `get_logs` (`logging`, `logger`, or custom). |
| [Semantics](https://github.com/leancodepl/marionette_mcp/blob/main/docs/semantics.md) | Make custom-painted / rich content readable to agents. |
| [MCP Tools](https://github.com/leancodepl/marionette_mcp/blob/main/docs/mcp-tools.md) | Full tool reference + AI-tool configuration. |
| [Custom Extensions](https://github.com/leancodepl/marionette_mcp/blob/main/docs/custom-extensions.md) | Expose app-specific actions as agent tools via `registerMarionetteExtension`. |
| [CLI](https://github.com/leancodepl/marionette_mcp/blob/main/docs/cli.md) | Drive Marionette from any shell-capable agent. |
| [Troubleshooting](https://github.com/leancodepl/marionette_mcp/blob/main/docs/troubleshooting.md) | Common gotchas and limitations. |

## Packages

| Package | Role |
| --- | --- |
| [`marionette_flutter`](https://pub.dev/packages/marionette_flutter) | The binding you add to your Flutter app. **Required.** |
| [`marionette_mcp`](https://pub.dev/packages/marionette_mcp) | MCP server bridging AI agents to your running app. |
| [`marionette_cli`](https://pub.dev/packages/marionette_cli) | CLI alternative for shell-only / restricted environments. |
| [`marionette_logging`](https://pub.dev/packages/marionette_logging) | `LogCollector` adapter for the `logging` package. |
| [`marionette_logger`](https://pub.dev/packages/marionette_logger) | `LogCollector` adapter for the `logger` package. |

---

## 🛠️ Maintained by LeanCode

<div align="center">
  <a href="https://leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp">
    <img src="https://leancodepublic.blob.core.windows.net/public/wide.png" alt="LeanCode Logo" height="100" />
  </a>
</div>

This package is built with 💙 by **[LeanCode](https://leancode.co?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp)**.
We are **top-tier experts** focused on Flutter Enterprise solutions.

### Why LeanCode?

- **Creators of [Patrol](https://patrol.leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp)** – the next-gen testing framework for Flutter.

- **Production-Ready** – We use this package in apps with millions of users.
- **Full-Cycle Product Development** – We take your product from scratch to long-term maintenance.

<div align="center">
  <br />

**Need help with your Flutter project?**

[**👉 Hire our team**](https://leancode.co/get-estimate?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp)
&nbsp;&nbsp;•&nbsp;&nbsp;
[Check our other packages](https://pub.dev/packages?q=publisher%3Aleancode.co&sort=downloads)

</div>
