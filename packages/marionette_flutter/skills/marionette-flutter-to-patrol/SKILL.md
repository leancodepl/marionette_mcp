---
name: marionette-flutter-to-patrol
description: Turn a verified Marionette session (steps.md, report.md, screenshots) into Patrol E2E tests for a Flutter app - what to encode, the step-to-Patrol mapping, which widgets need keys, assertions and seed control derived from the report, and native prompt timing. Use whenever someone asks to write Patrol tests from a Marionette run or session, to make a Marionette-verified flow regression-proof, or to review a Patrol suite built from one. Builds on Patrol's own skills (patrol-write-test, patrol-test-architecture).
---

# Patrol tests from a Marionette session

A Marionette session is a verified script of one flow. `steps.md` holds one line per
tool call with its selector and outcome. `report.md` is the driver's summary: what it
tested and checked, and the bugs and suspicions it found. `screenshots/` is the evidence.
This skill covers only what that input changes about writing Patrol tests: what to
encode, which widgets need keys, how each step maps to Patrol, and which assertions and
data rules the report implies.

## Load the Patrol skills first

Everything about Patrol itself comes from Patrol's own skills. Load them and follow
them:

- `patrol-write-test`: order of work, Patrol API, key rules, waits, end assertions,
  native dialogs, running tests.
- `patrol-test-architecture`: the `testApp` wrapper, Modules, System
  (`extends PlatformAutomator`), ApiClients, and the `keys.dart` conventions.

If they are not installed, take them from one of these:

- The `patrol` dependency, when its release has a `skills/` folder (4.10.0 and older do
  not): `dart run skills@ get -p patrol -s patrol-write-test -s patrol-test-architecture`.
- Patrol's repository:
  `npx skills add leancodepl/patrol --skill patrol-write-test --skill patrol-test-architecture`.
- In Claude Code: `/plugin install flutter-patrol@leancode-ai-plugins`.

If the project has no `patrol_test/` yet, set Patrol up first with the `patrol-setup`
skill, from the same sources, or from https://patrol.leancode.co/documentation. Where
this skill deviates from those skills, it says so and why; declare each deviation in
the hand-over.

## The example app

The snippets use one invented app, `slots_app`. A member signs in and gets a
`NavigationBar` with Slots and Bookings tabs, kept in an `IndexedStack`. Slots lists the
member's slots for the next 7 days (a loading card, then tiles with an `N free` label and
a Book button) and asks for the notification permission the first time it shows them.
Book opens a sheet with a seat-count field: a count above the free seats shows
`Only N seats are free.` as `errorText`; a valid count closes the sheet and shows one
snackbar, `Booked N seats`. Bookings reloads when opened and lists the member's bookings
in slot start order. The backend serves the same lists to a signed-in member, and an
admin endpoint removes one member's booking (seed control).

## Inputs

Get these from the caller, or work them out and declare them as assumed:

- The session directory `.marionette/sessions/<name>/`. No session yet: turn on session
  reports (`marionette-flutter-setup`), drive the flow with
  `marionette-flutter-drive-app`, then come back.
- The spec or acceptance criteria: the behaviour each test must assert, not only taps.
- A free device id: Patrol installs its own build of the app.
- Where the test accounts are documented. Never invent data that looks like a real
  person.
- How the local backend's seed is reset, and which seeded rows a test may consume.

## 1. Read the session

Read `steps.md` and `report.md` in full, then open the screenshots the report cites.

In `steps.md`, each line is `- [time] tool selector -> outcome`. An MCP run leaves one
session directory. A CLI run leaves one directory per command and logs the CLI's
hyphenated command names (`enter-text`): read those directories in time order as one
transcript.

- `tap`, `double_tap`, `long_press`, `secondary_tap`, `enter_text`, `swipe`,
  `scroll_to`, `pinch_zoom`, `press_back_button`, `press_key` and `set_device_config`
  lines are steps to encode (see the mapping table). `connect`, `disconnect`,
  `hot_restart`, `hot_reload`, `get_interactive_elements`, `take_screenshots` and
  `get_logs` are the driver looking; they encode to nothing, but they show what was on
  screen. `call_custom_extension` and promoted extension lines (outcome `ok`) may have
  changed app state (seed, sign-in): find out what they did from the report and encode
  it as setup, or declare it.
- The selector is what the call matched: `key=`, `text=`, `type=`, `identifier=`,
  `x= y=`, `focused_element=true`, and `ancestor_keys=a>b` when the key repeats in
  identical subtrees. On a `press_key` line, `key=` is the keyboard key (`enter`,
  `tab`), not a widget key; it acts on the focused element. The outcome after `->` holds
  the rest: the swipe direction (`Swiped down on element matching: …`), or for a
  coordinate swipe `Swiped from (x1, y1) to (x2, y2)`, where a growing y is downward;
  the pinch scale; or `error: …`. `set_device_config` values are not logged; take them
  from the report or the screenshots.
- `tap x= y=` means the widget had no key and no unique text. `tap text=` may hide a
  collision that the driver resolved by position (the same word on a tab, a title and a
  tile); check the listing or the screenshot. `tap type=FilledButton` worked only
  because one such button was on screen.
- `enter_text focused_element=true` follows the tap that focused a field. Typed values
  are redacted: `input_len=N`, or `input=[redacted]` when the `key` or `identifier`
  contains pass, pin, token, secret or cvv. Take them from the report, the spec or the
  seed.
- Two consecutive `swipe` lines on one list are one scroll. A downward swipe at the top
  of a list is pull-to-refresh.
- Traps the driver hit show here: an `error:` outcome and a retry, a `tap x= y=` after a
  failed `tap text=`, a `hot_restart` in the middle of the flow. Find the cause (a
  transient snackbar, a consumed seed row, a seed dated in UTC, a missing key) and treat
  it as a requirement.

`report.md` follows the report contract of `marionette-flutter-drive-app`. It is written
in the language of the prompt that started the run, so find its parts by their icons and
tags:

- The headline icon sums up the run: `✅` no findings, `⚠️` suspicions only, `🐛` at
  least one confirmed bug.
- `Tested:`, the line under the headline (its label may be translated), names the flows
  the run covered. `Checks:`, when present, names what the
  driver verified on top (validation, back navigation, dark mode, text scale). Neither
  line gives step numbers: map each flow and check to its lines in `steps.md`.
- Numbered findings are `🐛 [bug]` or `⚠️ [suspicion]`, each with `Repro:` and
  `Evidence:` (a step, a log line or a screenshot). Report them; do not encode a bug,
  because a test written around a known bug passes for the wrong reason. Confirm a
  suspicion before you rely on it.
- A DB or API check the driver made (`psql`, a REST call) becomes a backend assertion.
- `➖ Not covered:` is out of scope. Do not invent tests for it. A run stopped early
  says why and what it left untested; encode only what it reached.

The report says what the driver saw, not what the app must do: take the expected
behaviour from the spec. Without a `report.md`, work from `steps.md`, the screenshots
and the spec, and declare that.

Then split the actions into tests: one user intention per test, each from a fresh app
launch and sign-in. Write down each test's step range; a reviewer checks coverage
against the transcript with it.

## 2. Keys the transcript asks for

A flow that Marionette drove by coordinates or text has no keys for Patrol. Add them
before any test code, as their own commit, following the `keys.dart` conventions of
`patrol-test-architecture`. The transcript says which widgets need one:

| Evidence in the session | Key it |
| --- | --- |
| `tap x= y=` | The widget under the coordinates (from the listing or the screenshot) |
| `tap text=X` where X appears more than once | Every widget the test touches that shares the text |
| `tap text=X` on a tooltip or icon label | The icon button; tooltip text is not a stable finder |
| `tap type=…` | The widget; the type match works only while it is the only one |
| `enter_text focused_element=true` | The field the preceding tap focused |
| `swipe`, `scroll_to` | The list: the `scrollTo(view:)` target and the pull-to-refresh anchor |
| A dialog, sheet or snackbar in the flow | Its fields, every button, the snackbar |
| An end state the report describes | Its container, plus the error and loading widgets that could replace it |
| Repeated tiles from data | A parameterized key from the row's id, never an index |

Three cases come up often. Declare each in the hand-over; the first changes a widget
signature, which `patrol-write-test` otherwise forbids:

- A private widget without a `key` parameter: key the root widget it returns, or add
  `super.key` when the key must sit on the list child itself.
- `const` is lost. `keys` is a `final` top-level variable, so
  `NavigationDestination(key: keys.bottomTabs.slotsTab, …)` cannot be `const`, and a
  `const [...]` list of destinations loses `const` too. No behaviour changes.
- A transient widget (snackbar, dialog, sheet) gets its key where it is created: in the
  listener or the `showModalBottomSheet` builder, not in the screen's `build`.

If the app already has `ValueKey('snake_case')` literals that Marionette used, keep the
values: define the `keys.dart` members so their full values equal the old strings (skip
the page prefix of `patrol-test-architecture` if needed, and declare that), and replace
the literals with `keys.…` references.

## 3. No Marionette binding in Patrol tests

The app's `main()` calls `MarionetteBinding.ensureInitialized(...)` in debug builds.
`patrolTest` installs its own binding before the test body, and
`MarionetteBinding.ensureInitialized` then throws: one app has one `WidgetsBinding`.
So `openApp` must never call `main()`. Move the startup (config validation, SDK init,
the API client, the root widget) into a `bootstrapApp()` that both call. This refactor
deviates from the no-refactor rule of `patrol-write-test`; declare it.

```dart
// lib/main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:slots_app/bootstrap.dart';

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
```

```dart
// patrol_test/common/app_harness.dart, next to testApp
import 'package:patrol/patrol.dart';
import 'package:slots_app/bootstrap.dart';

Future<void> openApp(PatrolIntegrationTester $) async {
  await $.pumpWidgetAndSettle(await bootstrapApp());
}
```

If the app may not change, copy the body of `main()` without the binding into `openApp`,
and declare that the two can drift.

Two more consequences of the Marionette run:

- Stop `flutter run` and the Marionette session before `patrol test`: both install and
  drive the same app on the same device.
- `.patrol.env` needs the dart-defines the Marionette run got from
  `--dart-define-from-file`. Without them, the app's config validation fails before the
  first screen. From an emulator, a local backend is at `10.0.2.2`, not `localhost`.

## 4. Translate the steps

| `steps.md` line | Patrol |
| --- | --- |
| `tap key=slots_tile_<id>` | `$(keys.slots.tile(id)).tap()` |
| `tap text=Confirm` (unique, stable copy) | A key; `$('Confirm').tap()` breaks when the copy changes |
| `tap text=…` that collided, `tap type=…`, `tap x= y=` | Add a key, then `$(keys.<page>.<widget>).tap()` |
| `tap identifier=…` | A key, or `$(find.bySemanticsIdentifier('…'))` |
| Any line with `ancestor_keys=a>b` | Chain the finders, outermost first: `$(keys.<scope>).$(keys.<widget>).tap()` |
| A tap, then `enter_text focused_element=true` | `$(keys.<page>.<field>).enterText(value)`, no separate tap |
| `swipe` on a list, `scroll_to key=` | `$(keys.<page>.<item>).scrollTo(view: $(keys.<page>.list))` |
| Downward `swipe` at the top of a list | `$.tester.fling($(keys.<page>.list), const Offset(0, 300), 1200)`, then `$.pumpAndTrySettle()` |
| `press_back_button` | On Android, `$.platform.android.pressBack()` (Patrol's `mobile` automator has no `pressBack`, as of 4.10); on iOS, tap the app's back control by key |
| `press_key` | `$.tester.sendKeyEvent(LogicalKeyboardKey.<key>)`; Enter on a text field is different (below) |
| `long_press` | `$(keys.<page>.<widget>).longPress()` |
| `double_tap` | `$.tester.tap(finder)`, `$.tester.pump(kDoubleTapMinTime)`, `$.tester.tap(finder)` |
| `secondary_tap` | `$.tester.tap(finder, buttons: kSecondaryButton)` |
| `pinch_zoom` | A two-pointer gesture (`$.tester.startGesture`), or declare it not encoded |
| `set_device_config` | Not a user action. Set `$.tester.platformDispatcher.textScaleFactorTestValue` or `platformBrightnessTestValue` with `addTearDown($.tester.platformDispatcher.clearAllTestValues)`, or declare it not encoded |
| `hot_restart`, `hot_reload`, listing, screenshot, log, `connect` lines | Nothing; each test starts the app fresh in `openApp($)` |
| A DB/API check in the report | A backend read as the test user, compared at the end |
| A native prompt in the report | A `System` method right after the screen that triggers it (section 7) |

A validation message (`errorText`) is not in Marionette's element listing; the driver
saw it in a screenshot. Find it inside the keyed field's subtree:
`$(keys.bookingSheet.seatsField).$('Only ${slot.freeSeats} seats are free.')`.
These text and type finders are deliberate exceptions to the keys-only rule of
`patrol-write-test`: `errorText` and framework widgets carry no key, and the list reader
collects the keys of the tiles it finds.

`press_key` Enter on a focused text field submits it: Marionette runs the field's
`textInputAction`. A simulated key event does not, so submit on the field itself, with
that action (`done` here):

```dart
final seatsInput = $(keys.bookingSheet.seatsField).$(EditableText);
$.tester
    .state<EditableTextState>(seatsInput)
    .performAction(TextInputAction.done);
await $.pumpAndTrySettle();
```

Pull-to-refresh can be a silent no-op. A list whose content fits the viewport has
Android's `ClampingScrollPhysics`, which refuses the drag, so the `RefreshIndicator`
never fires and `pumpAndTrySettle` hides it. The Marionette swipe on a short list may
have proven nothing either. Assert `$(RefreshProgressIndicator).waitUntilVisible()`
right after the gesture, or have the app give the list `AlwaysScrollableScrollPhysics`.

Encode every action line, or declare which ones you merged or dropped and why. A step
that looks like a detour (an invalid value before the valid one) is often the spec's
check that the error appears and clears; dropping it drops that assertion.

## 5. Assertions from the report

Each flow under `Tested:` and each item on `Checks:` becomes an assertion group at the
end of its test, as `patrol-write-test` asks. These rules keep a green test from proving
nothing.

**Positive state next to every negative check.** `isListed(slotId)` being false also
holds while the list reloads, or when an error card replaced it. Wait for the loaded
state and name what must be there:

```dart
final remaining = (await asMember.bookings())
    .where((booking) => booking.slotId != cancelledSlotId)
    .toList();
await modules.bookings.cancel(cancelledSlotId);

await modules.bookings.waitUntilLoaded();
expect(modules.bookings.isErrorShown(), isFalse);
await modules.bookings.waitForBooking(remaining.first.slotId);
expect(modules.bookings.isListed(cancelledSlotId), isFalse);
```

**A loaded-state wait, not a bare `pumpAndTrySettle()`.** It returns silently while a
spinner turns, and the checks after it then run against the loading state. Wait for the
first expected tile, or for the loading card to be gone.

**Three declared mid-test exceptions** to "assert at the end": transient UI (a snackbar
is gone by the end), a message the next action clears (a validation error), and the
refresh indicator after a pull-to-refresh gesture. Assert each
right after the action that shows it, and declare it in the hand-over. When the spec
says one snackbar, count it: `expect(modules.bookingSheet.snackBarCount(), 1)`.

**The whole list, in order.** Scrolling to each expected tile misses an extra tile (a
row the app should hide) and a wrong order. Read the tile keys in screen order, dragging
half a viewport at a time because a lazy list puts only visible tiles onstage, and
compare them with the backend rows. The reader, in the `Bookings` module:

```dart
  Future<List<Key>> listedTiles() async {
    final listed = <Key>[];
    final scrollable = $(keys.bookings.list).$(Scrollable);
    while (true) {
      for (final element in $(BookingTile).evaluate()) {
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

```dart
final bookings = await asMember.bookings();
expect(await modules.bookings.listedTiles(), [
  for (final booking in bookings) keys.bookings.tile(booking.slotId),
]);
```

**`expect` needs `package:flutter_test/flutter_test.dart`.** Patrol does not re-export
it. Import it in test files for `expect`, matchers and `find.bySemanticsIdentifier`
(Patrol has no identifier finder), and declare that finder as a deviation from the
"no flutter_test" rule of `patrol-write-test`.

**The mutation check.** Revert the app change the tests were written for and run them.
A test must fail. If none does, the tests drive the path without asserting its result:
add the assertion the change made true, and run both ways again.

## 6. Data, seed and preconditions

- Compute expected values in the test from the backend, as the test user, through the
  endpoint and parameters the app uses. That applies the app's visibility rules without
  re-implementing them. Build keys from the rows; compare copy with computed values
  (`'${slot.freeSeats} free'`); take dates from the rows, not the device clock.
- Use two roles. The as-user role gives expected values. The admin role only restores
  seed rows and reads state the app never shows. Make the admin client refuse any host
  but `127.0.0.1`, `localhost` and `10.0.2.2`, so a misconfigured `.patrol.env` cannot
  change a shared environment.
- Assert preconditions from the backend before acting. A list test with an empty
  expected list passes while testing nothing.
- A test that consumes a seeded row resets it at its start (a previous run may have
  crashed) and at its end (other tests expect the seed). Read the final state into a
  variable before the restore, then assert on the variable. Only that test needs admin.
- Load the state a later check depends on before you destroy it: an isolation test that
  signs the first user out before their list rendered proves nothing.
- A seed dated from a fixed point (the start of the week) can leave a "next 7 days"
  window empty on some days. Fix the seed to date rows from the reset day.
- Run each test alone (`-t`) and the whole suite.

The flow from the example app, with each rule in place:

```dart
// patrol_test/book_seats_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:slots_app/keys.dart';

import 'common/app_harness.dart';
import 'common/test_users.dart';

const _seededSlotId = String.fromEnvironment('PATROL_SEEDED_SLOT_ID');

void main() {
  testApp('A member books two seats and finds them under Bookings', (
    $,
    modules,
    system,
    apiClients,
  ) async {
    const member = TestUsers.member;
    final admin = apiClients.backend.asAdmin;
    await admin.cancelBooking(member, _seededSlotId);

    final asMember = await apiClients.backend.asUser(member);
    final slots = await asMember.upcomingSlots();
    expect(slots.map((slot) => slot.id), contains(_seededSlotId));
    final slot = slots.firstWhere((slot) => slot.id == _seededSlotId);
    expect(slot.freeSeats, greaterThanOrEqualTo(2));

    await openApp($);
    await modules.signIn.signIn(member);
    await modules.slots.waitForSlot(slots.first.id);
    await system.allowRemindersIfAsked();

    await modules.slots.startBooking(slot.id);
    await modules.bookingSheet.chooseSeats(slot.freeSeats + 1);
    await modules.bookingSheet.confirm();
    await modules.bookingSheet.waitForSeatsError(
      'Only ${slot.freeSeats} seats are free.',
    );

    await modules.bookingSheet.chooseSeats(2);
    await modules.bookingSheet.confirm();
    expect(
      await modules.bookingSheet.waitForBookedSnackBar(),
      'Booked 2 seats',
    );
    expect(modules.bookingSheet.snackBarCount(), 1);

    await modules.bottomTabs.openBookings();
    await modules.bookings.waitForBooking(slot.id);
    final listed = await modules.bookings.listedTiles();

    final bookings = await asMember.bookings();
    await admin.cancelBooking(member, slot.id);

    expect(listed, [
      for (final booking in bookings) keys.bookings.tile(booking.slotId),
    ]);
    expect(bookings.firstWhere((b) => b.slotId == slot.id).seats, 2);
  });
}
```

`startBooking` opens the Slots tab before it taps: under an `IndexedStack` the other tab
stays built but offstage, Patrol's finders skip it, and a `tap()` there times out.

## 7. Native prompts

Handle a permission prompt right after the screen that triggers it is visible, with a
short timeout, in a `System` method:

```dart
  Future<void> allowRemindersIfAsked() async {
    const window = Duration(seconds: 7);
    if (await mobile.isPermissionDialogVisible(timeout: window)) {
      await mobile.grantPermissionWhenInUse();
    }
  }
```

Do not start the window at the sign-in tap: a cold start takes longer, and the prompt
then lands over later steps, holding window focus (the next field tap opens no keyboard).
`grantPermissionWhenInUse()` also taps the Allow button of the Android 13+ notification
prompt. Grant unless granting crashes the app under test (an unawaited push-token
registration on an emulator without Google services does); then use `denyPermission()`
and file the crash as an app bug with the Marionette evidence. The notification prompt
exists on Android 13+ only; state the API level in `patrol_test/README.md`.

## 8. Review before hand-over

Walk this list against the code, not from memory:

- [ ] Reverting the change under test makes a test fail.
- [ ] Every `Tested:` flow and `Checks:` item is asserted; no `[bug]` finding and no
      `Not covered` item is encoded.
- [ ] Every action line is encoded, or its merge or drop is declared.
- [ ] End assertions follow a loaded-state wait and name the positive state.
- [ ] Lists are compared as the exact key sequence from the backend rows.
- [ ] Expected values and preconditions come from the backend as the test user.
- [ ] The consuming test restores its rows; the admin client refuses non-local hosts.
- [ ] Native prompts are handled after the triggering screen, with a timeout.
- [ ] Each test passes alone and in the suite.
- [ ] Mid-test assertions, key deviations and pull-to-refresh risks are declared.
- [ ] No `MarionetteBinding`, secrets or personal data in the test code.

Hand over: each test with its step range, the keys added and their deviations, the
mid-test assertions, the seed rows consumed and restored, what was not encoded and why,
the mutation check result, and the last line of `dart analyze`.
