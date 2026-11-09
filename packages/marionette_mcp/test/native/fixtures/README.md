# Native UI fixtures

UI trees captured from real devices and simulators, used by
`test/native/fixtures_test.dart` to test the parsers, the selector and the
coordinate conversion on real data instead of hand-written samples.

Each fixture is a pair:

- `<name>.xml` — raw page source from UIAutomator2 / WebDriverAgent, in the
  server's own units (pixels on Android, points on iOS);
- `<name>.json` — screen size in screen pixels, scale, foreground app and
  OS version at capture time.

## Capturing a fixture

Run the example app, navigate to the screen, then from `packages/marionette_mcp`:

```bash
dart run tool/capture_native_fixture.dart --platform android \
  --serial emulator-5554 --os "Android 9 (API 28)" --name android28_home
dart run tool/capture_native_fixture.dart --platform ios \
  --udid <UDID> --os "iOS 26.4" --name ios26_home
```

Before committing, check the XML for personal data (contact names, file
names, account e-mails) — fixtures are public.
