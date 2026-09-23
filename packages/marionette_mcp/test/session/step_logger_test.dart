import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('describeStepSelector', () {
    test('picks up curated selector fields only', () {
      final selector = describeStepSelector('tap', {
        'key': 'submit_button',
        'text': 'ignored because key is present too',
      });

      expect(selector,
          'key=submit_button text=ignored because key is present too');
    });

    test('omits free-text payload fields for other tools', () {
      final selector = describeStepSelector('call_custom_extension', {
        'extension': 'foo.bar',
        'args': {'secret': 'shh'},
      });

      expect(selector, isEmpty);
    });

    test('flattens coordinates', () {
      final selector = describeStepSelector('tap', {
        'coordinates': {'x': 10, 'y': 20},
      });

      expect(selector, 'x=10 y=20');
    });

    test('redacts a connect uri to scheme://host:port', () {
      // Regression test: Flutter VM service URIs commonly embed an auth
      // token as a path segment (ws://host:PORT/TOKEN=/ws) — logging the
      // raw uri would persist that token to steps.md.
      final selector = describeStepSelector('connect', {
        'uri': 'ws://127.0.0.1:8181/AbCdEf123=/ws',
      });

      expect(selector, 'uri=ws://127.0.0.1:8181');
      expect(selector, isNot(contains('AbCdEf123')));
    });

    test('falls back to a placeholder for an unparsable uri', () {
      final selector = describeStepSelector('connect', {'uri': 'not a uri'});

      expect(selector, isNot(contains('not a uri')));
    });

    test('collapses a multiline selector value onto one physical line', () {
      // Regression test: an unnormalized multiline value would break
      // steps.md's one-line-per-call format.
      final selector = describeStepSelector('tap', {
        'text': 'Multi\nLine\n  Label',
      });

      expect(selector, 'text=Multi Line Label');
      expect(selector, isNot(contains('\n')));
    });

    group('enter_text redaction', () {
      test('records only the length for a non-sensitive field', () {
        final selector = describeStepSelector('enter_text', {
          'key': 'dob_field',
          'input': '2099-01-01',
        });

        expect(selector, 'key=dob_field input_len=10');
      });

      test('fully redacts when the selector looks sensitive', () {
        final selector = describeStepSelector('enter_text', {
          'key': 'password_field',
          'input': 'hunter2',
        });

        expect(selector, 'key=password_field input=[redacted]');
      });

      test('matches sensitive field names case-insensitively', () {
        final selector = describeStepSelector('enter_text', {
          'identifier': 'PIN_CODE',
          'input': '1234',
        });

        expect(selector, contains('input=[redacted]'));
      });

      test('also applies to the hyphenated CLI command name', () {
        final selector = describeStepSelector('enter-text', {
          'key': 'cvv_input',
          'input': '123',
        });

        expect(selector, contains('input=[redacted]'));
      });

      test('never includes the raw entered text', () {
        final selector = describeStepSelector('enter_text', {
          'key': 'name_field',
          'input': 'super secret value nobody should see',
        });

        expect(selector, isNot(contains('super secret value')));
      });
    });
  });

  group('formatStepLine', () {
    test('omits the selector separator when there is none', () {
      final line = formatStepLine('disconnect', '', 'ok');
      expect(line, matches(r'^- \[\d\d:\d\d:\d\d\] disconnect -> ok$'));
    });

    test('includes the selector when present', () {
      final line = formatStepLine('tap', 'key=submit', 'ok');
      expect(line, matches(r'^- \[\d\d:\d\d:\d\d\] tap key=submit -> ok$'));
    });
  });

  group('StepLogger.logStep', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('step_logger_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Session openSession() =>
        Session.open(Directory(p.join(tempDir.path, 'session')));

    test('is a no-op without an active session', () {
      final logger = StepLogger();
      logger.logStep(
        'tap',
        {'key': 'x'},
        const CallToolResult(content: [TextContent(text: 'ok')]),
      );
      // No session to write to, and no exception thrown.
    });

    test('appends a success line to steps.md', () {
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'tap',
        {'key': 'submit_button'},
        const CallToolResult(
          content: [TextContent(text: 'Successfully tapped')],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, contains('tap key=submit_button -> Successfully tapped'));
    });

    test('prefixes an error outcome', () {
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'tap',
        {'key': 'missing'},
        const CallToolResult(
          isError: true,
          content: [TextContent(text: 'Element not found')],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, contains('-> error: Element not found'));
    });

    test(
        'extracts the exception message and a few stack frames from a '
        'structured app-side error, instead of truncating the raw JSON', () {
      // This is the real shape marionette_flutter sends for an uncaught
      // exception (see registerInternalMarionetteExtension's catch-all):
      // VmServiceExtensionException.toString() produces
      // "Extension X failed\nError: {"exception":...,"stack":...}". Blindly
      // truncating that at 200 chars used to cut the JSON apart mid-
      // structure, often losing the exception message on a long selector.
      final session = openSession();
      final logger = StepLogger()..session = session;

      final errorJson = jsonEncode({
        'exception': 'Exception: Element matching '
            '{identifier: 25, Friday, September 25, 2026} not found',
        'stack': '#0      GestureDispatcher.tap '
            '(package:marionette_flutter/src/gestures/dispatcher.dart:45:7)\n'
            '#1      MarionetteExtensions.tap.<anonymous closure> '
            '(package:marionette_flutter/src/binding/extensions.dart:120:5)\n'
            '#2      registerInternalMarionetteExtension.<anonymous closure> '
            '(package:marionette_flutter/src/binding/register.dart:40:29)\n'
            '#3      _rootRunUnary (dart:async/zone.dart:1436:47)\n'
            '#4      _CustomZone.runUnary (dart:async/zone.dart:1335:19)\n'
            '#5      _FutureListener.handleValue '
            '(dart:async/future_impl.dart:151:18)',
        'method': 'ext.flutter.marionette.tap',
      });

      logger.logStep(
        'tap',
        {'identifier': '25, Friday, September 25, 2026'},
        CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: 'Extension marionette.tap failed\nError: $errorJson',
            ),
          ],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(
        content,
        contains(
          'error: Exception: Element matching '
          '{identifier: 25, Friday, September 25, 2026} not found [',
        ),
      );
      // The 3 application frames survive, package: stripped, no column, and
      // anonymous closures spelled <fn> (stack_trace's own convention). The
      // trailing dart:async/zone.dart run — pure SDK plumbing, not
      // application code — is folded and then dropped entirely by
      // Trace.terse because it's the outermost (trailing) part of the
      // trace, rather than eating 1 of the 4 frames in the budget for noise.
      expect(
        content,
        contains(
          'GestureDispatcher.tap '
          '(marionette_flutter/src/gestures/dispatcher.dart:45) › '
          'MarionetteExtensions.tap.<fn> '
          '(marionette_flutter/src/binding/extensions.dart:120) › '
          'registerInternalMarionetteExtension.<fn> '
          '(marionette_flutter/src/binding/register.dart:40)',
        ),
      );
      expect(content, isNot(contains('_rootRunUnary')));
      expect(content, isNot(contains('_CustomZone.runUnary')));
      expect(content, isNot(contains('"exception"')));
      expect(content, isNot(contains('"stack"')));
    });

    test(
        'folds SDK frames in the middle of the trace into one instead of '
        'losing an application frame to the budget', () {
      // Regression test for the value of using package:stack_trace's
      // Trace.terse instead of naively taking the first N raw lines: when
      // SDK noise sits between two application frames (not just trailing),
      // it's folded into a single frame rather than either being kept
      // verbatim (wasting budget) or naively counted against the 4-frame
      // cap the same as a real application frame.
      final session = openSession();
      final logger = StepLogger()..session = session;

      final errorJson = jsonEncode({
        'exception': 'Exception: boom',
        'stack': '#0      AppCode.first (package:marionette_flutter/a.dart:1:1)\n'
            '#1      _rootRunUnary (dart:async/zone.dart:1436:47)\n'
            '#2      _CustomZone.runUnary (dart:async/zone.dart:1335:19)\n'
            '#3      _FutureListener.handleValue (dart:async/future_impl.dart:151:18)\n'
            '#4      AppCode.second (package:marionette_flutter/b.dart:2:2)',
      });

      logger.logStep(
        'tap',
        {},
        CallToolResult(
          isError: true,
          content: [TextContent(text: 'Extension x failed\nError: $errorJson')],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, contains('AppCode.first (marionette_flutter/a.dart:1)'));
      expect(content, contains('AppCode.second (marionette_flutter/b.dart:2)'));
      // The 3 middle SDK frames are folded into a single representative
      // frame — not kept verbatim (3 separate entries eating the 4-frame
      // cap on pure noise), and not silently dropped either (unlike a
      // trailing/outermost fold, a fold in the middle of the trace is kept,
      // just simplified: no line/column, "-patch" and library path
      // stripped).
      expect(content, isNot(contains('_rootRunUnary')));
      expect(content, isNot(contains('_CustomZone.runUnary')));
      expect(
        content,
        contains(
          'AppCode.first (marionette_flutter/a.dart:1) › '
          '_FutureListener.handleValue (dart:async) › '
          'AppCode.second (marionette_flutter/b.dart:2)',
        ),
      );
    });

    test(
        'falls back to the plain message for a deliberate, non-JSON '
        'error', () {
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'get_logs',
        {},
        const CallToolResult(
          isError: true,
          content: [TextContent(text: 'No log collector configured.')],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, contains('-> error: No log collector configured.'));
    });

    test(
        'redacts a uri embedded in a success message, not just the '
        'selector', () {
      // Regression test: redacting only the uri= selector left the same
      // token reachable through the outcome — connect's own success text
      // ("Successfully connected to app at $uri...") repeats the full uri,
      // and connect is in the short-confirmation allowlist so that text is
      // echoed into steps.md verbatim.
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'connect',
        {'uri': 'ws://127.0.0.1:8181/AbCdEf123=/ws'},
        const CallToolResult(
          content: [
            TextContent(
              text: 'Successfully connected to app at '
                  'ws://127.0.0.1:8181/AbCdEf123=/ws\n'
                  'Opened session: /tmp/x',
            ),
          ],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, isNot(contains('AbCdEf123')));
      expect(content, contains('ws://127.0.0.1:8181'));
    });

    test('redacts a uri embedded in an error message', () {
      // A reconnect attempt that fails while a prior session is still open
      // (no disconnect in between) still logs into that session — and a
      // thrown connection error's message commonly echoes the uri it tried.
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'connect',
        {'uri': 'ws://127.0.0.1:8181/AbCdEf123=/ws'},
        const CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: 'Failed to connect to app: SocketException: '
                  'Connection refused (uri: ws://127.0.0.1:8181/AbCdEf123=/ws)',
            ),
          ],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, isNot(contains('AbCdEf123')));
    });

    test('does not persist a data-listing tool\'s payload on success', () {
      // Regression test: get_interactive_elements, get_logs, and
      // call_custom_extension can return arbitrary application data —
      // echoing the first 200 characters of that into steps.md contradicts
      // the no-payload design and can retain application secrets.
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'get_interactive_elements',
        {},
        const CallToolResult(
          content: [
            TextContent(
                text: 'Found 1 element(s):\nType: TextField, '
                    'Text: "user@example.com"'),
          ],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, contains('get_interactive_elements -> ok'));
      expect(content, isNot(contains('user@example.com')));
    });

    test('still reports the full error message for a data-listing tool', () {
      // Errors are diagnostic context the report contract explicitly wants
      // (steps.md's "the error returned... the 'element not found'
      // detail"), unlike a successful payload — this applies regardless of
      // which tool produced it.
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'get_logs',
        {},
        const CallToolResult(
          isError: true,
          content: [TextContent(text: 'No log collector configured')],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, contains('-> error: No log collector configured'));
    });

    test('does not persist a custom/dynamic extension tool\'s payload', () {
      // Dynamically-promoted custom extension tools aren't known by name
      // ahead of time, so they must default to the safe, generic outcome
      // rather than being explicitly allowlisted one by one.
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'app_navigation_go_to_page',
        {},
        const CallToolResult(
          content: [TextContent(text: '{"userToken":"abc123","ok":true}')],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, contains('app_navigation_go_to_page -> ok'));
      expect(content, isNot(contains('abc123')));
    });

    test('appends multiple calls as separate lines', () {
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'tap',
        {'key': 'a'},
        const CallToolResult(content: [TextContent(text: 'ok')]),
      );
      logger.logStep(
        'tap',
        {'key': 'b'},
        const CallToolResult(content: [TextContent(text: 'ok')]),
      );

      final lines = session.stepsFile
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .toList();
      expect(lines, hasLength(2));
    });

    test('summarizes an image-only result without a payload', () {
      final session = openSession();
      final logger = StepLogger()..session = session;

      logger.logStep(
        'take_screenshots',
        {},
        const CallToolResult(
          content: [ImageContent(data: 'base64==', mimeType: 'image/png')],
        ),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content, contains('-> 1 screenshot(s) captured'));
      expect(content, isNot(contains('base64==')));
    });

    test('truncates a very long outcome message', () {
      final session = openSession();
      final logger = StepLogger()..session = session;
      final longText = 'x' * 500;

      logger.logStep(
        'get_logs',
        {},
        CallToolResult(content: [TextContent(text: longText)]),
      );

      final content = session.stepsFile.readAsStringSync();
      expect(content.length, lessThan(400));
    });
  });

  group('withStepLogging', () {
    test('logs after the wrapped callback resolves', () async {
      final tempDir = Directory.systemTemp.createTempSync('with_step_logging_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final session = Session.open(Directory(p.join(tempDir.path, 's')));
      final stepLogger = StepLogger()..session = session;

      final wrapped = withStepLogging(
        stepLogger,
        'hot_reload',
        (args, extra) async =>
            const CallToolResult(content: [TextContent(text: 'reloaded')]),
      );

      final result = await wrapped(const {}, _fakeExtra());

      expect((result.content.single as TextContent).text, 'reloaded');
      expect(session.stepsFile.readAsStringSync(), contains('hot_reload'));
    });
  });
}

RequestHandlerExtra _fakeExtra() => RequestHandlerExtra(
      signal: BasicAbortController().signal,
      requestId: 1,
      sendNotification: (notification, {relatedTask}) async {},
      sendRequest: <T extends BaseResultData>(
        request,
        resultFactory,
        options,
      ) async =>
          throw UnimplementedError(),
    );
