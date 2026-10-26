---
name: marionette-flutter-to-patrol
description: Turn a verified Marionette session (.marionette/sessions/<name>/ with steps.md, report.md and screenshots) into Patrol E2E tests for a Flutter app - which steps to encode, the step-to-Patrol mapping, which widgets need keys, the assertions and seed control the report implies, keeping MarionetteBinding out of the test build, and native prompt timing. Use whenever someone asks to write Patrol tests from a Marionette run or session, to replay a run as a test, to make a Marionette-verified flow regression-proof or put it in CI, or to review a Patrol suite built from one. Builds on Patrol's own skills (patrol-write-test, patrol-test-architecture) and does not repeat them.
---

# marionette_flutter: Patrol tests from a session

A Marionette session is a verified script of one flow: `steps.md` (one line
per tool call, written by the server), `report.md` (the driver's summary of
what it tested, checked and found) and `screenshots/` (the evidence). This
skill covers only what that input changes about writing Patrol tests: what to
encode, which widgets need keys, how each step maps to Patrol, and which
assertions and data rules the report implies. Everything about Patrol itself
comes from Patrol's own skills.

## Load the Patrol skills first

- `patrol-write-test`: the order of work, the Patrol API, key rules, waits,
  end assertions, native dialogs, running tests.
- `patrol-test-architecture`: the `testApp` wrapper, Modules, System
  (`extends PlatformAutomator`), ApiClients, and the `keys.dart` conventions.

If they are not installed, take them, with `patrol-setup`, from one of these:

- Patrol's repository, with the npm `skills` CLI:
  `npx skills add leancodepl/patrol/skills -s '*' -a claude-code -y`.
- The `patrol` dependency, once a release ships a `skills/` folder (4.10.0
  and older do not):
  `dart run skills@ get -p patrol -s patrol-setup -s patrol-write-test -s patrol-test-architecture`.
- In Claude Code: `/plugin install flutter-patrol@leancode-ai-plugins`.

If the project has no `patrol_test/` yet, set Patrol up first with
`patrol-setup` or https://patrol.leancode.co/documentation. Where this skill
deviates from Patrol's rules it says so and why; declare each deviation in
the hand-over, so a reviewer sees a decision, not a mistake.

## The example app

The snippets use one invented app, `shop_app`. A customer signs in and gets
Products and Cart tabs in an `IndexedStack`. Products shows a loading card,
then tiles with an `N in stock` label and an Add button, and asks for the
notification permission the first time. Add opens a sheet with a quantity
field: a quantity above the stock shows `Only N in stock.` as `errorText`; a
valid one closes the sheet with one snackbar, `Added N to cart`. Cart reloads
when opened and lists its lines in insertion order. The backend serves the
same lists to the signed-in customer; an admin endpoint removes one customer's
cart line (seed control).

## Inputs

Get these from the caller, or work them out and declare them as assumed:

- The session directory `.marionette/sessions/<name>/`. No session yet: turn
  on session reports (`marionette-flutter-setup`), drive the flow with
  `marionette-flutter-drive-app`, then come back.
- The spec or acceptance criteria: the behaviour each test must assert, not
  only the taps. The report says what the driver saw, not what the app must do.
- A free device id: Patrol installs its own build of the app.
- Where the test accounts are documented. Never invent data that looks like a
  real person.
- How the local backend's seed is reset, and which seeded rows a test may
  consume.

## 1. Read the session

Read `steps.md` and `report.md` in full, then open the screenshots the report
cites. An MCP run leaves one session directory. A CLI run leaves one per
command, logged under the CLI's hyphenated name (`enter-text`): read them in
time order as one transcript.

Each `steps.md` line is `- [HH:MM:SS] tool selector -> outcome`:

- Action lines to encode: `tap`, `double_tap`, `long_press`, `secondary_tap`,
  `enter_text`, `swipe`, `scroll_to`, `pinch_zoom`, `press_back_button`,
  `press_key` and `set_device_config`. `connect`, `disconnect`, `hot_restart`,
  `hot_reload`, `get_interactive_elements`, `take_screenshots` and `get_logs`
  are the driver looking; they encode to nothing but show what was on screen.
  `call_custom_extension` and promoted extension lines (outcome `ok`) may have
  changed app state (seed, sign-in): find out from the report what they did
  and encode it as setup, or declare it.
- The selector is what the call matched: `key=`, `identifier=`, `text=`,
  `type=`, `x= y=`, `focused_element=true`, and `ancestor_keys=a>b` when the
  key repeats in identical subtrees. On a `press_key` line, `key=` is the
  keyboard key (`enter`, `tab`), not a widget key; it acts on the focused
  element.
- The outcome holds the rest: the swipe direction (`Swiped down on element
  matching: …`) or, for a coordinate swipe, `Swiped from (x1, y1) to (x2, y2)`
  with y growing downward; the pinch scale; or `error: …`. `set_device_config`
  logs only `Device config updated`: take the values from the report or the
  screenshots.
- Weak selectors show where keys are missing. `tap x= y=` means the widget had
  no key and no unique text. `tap text=` may hide a collision the driver
  resolved by position (the same word on a tab, a title and a tile); check the
  listing or the screenshot. `tap type=FilledButton` hit the first widget of
  that type; it stays correct only while that widget stays the first.
- `enter_text focused_element=true` follows the tap that focused a field.
  Typed values are redacted to `input_len=N`, or `input=[redacted]` when the
  key or identifier contains pass, pin, token, secret or cvv. Take them from
  the report, the spec or the seed.
- Two consecutive `swipe` lines on one list are one scroll. A downward swipe
  at the top of a list is pull-to-refresh.
- Traps the driver hit are requirements: an `error:` outcome and a retry, a
  `tap x= y=` after a failed `tap text=`, a `hot_restart` mid-flow. Find the
  cause (a transient snackbar, a consumed seed row, a seed dated in UTC, a
  missing key) and design the test around it.

`report.md` follows the report contract of `marionette-flutter-drive-app`. It
is written in the language of the prompt that started the run, so find its
parts by their icons and tags:

- The headline icon sums up the run: `✅` no findings, `⚠️` suspicions only,
  `🐛` at least one confirmed bug.
- `Tested:`, under the headline (the label may be translated), names the flows
  the run covered. `Checks:`, when present, names what the driver verified on
  top (validation, back navigation, dark mode, text scale). Neither line gives
  step numbers: map each flow and check to its lines in `steps.md` yourself.
- Numbered findings are `🐛 [bug]` or `⚠️ [suspicion]`, each with `Repro:` and
  `Evidence:` (a step, a log line or a screenshot). Report them; do not encode
  a bug, because a test written around a known bug passes for the wrong
  reason. Confirm a suspicion before you rely on it.
- A DB or API check the driver made (`psql`, a REST call) becomes a backend
  assertion.
- `➖ Not covered:` is out of scope; do not invent tests for it. A run stopped
  early says why and what it left untested; encode only what it reached.

Without a `report.md`, work from `steps.md`, the screenshots and the spec, and
declare that.

Then split the actions into tests: one user intention per test, each from a
fresh app launch and sign-in. Write down each test's step range; a reviewer
checks coverage against the transcript with it.

## 2. Keys the transcript asks for

A flow that Marionette drove by coordinates or text has no keys for Patrol.
Add them before any test code, as their own commit, following the `keys.dart`
conventions of `patrol-test-architecture`. The transcript says which widgets
need one:

| Evidence in the session | Key it |
| --- | --- |
| `tap x= y=` | The widget under the coordinates (from the listing or the screenshot) |
| `tap text=X` where X appears more than once | Every widget the test touches that shares the text |
| `tap text=X` on a tooltip or icon label | The icon button; tooltip text is not a stable finder |
| `tap type=…` | The widget; the type match holds only while it is the first of its type |
| `enter_text focused_element=true` | The field the preceding tap focused |
| `swipe`, `scroll_to` | The list: the `scrollTo(view:)` target and the pull-to-refresh anchor |
| A dialog, sheet or snackbar in the flow | Its fields, every button, the snackbar |
| An end state the report describes | Its container, plus the error and loading widgets that could replace it |
| Repeated tiles from data | A parameterized key from the row's id, never an index |

Three cases come up often. Declare each in the hand-over; the first changes a
widget signature, which `patrol-write-test` otherwise forbids:

- A private widget without a `key` parameter: key the root widget it returns,
  or add `super.key` when the key must sit on the list child itself.
- `const` is lost. `keys` is a `final` top-level variable, so
  `NavigationDestination(key: keys.bottomTabs.cartTab, …)` cannot be `const`,
  and a `const [...]` list of destinations loses `const` too. No behaviour
  changes.
- A transient widget (snackbar, dialog, sheet) gets its key where it is
  created: in the listener or the `showModalBottomSheet` builder, not in the
  screen's `build`.

If the app already has `ValueKey('snake_case')` literals that Marionette used,
keep the values: define the `keys.dart` members so their full values equal the
old strings (skip the page prefix of `patrol-test-architecture` if needed, and
declare that), and replace the literals with `keys.…` references.

## 3. Keep MarionetteBinding out of the test build

The app's `main()` calls `MarionetteBinding.ensureInitialized(...)` in debug
builds. `patrolTest` installs its own binding before the test body, and
`MarionetteBinding.ensureInitialized` then throws: one app has one
`WidgetsBinding`. So `openApp` must never call `main()`. Move the startup
(config validation, SDK init, the API client, the root widget) into a
`bootstrapApp()` that both call. This refactor deviates from the no-refactor
rule of `patrol-write-test`; declare it.

```dart
// lib/main.dart
Future<void> main() async {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(
      const MarionetteConfiguration(enableSessionReports: true),
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(await bootstrapApp());
}

// patrol_test/common/app_harness.dart, next to testApp
Future<void> openApp(PatrolIntegrationTester $) async {
  await $.pumpWidgetAndSettle(await bootstrapApp());
}
```

If the app may not change, copy the body of `main()` without the binding into
`openApp`, and declare that the two can drift.

Two more consequences of the Marionette run:

- Stop `flutter run` and the Marionette session before `patrol test`: both
  install and drive the same app on the same device.
- `.patrol.env` needs the dart-defines the Marionette run got from
  `--dart-define-from-file`; without them the app's config validation fails
  before the first screen. From an Android emulator, a local backend is at
  `10.0.2.2`, not `localhost`.

## 4. Translate the steps

| `steps.md` line | Patrol |
| --- | --- |
| `tap key=product_tile_<id>` | `$(keys.products.tile(id)).tap()` |
| `tap text=Confirm` (unique, stable copy) | A key; `$('Confirm').tap()` breaks when the copy changes |
| `tap text=…` that collided, `tap type=…`, `tap x= y=` | Add a key, then `$(keys.<page>.<widget>).tap()` |
| `tap identifier=…` | A key, or `$(find.bySemanticsIdentifier('…'))` |
| Any line with `ancestor_keys=a>b` | Chain the finders, outermost first: `$(keys.<scope>).$(keys.<widget>).tap()` |
| A tap, then `enter_text focused_element=true` | `$(keys.<page>.<field>).enterText(value)`, no separate tap |
| `swipe` on a list, `scroll_to key=` | `$(keys.<page>.<item>).scrollTo(view: $(keys.<page>.list))` |
| Downward `swipe` at the top of a list | `$.tester.fling($(keys.<page>.list), const Offset(0, 300), 1200)`, then `$.pumpAndTrySettle()` |
| `press_back_button` | On Android, `$.platform.android.pressBack()` (`$.platform.mobile` has no `pressBack`, as of 4.10); on iOS, tap the app's back control by key |
| `press_key` | `$.tester.sendKeyEvent(LogicalKeyboardKey.<key>)`; Enter on a text field is different (below) |
| `long_press` | `$(keys.<page>.<widget>).longPress()` |
| `double_tap` | `$.tester.tap(finder)`, `$.tester.pump(kDoubleTapMinTime)`, `$.tester.tap(finder)` |
| `secondary_tap` | `$.tester.tap(finder, buttons: kSecondaryButton)` |
| `pinch_zoom` | A two-pointer gesture (`$.tester.startGesture`), or declare it not encoded |
| `set_device_config` | Not a user action. Set `$.tester.platformDispatcher.textScaleFactorTestValue` or `platformBrightnessTestValue` with `addTearDown($.tester.platformDispatcher.clearAllTestValues)`, or declare it not encoded |
| `hot_restart`, `hot_reload`, listing, screenshot, log, `connect` lines | Nothing; each test starts the app fresh in `openApp($)` |
| A DB/API check in the report | A backend read as the test user, compared at the end |
| A native prompt in the report | A `System` method right after the screen that triggers it (section 7) |

A validation message (`errorText`) appears in Marionette's listing as a text
element without a key. In Patrol, find it inside the keyed field's subtree:
`$(keys.quantitySheet.quantityField).$('Only ${product.stock} in stock.')`.
These text and type finders are deliberate exceptions to the keys-only rule of
`patrol-write-test`: `errorText` and framework widgets carry no key, and the
list reader collects the keys of the tiles it finds.

`press_key` Enter on a focused text field submits it: Marionette calls the
field's `textInputAction` (`done` when unset). A key event alone does not, and
Patrol unregisters its test text input after `enterText`, so submit on the
field itself, with that action:

```dart
final quantityInput = $(keys.quantitySheet.quantityField).$(EditableText);
$.tester
    .state<EditableTextState>(quantityInput)
    .performAction(TextInputAction.done);
await $.pumpAndTrySettle();
```

Pull-to-refresh can be a silent no-op. A list whose content fits the viewport
has Android's `ClampingScrollPhysics`, which refuses the drag, so the
`RefreshIndicator` never fires and `pumpAndTrySettle` hides it. The Marionette
swipe on a short list may have proven nothing either. Assert
`$(RefreshProgressIndicator).waitUntilVisible()` right after the gesture, or
have the app give the list `AlwaysScrollableScrollPhysics`.

Encode every action line, or declare which ones you merged or dropped and why.
A step that looks like a detour (an invalid value before the valid one) is
often the spec's check that the error appears and clears; dropping it drops
that assertion.

## 5. Assertions from the report

Each flow under `Tested:` and each item on `Checks:` becomes an assertion
group at the end of its test, as `patrol-write-test` asks. These rules keep a
green test from proving nothing.

**Positive state next to every negative check.** `isListed(productId)` being
false also holds while the list reloads, or when an error card replaced it.
Wait for the loaded state and name what must be there:

```dart
await modules.cart.waitUntilLoaded();
expect(modules.cart.isErrorShown(), isFalse);
await modules.cart.waitForLine(remaining.first.productId);
expect(modules.cart.isListed(removedProductId), isFalse);
```

**A loaded-state wait, not a bare `pumpAndTrySettle()`.** It returns silently
while a spinner turns, and the checks after it then run against the loading
state. Wait for the first expected tile, or for the loading card to be gone.

**Three declared mid-test exceptions** to "assert at the end": transient UI (a
snackbar is gone by the end), a message the next action clears (a validation
error), and the refresh indicator after a pull-to-refresh gesture. Assert each
right after the action that shows it, and declare it in the hand-over. When
the spec says one snackbar, count it:
`expect(modules.quantitySheet.snackBarCount(), 1)`.

**The whole list, in order.** Scrolling to each expected tile misses an extra
tile (a row the app should hide) and a wrong order. Read the tile keys in
screen order, dragging half a viewport at a time because a lazy list puts only
visible tiles onstage, and compare them with the backend rows. The reader, in
the `Cart` module:

```dart
  Future<List<Key>> listedLines() async {
    final listed = <Key>[];
    final scrollable = $(keys.cart.list).$(Scrollable);
    while (true) {
      for (final element in $(CartLineTile).evaluate()) {
        final key = element.widget.key!;
        if (!listed.contains(key)) {
          listed.add(key);
        }
      }
      final position = $.tester.state<ScrollableState>(scrollable).position;
      if (position.extentAfter == 0) {
        return listed;
      }
      await $.tester.drag(
        scrollable,
        Offset(0, -position.viewportDimension / 2),
      );
      await $.pumpAndTrySettle();
    }
  }
```

**`expect` needs `package:flutter_test/flutter_test.dart`.** Patrol does not
re-export it. Import it in test files for `expect`, matchers and
`find.bySemanticsIdentifier` (Patrol has no identifier finder), and declare
that as a deviation from the "no flutter_test" rule of `patrol-write-test`.

**The mutation check.** Revert the app change the tests were written for and
run them. A test must fail. If none does, the tests drive the path without
asserting its result: add the assertion the change made true, and run both
ways again.

## 6. Data, seed and preconditions

- Compute expected values in the test from the backend, as the test user,
  through the endpoint and parameters the app uses. That applies the app's
  visibility rules without re-implementing them. Build keys from the rows;
  compare copy with computed values (`'${product.stock} in stock'`); take
  dates from the rows, not the device clock.
- Use two roles. The as-user role gives expected values. The admin role only
  restores seed rows and reads state the app never shows. Make the admin
  client refuse any host but `127.0.0.1`, `localhost` and `10.0.2.2`, so a
  misconfigured `.patrol.env` cannot change a shared environment.
- Assert preconditions from the backend before acting. A list test with an
  empty expected list passes while testing nothing.
- A test that consumes a seeded row resets it at its start (a previous run may
  have crashed) and at its end (other tests expect the seed). Read the final
  state into a variable before the restore, then assert on the variable. Only
  that test needs admin.
- Load the state a later check depends on before you destroy it: an isolation
  test that signs the first user out before their list rendered proves
  nothing.
- A seed dated from a fixed point can fall outside a window the app computes
  from today ("next 7 days"). Date seed rows from the reset day.
- Run each test alone (`-t`) and the whole suite.

The flow from the example app, with each rule in place:

```dart
// patrol_test/add_to_cart_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/keys.dart';

import 'common/app_harness.dart';
import 'common/test_users.dart';

const _seededProductId = String.fromEnvironment('PATROL_SEEDED_PRODUCT_ID');

void main() {
  testApp('A customer adds two of a product and finds them in the cart', (
    $,
    modules,
    system,
    apiClients,
  ) async {
    const customer = TestUsers.customer;
    final admin = apiClients.backend.asAdmin;
    await admin.removeCartLine(customer, _seededProductId);

    final asCustomer = await apiClients.backend.asUser(customer);
    final products = await asCustomer.productsInStock();
    expect(products.map((product) => product.id), contains(_seededProductId));
    final product = products.firstWhere((p) => p.id == _seededProductId);
    expect(product.stock, greaterThanOrEqualTo(2));

    await openApp($);
    await modules.signIn.signIn(customer);
    await modules.products.waitForProduct(products.first.id);
    await system.allowNotificationsIfAsked();

    await modules.products.startAdding(product.id);
    await modules.quantitySheet.chooseQuantity(product.stock + 1);
    await modules.quantitySheet.confirm();
    await modules.quantitySheet.waitForQuantityError(
      'Only ${product.stock} in stock.',
    );

    await modules.quantitySheet.chooseQuantity(2);
    await modules.quantitySheet.confirm();
    expect(
      await modules.quantitySheet.waitForAddedSnackBar(),
      'Added 2 to cart',
    );
    expect(modules.quantitySheet.snackBarCount(), 1);

    await modules.bottomTabs.openCart();
    await modules.cart.waitForLine(product.id);
    final listed = await modules.cart.listedLines();

    final lines = await asCustomer.cartLines();
    await admin.removeCartLine(customer, product.id);

    expect(listed, [
      for (final line in lines) keys.cart.line(line.productId),
    ]);
    expect(lines.firstWhere((l) => l.productId == product.id).quantity, 2);
  });
}
```

`startAdding` opens the Products tab before it taps: under an `IndexedStack`
the other tab stays built but offstage, Patrol's finders skip it, and a `tap()`
there times out.

## 7. Native prompts

Handle a permission prompt right after the screen that triggers it is visible,
with a short timeout, in a `System` method:

```dart
  Future<void> allowNotificationsIfAsked() async {
    const window = Duration(seconds: 7);
    if (await mobile.isPermissionDialogVisible(timeout: window)) {
      await mobile.grantPermissionWhenInUse();
    }
  }
```

Start the window at the triggering screen, not at an earlier tap: a cold start
takes longer, and a prompt that lands over later steps holds the focus (the
next field tap opens no keyboard). Grant unless granting crashes the app under
test; then use `denyPermission()` and file the crash as an app bug with the
Marionette evidence. State in `patrol_test/README.md` which OS versions show
the prompt: Android asks for notifications from Android 13, iOS the first time
the app requests them.

## 8. Before hand-over

Check the code against sections 2 to 7 one by one, not from memory: a green
suite does not show a skipped rule. Run the mutation check, each test alone
and the whole suite, and `dart analyze`. Keep secrets and personal data out of
the test code.

Hand over: each test with its step range, the keys added and their deviations,
the mid-test assertions, the seed rows consumed and restored, what was not
encoded and why, the mutation check result, and the last line of
`dart analyze`.
