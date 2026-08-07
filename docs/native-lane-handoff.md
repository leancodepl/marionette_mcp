# Native lane — testing handoff

Handoff doc for validating Marionette against UI **outside** the Flutter widget tree. Full requirement catalog: `[native requirements.txt](../native%20requirements.txt)` (repo root).

## Example app — Testing tab

All native-lane test cases live in the **example app** under the bottom-nav **Testing** tab:


| Screen               | Route                                     | Requirement                  |
| -------------------- | ----------------------------------------- | ---------------------------- |
| Testing (hub)        | `/testing`                                | Entry point                  |
| WebView              | `/testing/webview`                        | §2 WebViews                  |
| Platform Views (hub) | `/testing/platform-views`                 | §1 Embedded platform views   |
| Native controls      | `/testing/platform-views/native-controls` | §1a Plain native UI controls |
| Camera preview       | `/testing/platform-views/camera`          | §1b GPU-backed platform view |
| Google Maps          | `/testing/platform-views/google-maps`     | §1b GPU-backed platform view |
| Video player         | `/testing/platform-views/video-player`    | §1b GPU-backed platform view |
| Permission dialogs   | `/testing/permission-dialogs`             | §3 Permission dialogs        |
| Pickers & sheets     | `/testing/pickers-and-sheets`             | §4 Pickers and sheets        |


**Prerequisites:** Flutter lane — `connect` + VM service URI. Native lane — `native_connect` with `platform: android` | `ios` (see [README — Native lane requirements](../README.md#native-lane-requirements-android)).

---



## §1a — Plain native UI controls


|                        | Android | iOS |
| ---------------------- | ------- | --- |
| Implemented & verified | ✓       | ✓   |


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


|                                         | Android                                                                                        | iOS                                                                              |
| --------------------------------------- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Embedding                               | Often **Virtual Display** — native view is copied into a Flutter **texture** in the layer tree | **Hybrid composition only** — `UIView` is a real UIKit subview alongside Flutter |
| `take_screenshots` shows platform view? | **Usually yes** (texture is in the tree)                                                       | **No** — UIKit subviews are not in Skia; area appears empty / wrong in the PNG   |
| Use instead                             | —                                                                                              | `native_take_screenshot` (OS-level capture)                                      |


So on **iOS**, rely on `native_get_elements` + `native_take_screenshot` for platform-view content; Flutter screenshot + vision is misleading for that region. On **Android**, Flutter screenshot may still be enough for a quick visual check, but automation remains **native lane only**.

### How to verify

1. `flutter run` on emulator/simulator; `connect` to VM service URI.
2. Open **Testing → Platform Views → Native controls**.
3. `native_connect` (`platform: android` or `ios`).
4. `native_get_elements` — confirm native label, input, and button appear.
5. `native_tap` on the native button; `native_enter_text` on the native field.
6. Compare with `get_interactive_elements` — native inner widgets absent.

---



## §1b — GPU-backed platform views

Platform-view **interactive elements** only (page chrome omitted — always **Both**).

| Symbol | Meaning |
| ------ | ------- |
| **Both** | `get_interactive_elements` and `native_get_elements` |
| **Flutter** | `get_interactive_elements` only |
| **Native** | `native_get_elements` only |
| **—** | Neither tool |

### Camera preview

| Platform-view element | Android | iOS |
| --------------------- | :-------: | :-: |
| Preview surface | **—** | *not tested* |

**Android:** feed renders visually but neither lane lists the preview.

**iOS:** not tested on device — Simulator has no camera. On Simulator only, init fails with *"No cameras found on this device"* and both lanes expose that error text (**Both**); this is not representative of real-device behavior.

### Google Maps

| Platform-view element | Android | iOS |
| --------------------- | :-------: | :-: |
| Map pan area | **Native** (TextureView) | **Native** (`platform_view[1]`) |
| Zoom in / Zoom out | **Native** | **—** |
| Google logo button | **—** | **Native** |

Flutter lane misses the map on **both** platforms.

### Video player

One visible Dart overlay; native player mirrors playback state in the accessibility tree. Same on Android & iOS — **different nodes, same controls**:

| Control | Flutter lane | Native lane |
| ------- | :----------: | :-----------: |
| Seek / progress | ✓ | ✓ |
| Play / pause | ✓ | ✓ |
| Time | ✓ | ✓ |

iOS: Maps registers a `platform_view[…]` node; video_player does not (texture/hybrid composition vs true platform view).

---

## §3 — Permission dialogs

|                        | Android | iOS |
| ---------------------- | :-----: | :-: |
| Implemented & verified | ✓       | ✓   |

Screen: **Testing → Permission dialogs** (`/testing/permission-dialogs`). Triggers system prompts via `permission_handler` (notifications switch, camera/photos request buttons).

| Tool | Lane | Result |
| ---- | ---- | ------ |
| `native_get_elements` | Native | **Allow / Don’t allow** (or equivalent) on the OS dialog — works on **both** platforms |
| `native_tap` | Native | Can accept or deny the dialog |
| `get_interactive_elements` | Flutter | App UI only — **does not** list the system dialog |
| `take_screenshots` | Flutter | **Does not** show the dialog (drawn above Flutter by the OS) |
| `native_take_screenshot` | Native | **Does** show the dialog |

Reset between runs: `adb shell pm reset-permissions` (Android) or `xcrun simctl privacy booted reset all <bundle id>` (iOS).

---

## §4 — Pickers and sheets

|                        | Android | iOS |
| ---------------------- | :-----: | :-: |
| Implemented            | ✓       | ✓   |
| Tested                 | ✓ (smoke) | *not tested* |

Screen: **Testing → Pickers & sheets** (`/testing/pickers-and-sheets`). Each button opens an OS-owned UI outside the Flutter tree:

| Case | Plugin | Native UI (Android / iOS) |
| ---- | ------ | ------------------------- |
| **Files** | `file_picker` | SAF DocumentsUI / `UIDocumentPickerViewController` |
| **Photos** | `image_picker` (gallery) | Android photo picker / `PHPickerViewController` |
| **Camera capture** | `image_picker` (camera) | Camera intent / `UIImagePickerController` |
| **Share** | `share_plus` | Intent chooser / `UIActivityViewController` |

Same pattern as §3 permission dialogs:

| Tool | Lane | Result |
| ---- | ---- | ------ |
| `native_get_elements` | Native | Lists controls inside the open picker/sheet (e.g. Cancel, file rows, share targets) |
| `native_tap` | Native | Can interact with picker/sheet UI |
| `get_interactive_elements` | Flutter | App buttons only — **does not** list the open picker/sheet |
| `take_screenshots` | Flutter | **Does not** show the picker/sheet |
| `native_take_screenshot` | Native | **Does** show the picker/sheet |

**Testing note:** Smoke-tested on **Android only** — all four cases open the expected native UI and respond to `native_get_elements` / `native_tap`. Not tested deeply (edge cases, every control, dismiss paths). **iOS not tested yet.**

---

