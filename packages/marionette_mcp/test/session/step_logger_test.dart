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
        Session.open(Directory(p.join(tempDir.path, 'session')),
            resumed: false);

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
      final session =
          Session.open(Directory(p.join(tempDir.path, 's')), resumed: false);
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
