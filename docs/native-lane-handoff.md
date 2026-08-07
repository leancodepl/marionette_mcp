# Native lane — testing handoff

Handoff doc for validating Marionette against UI **outside** the Flutter widget tree. Full requirement catalog: [`native requirements.txt`](../native%20requirements.txt) (repo root).

## Example app — Testing tab

All native-lane test cases live in the **example app** under the bottom-nav **Testing** tab:

| Screen               | Route                                     | Requirement                  |
| -------------------- | ----------------------------------------- | ---------------------------- |
| Testing (hub)        | `/testing`                                | Entry point                  |
| WebView              | `/testing/webview`                        | §2 WebViews                  |
| Platform Views (hub) | `/testing/platform-views`                 | §1 Embedded platform views   |
| Native controls      | `/testing/platform-views/native-controls` | §1a Plain native UI controls |

**Prerequisites:** Flutter lane — `connect` + VM service URI. Native lane — `native_connect` with `platform: android` | `ios` (see [README — Native lane requirements](../README.md#native-lane-requirements-android)).

---

## §1a — Plain native UI controls

|                        | Android | iOS |
| ---------------------- | :-----: | :-: |
| Implemented & verified |    ✓    |  ✓  |

Embedded `AndroidView` / `UiKitView` hosting native widgets (Android: `TextView`, `EditText`, `Button`; iOS: `UILabel`, `UITextField`, `UIButton`). Implementation: `example/lib/widgets/native_controls_platform_view.dart` + platform factories in `example/android/…/NativeControlsViewFactory.kt` and `example/ios/Runner/NativeControlsViewFactory.swift`.

### Expected Marionette behavior

| Tool                              | Lane    | Result                                                                                                                              |
| --------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `get_interactive_elements`        | Flutter | Does **not** list inner native controls (`Native label`, `Tap me (native)`, native field). Only surrounding Flutter widgets appear. |
| `native_get_elements`             | Native  | **Does** list native components (by text / accessibility id: `native_label`, `native_input`, `native_button`).                      |
| `native_tap`, `native_enter_text` | Native  | Can interact with those elements.                                                                                                   |
| `tap`, `enter_text` (Flutter)     | Flutter | Cannot target inner native widgets (not in Flutter tree).                                                                           |

Native UI inside a platform view is **not part of the Flutter element tree**; it is only exposed through the native lane after `native_connect`.

### Flutter `take_screenshots` vs platform views (Android ≠ iOS)

Marionette `take_screenshots` rasterizes Flutter’s **Skia layer tree** (`RenderView` → `toImage`). Platform views are embedded differently per OS:

| | Android | iOS |
|---|---------|-----|
| Embedding | Often **Virtual Display** — native view is copied into a Flutter **texture** in the layer tree | **Hybrid composition only** — `UIView` is a real UIKit subview alongside Flutter |
| `take_screenshots` shows platform view? | **Usually yes** (texture is in the tree) | **No** — UIKit subviews are not in Skia; area appears empty / wrong in the PNG |
| Use instead | — | `native_take_screenshot` (OS-level capture) |

So on **iOS**, rely on **`native_get_elements`** + **`native_take_screenshot`** for platform-view content; Flutter screenshot + vision is misleading for that region. On **Android**, Flutter screenshot may still be enough for a quick visual check, but automation remains **native lane only**.

### How to verify

1. `flutter run` on emulator/simulator; `connect` to VM service URI.
2. Open **Testing → Platform Views → Native controls**.
3. `native_connect` (`platform: android` or `ios`).
4. `native_get_elements` — confirm native label, input, and button appear.
5. `native_tap` on the native button; `native_enter_text` on the native field.
6. Compare with `get_interactive_elements` — native inner widgets absent.

---

<!-- Remaining sections (§1b–§11) to be added as example app coverage lands. -->
