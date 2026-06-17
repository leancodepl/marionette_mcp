# Log Collection

The `get_logs` tool lets an agent read the logs your app emitted since start or since the last hot reload — invaluable for confirming an API call fired, spotting an exception, or debugging why a tap did nothing.

Logs are off by default. Wire up a `LogCollector` via `MarionetteConfiguration(logCollector: ...)`. Pick the option that matches how your app logs.

## Option 1 — the `logging` package

If your app uses Dart's [`logging`](https://pub.dev/packages/logging) package:

```bash
flutter pub add marionette_logging
```

```dart
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_logging/marionette_logging.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: LoggingLogCollector()),
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  Logger.root.level = Level.ALL;
  runApp(const MyApp());
}
```

`LoggingLogCollector` subscribes to `Logger.root.onRecord` and formats each record with timestamp, level, logger name, error, and stack trace.

## Option 2 — the `logger` package

If your app uses the [`logger`](https://pub.dev/packages/logger) package:

```bash
flutter pub add marionette_logger
```

```dart
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_logger/marionette_logger.dart';

void main() {
  final logCollector = LoggerLogCollector();

  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: logCollector),
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  final logger = Logger(
    output: MultiOutput([ConsoleOutput(), logCollector]),
  );

  runApp(const MyApp());
}
```

`LoggerLogCollector` is both a `LogCollector` and a `logger` `LogOutput`, so the single object plugs into both `MarionetteConfiguration` and your `Logger`.

## Option 3 — anything else (`PrintLogCollector`)

For custom logging setups, `PrintLogCollector` (shipped in `marionette_flutter`) gives you a manual `addLog` you can call from wherever your logs flow:

```dart
import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  final collector = PrintLogCollector();

  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: collector),
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  // Hook into your logging system.
  myLogger.onLog((message) => collector.addLog(message));

  runApp(const MyApp());
}
```

A common variant is to route Flutter's own `debugPrint` into the collector — see the [complete production `main.dart`](./configuration.md#complete-production-maindart).

## No logging

If you don't need logs, omit `logCollector`. `get_logs` will return a message explaining how to enable it.
