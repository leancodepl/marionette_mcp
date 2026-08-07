<a href="https://leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-mcp" align="center">
  <img alt="marionette_mcp" src="https://github.com/user-attachments/assets/12726942-57b3-4967-a1c8-bea06b397500" />
</a>

# Marionette MCP

![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![marionette_mcp pub.dev badge](https://img.shields.io/pub/v/marionette_mcp)](https://pub.dev/packages/marionette_mcp)

**"Playwright MCP/Cursor Browser, but for Flutter apps"**

Marionette MCP enables AI agents (Claude Code, Copilot, Cursor, Gemini CLI, and more) to inspect and interact with running Flutter applications. It connects your AI agent directly to a running app via the Model Context Protocol (MCP), so it can see the widget tree, tap elements, enter text, scroll, and capture screenshots for automated AI-driven smoke testing and interaction.

Marionette MCP keeps the surface area intentionally small. It exposes only a handful of high-signal actions and returns the minimum actionable data, which helps keep prompts focused and context sizes under control.

## Learn more about Marionette MCP:

- Video: [Clicking Through Your App with Marionette MCP](https://youtu.be/JYsFDbKTJ54)
- Article: [Marionette MCP - Your Flutter AI Agent That Interacts With Running Apps](https://leancode.co/blog/marionette-mcp-in-flutter-apps?utm_source=github.com&utm_medium=referral&utm_campaign=marionette-readme)

## Demo

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

For UI **outside** the Flutter widget tree (system permission dialogs, OS sheets, webviews, browser DOM on Flutter web), use the native lane: `native_connect` with `platform` `android` | `ios` | `web`, then `native_get_elements` / `native_tap` / etc. Prefer Flutter tools when the target is an in-app widget.

### Native lane requirements (Android)

`native_connect` with `platform: android` uses **UIAutomator2** over adb. Marionette does **not** install adb for you — it must already be on your `PATH` (Android SDK Platform Tools; usually present if you run Flutter on Android):

```bash
which adb          # should print a path
adb devices        # device/emulator must show state "device"
```

You also need a connected Android device or emulator. Optionally pass `serial` to `native_connect` when multiple devices are attached.

On first connect, Marionette **downloads and caches** the UIAutomator2 server APKs (Appium v10.3.2). To use local APKs instead:

```bash
export MARIONETTE_UIA2_SERVER_APK=/path/to/appium-uiautomator2-server.apk
export MARIONETTE_UIA2_TEST_APK=/path/to/appium-uiautomator2-server-debug-androidTest.apk
```

### Native lane requirements (iOS)

`native_connect` with `platform: ios` uses **WebDriverAgent (WDA)** on an **iOS Simulator** (real devices are not supported yet). Unlike Android, Marionette does **not** download or build WDA for you — you need a **one-time build**, then Marionette can launch and reuse it.

**Host & tools**

- **macOS only** — WDA bootstrap uses `xcrun simctl` and `xcodebuild` (from Xcode).
- A **booted iOS Simulator** (`open -a Simulator`, or `xcrun simctl boot "iPhone 16"`). Optionally pass `udid` to `native_connect` when several simulators are booted.

**One-time WebDriverAgent build**

```bash
git clone https://github.com/appium/WebDriverAgent.git
cd WebDriverAgent
xcodebuild build-for-testing \
  -project WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -destination 'platform=iOS Simulator,id=<UDID>'
```

Get `<UDID>` from `xcrun simctl list devices`. Build for the simulator runtime you plan to use — rebuild if you switch to an incompatible OS/arch.

**Point Marionette at the build** (pick one):

```bash
# Preferred: .xctestrun from DerivedData/Build/Products
export MARIONETTE_WDA_XCTESTRUN=/path/to/WebDriverAgentRunner_*.xctestrun

# Or the runner .app / Products directory
export MARIONETTE_WDA_BUNDLE=/path/to/WebDriverAgentRunner-Runner.app
export MARIONETTE_WDA_PATH=/path/to/DerivedData/Build/Products
```

Or copy the build output into `~/.cache/marionette_mcp/wda/` — Marionette scans that directory automatically (no env vars needed once artifacts are there). On connect it runs `xcodebuild test-without-building` against the `.xctestrun`, or falls back to `simctl install` + `simctl launch` for a `.app` bundle.

### Native lane requirements (Web)

`native_connect` with `platform: web` uses **ChromeDriver** to automate **browser DOM** — HTML around a Flutter web app and `<iframe>` content in the page. Marionette does **not** install ChromeDriver or Chrome for you; it attaches to the Chrome already started by `flutter run`.

**What this lane is for**

- Real DOM elements: `<button>`, `<input>`, `<a>`, semantic HTML, in-page iframes.
- UI that never appears in the Flutter widget tree (`get_interactive_elements`).
- **Attaching to the same Chrome window** already opened by `flutter run -d chrome` (default) so app state is preserved when switching from Flutter tools to native DOM tools.

**What it is not for**

- Flutter widgets rendered by **CanvasKit** (or other non-DOM Flutter painting) — use the **Flutter VM lane** (`connect`, `tap`, `enter_text`, …) for those.
- In practice you often use **both lanes**: Flutter tools for in-app widgets; `native_*` tools for DOM the Flutter tree does not expose.

**Host & tools**

- **macOS, Linux, or Windows** — Marionette spawns ChromeDriver locally via `dart:io` (no macOS-only constraint, unlike iOS WDA).
- **ChromeDriver** on `PATH`, or set `MARIONETTE_CHROMEDRIVER` to the binary path.
- **Google Chrome** installed (started by `flutter run -d chrome`).
- **ChromeDriver and Chrome major versions must match** — version skew is the most common connect failure. Check `chrome://version` in the browser against `chromedriver --version`.

```bash
which chromedriver       # should print a path
chromedriver --version   # should match your Chrome major version
```

**Optional environment variables**

```bash
export MARIONETTE_CHROMEDRIVER=/path/to/chromedriver
export MARIONETTE_CHROME_DEBUGGER_ADDRESS=127.0.0.1:9222 # skip auto-discovery
export MARIONETTE_SCREENSHOTS_DIR=$HOME/marionette-screenshots   # optional PNG saves
```

**Connecting (recommended: attach to flutter run)**

1. Start Chrome with a known DevTools port so Marionette can attach:

```bash
flutter run -d chrome \
  --web-browser-debug-port=9222 \
  --web-browser-flag=--remote-allow-origins=*
```

2. Call Flutter `connect` with the VM service URI when you need the widget tree.
3. When you need DOM outside the Flutter tree, call `native_connect` with `platform: web` — ChromeDriver attaches to the running Chrome via `goog:chromeOptions.debuggerAddress`.

`native_connect` arguments for web:

| Argument          | Purpose                                                                                                                                                                                              |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `debuggerAddress` | Chrome DevTools address (e.g. `127.0.0.1:9222`). When omitted, Marionette uses `MARIONETTE_CHROME_DEBUGGER_ADDRESS`, scans Chrome processes for `--remote-debugging-port`, then probes common ports. |
| `chromeDriverUrl` | Attach to an already-running ChromeDriver instead of Marionette spawning one                                                                                                                         |

On connect, Marionette starts ChromeDriver (unless `chromeDriverUrl` is set), then attaches to your existing Chrome session from `flutter run`.

### Native UI coverage

The native lane exposes a small generic toolkit — `native_get_elements`, `native_tap`, `native_scroll`, `native_enter_text`, `native_take_screenshot`, plus `foregroundApp` from `native_get_elements`. There is no category-specific logic (no WebView CDP, keyboard dismiss, biometrics triggers, or file-picker bypass). What works depends on whether the platform accessibility tree exposes the UI.

**Status legend:** **Yes** = reliably covered by today's native tools · **Partial** = some flows work (often tap/screenshot), with important gaps · **No** = not supported / out of scope · **—** = not applicable on that platform

| Case                                                                                                   | Android                                                                                         | iOS (Simulator)                                                              | Web                                                                                          |
| ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **1a. Plain platform views** — TextView / UILabel, native buttons and text fields in a PlatformView    | Partial                                                                                         | Partial                                                                      | Partial — DOM elements via ChromeDriver; not Flutter CanvasKit                               |
| **1b. GPU / Surface views** — maps, video, camera preview, `<canvas>`                                  | Partial — bounds, tap, full-screen screenshot; inner content not readable in tree               | Partial — same                                                               | Partial — `<video>` / `<canvas>` in DOM; CanvasKit Flutter layer not in tree                 |
| **1c. Third-party SDK views** — ads, Stripe card field, PDF viewers                                    | Partial — when SDK exposes accessibility nodes; PCI-sensitive fields may be hidden              | Partial — same                                                               | Partial — when exposed as DOM; PCI fields may be hidden                                      |
| **2. WebViews** — `webview_flutter`, in-app browser content                                            | Partial — WebView container + visual screenshot; **no inner DOM** (no CDP / `chrome://inspect`) | Partial — same (no Safari Web Inspector integration)                         | Partial — in-page DOM via ChromeDriver; not a separate attach/debug flow yet                 |
| **3. Permission dialogs** — runtime permission prompts, ATT                                            | Yes — tree read, tap Allow/Deny, `foregroundApp`                                                | Partial — tap works; `foregroundApp` is null when SpringBoard owns the alert | Partial — tap in-page permission UI in DOM; browser permission bubbles may need manual grant |
| **4. Pickers & sheets** — file/photo picker, share sheet, camera intent                                | Partial — tap visible list items; **no** SAF/intent or file-upload bypass                       | Partial — same; **no** PHPicker file injection                               | Partial — tap visible DOM; **no** `<input type="file">` CDP bypass yet                       |
| **5. Authentication UI** — account picker, autofill bars                                               | Partial — tap/type when controls appear in tree                                                 | Partial — same                                                               | Partial — tap/type DOM controls                                                              |
| **5. Biometrics** — fingerprint / Face ID sheets                                                       | No — no sensor simulation in native tools                                                       | No — no simulator Face ID trigger                                            | No                                                                                           |
| **6. Payment & purchase sheets** — Apple Pay, Google Pay, StoreKit, Play Billing                       | No — out of scope                                                                               | No — out of scope                                                            | No                                                                                           |
| **7. Browser handoff / OAuth** — Custom Tabs, SFSafariViewController, ASWebAuthenticationSession       | Partial — system consent alerts tappable; **no** in-browser OAuth automation                    | Partial — same                                                               | Partial — in-tab DOM only                                                                    |
| **8. Keyboard / IME** — occludes layout, needs dismiss                                                 | Partial — `native_enter_text` only; **no** dedicated dismiss (ESC/back/resign)                  | Partial — same                                                               | Partial — `native_enter_text` only                                                           |
| **9. Transient system UI** — toasts, notification shade, status bar                                    | Partial — tree read + screenshot when exposed; **no** expand-notifications helper               | Partial — same; **no** push/notification shortcuts                           | Partial — DOM toasts/banners when exposed                                                    |
| **10. Full native screens** — add-to-app, plugin-launched Activity / UIViewController (e.g. camera UI) | Yes — generic native hierarchy when native app is foreground                                    | Partial — simulator only; real device not supported yet                      | No                                                                                           |
| **11. Plugin native dialogs** — AlertDialog / UIAlertController raised by plugins                      | Yes — primary target for native lane; tap by label/text                                         | Yes — same                                                                   | No                                                                                           |

**Example app demos today:** permission prompts (`notifications_screen.dart`), embedded WebView visual capture (`webview_screen.dart`). Platform views, pickers, and biometrics are not demoed yet.

**Prefer the Flutter lane** when the target is an in-app widget (`get_interactive_elements`, `tap`, `enter_text`). Switch to native tools when the Flutter tree is empty or a system surface covers the app.

Your app can also expose its own actions to the agent via [Custom Extensions](https://github.com/leancodepl/marionette_mcp/blob/main/docs/custom-extensions.md) — navigate by route name, seed test data, toggle feature flags, and more.

## Screenshot storage

`take_screenshots` and `native_take_screenshot` return inline PNG images by default — **no files are written to disk** unless you opt in.

To also save PNG files locally, set `MARIONETTE_SCREENSHOTS_DIR` to an existing or creatable directory path. Files are named with a UTC timestamp and a `flutter` or `native` suffix (e.g. `2026-08-06T09-35-17.281020Z_flutter.png`).

```bash
export MARIONETTE_SCREENSHOTS_DIR="$HOME/marionette-screenshots"
```

When running the MCP server from an AI tool, set the variable in that tool's MCP config. For Cursor (`.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "marionette": {
      "command": "marionette_mcp",
      "args": [],
      "env": {
        "MARIONETTE_SCREENSHOTS_DIR": "/path/to/screenshots"
      }
    }
  }
}
```

Restart the MCP server after changing the variable so it picks up the new value.

Some real-world prompts:

> "I implemented the Forgot Password screen — connect, navigate to login, tap 'Forgot Password', enter a valid email, submit, and check the logs that the API call fired."

> "I refactored the routing. Run a smoke test: cycle through all bottom-nav tabs and verify each screen loads without exceptions in the logs."

> "Investigate the unresponsive 'Clear Cache' button on Settings — find it via `get_interactive_elements`, tap it, and analyze the logs."

## Documentation

| Guide                                                                                                 | What's inside                                                                 |
| ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| [Getting Started](https://github.com/leancodepl/marionette_mcp/blob/main/docs/getting-started.md)     | Zero-to-driving in 5 steps.                                                   |
| [Flutter Setup](https://github.com/leancodepl/marionette_mcp/blob/main/docs/flutter-setup.md)         | The binding, debug-only init, the single-binding rule.                        |
| [Configuration](https://github.com/leancodepl/marionette_mcp/blob/main/docs/configuration.md)         | **Custom design systems, production checklist, complete `main.dart`.**        |
| [Log Collection](https://github.com/leancodepl/marionette_mcp/blob/main/docs/logging.md)              | Wire up `get_logs` (`logging`, `logger`, or custom).                          |
| [Semantics](https://github.com/leancodepl/marionette_mcp/blob/main/docs/semantics.md)                 | Make custom-painted / rich content readable to agents.                        |
| [MCP Tools](https://github.com/leancodepl/marionette_mcp/blob/main/docs/mcp-tools.md)                 | Full tool reference + AI-tool configuration.                                  |
| [Custom Extensions](https://github.com/leancodepl/marionette_mcp/blob/main/docs/custom-extensions.md) | Expose app-specific actions as agent tools via `registerMarionetteExtension`. |
| [CLI](https://github.com/leancodepl/marionette_mcp/blob/main/docs/cli.md)                             | Drive Marionette from any shell-capable agent.                                |
| [Troubleshooting](https://github.com/leancodepl/marionette_mcp/blob/main/docs/troubleshooting.md)     | Common gotchas and limitations.                                               |

## Packages

| Package                                                             | Role                                                      |
| ------------------------------------------------------------------- | --------------------------------------------------------- |
| [`marionette_flutter`](https://pub.dev/packages/marionette_flutter) | The binding you add to your Flutter app. **Required.**    |
| [`marionette_mcp`](https://pub.dev/packages/marionette_mcp)         | MCP server bridging AI agents to your running app.        |
| [`marionette_cli`](https://pub.dev/packages/marionette_cli)         | CLI alternative for shell-only / restricted environments. |
| [`marionette_logging`](https://pub.dev/packages/marionette_logging) | `LogCollector` adapter for the `logging` package.         |
| [`marionette_logger`](https://pub.dev/packages/marionette_logger)   | `LogCollector` adapter for the `logger` package.          |

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
