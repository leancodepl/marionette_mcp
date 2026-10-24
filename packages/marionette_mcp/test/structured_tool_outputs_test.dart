import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/mcp/server_context.dart';
import 'package:marionette_mcp/src/mcp/tools/tools.dart';
import 'package:marionette_mcp/src/session/screenshot_service.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class _Connector implements VmServiceConnector {
  Map<String, dynamic> response = {};
  bool systemSuccess = true;
  bool fails = false;

  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (fails) return Future<Map<String, dynamic>>.error(StateError('offline'));
    if (invocation.memberName == #hotReload ||
        invocation.memberName == #hotRestart) {
      return Future<bool>.value(systemSuccess);
    }
    return Future<Map<String, dynamic>>.value(response);
  }
}

class _Extra implements RequestHandlerExtra {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _Connector connector;
  late Map<String, BaseTool> tools;
  final extra = _Extra();

  setUp(() {
    connector = _Connector();
    final context = VmServiceContext(connector: connector);
    addTearDown(context.dispose);
    tools = {
      for (final tool in createAllTools(context: context)) tool.name: tool
    };
  });

  void validate(String name, CallToolResult result) {
    expect(result.isError, isFalse);
    expect(result.structuredContent, isNotNull);
    tools[name]!.outputSchema!.validate(result.structuredContent);
  }

  final actionCases = <String, (Map<String, dynamic>, String)>{
    'set_device_config': ({'reset': true}, 'Device config updated'),
    'tap': ({'key': 'target'}, 'Successfully tapped'),
    'secondary_tap': ({'key': 'target'}, 'Successfully secondary tapped'),
    'double_tap': ({'key': 'target'}, 'Successfully double tapped'),
    'long_press': ({'key': 'target'}, 'Successfully long pressed'),
    'swipe': ({'key': 'target', 'direction': 'up'}, 'Successfully swiped'),
    'pinch_zoom': ({'key': 'target', 'scale': 2}, 'Successfully pinch zoomed'),
    'press_back_button': ({}, 'Back button pressed, no route to pop'),
    'scroll_to': ({'key': 'target'}, 'Successfully scrolled to element'),
    'press_key': ({'key': 'enter'}, 'Successfully pressed key'),
    'enter_text': (
      {'key': 'target', 'input': 'hello'},
      'Successfully entered text'
    ),
    'hot_reload': ({}, 'Hot reload completed successfully'),
    'hot_restart': ({}, 'Hot restart completed successfully'),
  };

  test('all 20 built-in tools have schemas with required fields', () {
    expect(tools, hasLength(20));
    for (final tool in tools.values) {
      expect(tool.outputSchema, isNotNull, reason: tool.name);
      expect(tool.outputSchema!.required, isNotEmpty, reason: tool.name);
      expect(
        () => tool.outputSchema!.validate({}),
        throwsA(isA<JsonSchemaValidationException>()),
        reason: tool.name,
      );
    }
  });

  for (final entry in actionCases.entries) {
    test('${entry.key} preserves fallback text with structured message',
        () async {
      final result = await tools[entry.key]!.execute(entry.value.$1, extra);
      validate(entry.key, result);
      expect((result.content.single as TextContent).text, entry.value.$2);
      expect(result.structuredContent, {'message': entry.value.$2});
    });

    if (!entry.key.startsWith('hot_')) {
      test('${entry.key} preserves app-provided confirmation', () async {
        connector.response = {'message': 'App confirmation'};
        final result = await tools[entry.key]!.execute(entry.value.$1, extra);
        validate(entry.key, result);
        expect((result.content.single as TextContent).text, 'App confirmation');
        expect(result.structuredContent, {'message': 'App confirmation'});
      });
    }
  }

  test('back result includes the runtime didPop boolean', () async {
    for (final didPop in [true, false]) {
      connector.response = {'didPop': didPop};
      final result = await tools['press_back_button']!.execute({}, extra);
      validate('press_back_button', result);
      expect(result.structuredContent!['didPop'], didPop);
      expect(
          (result.content.single as TextContent).text,
          didPop
              ? 'Back button pressed, route was popped'
              : 'Back button pressed, no route to pop');
    }
  });

  test('inspection preserves extensible element objects and count', () async {
    final elements = [
      {
        'type': 'Button',
        'key': 'submit',
        'futureField': {'enabled': true}
      },
    ];
    connector.response = {'elements': elements};
    final result = await tools['get_interactive_elements']!.execute({}, extra);
    validate('get_interactive_elements', result);
    expect(result.structuredContent, {'elements': elements, 'count': 1});
    expect((result.content.single as TextContent).text,
        startsWith('Found 1 interactive element(s):\n'));
  });

  test('empty inspection still provides an empty array', () async {
    connector.response = {'elements': []};
    final result = await tools['get_interactive_elements']!.execute({}, extra);
    validate('get_interactive_elements', result);
    expect(result.structuredContent, {'elements': [], 'count': 0});
    expect((result.content.single as TextContent).text,
        'Found 0 interactive element(s):\n\n');
  });

  test('logs preserve strings and empty results', () async {
    for (final logs in <List<String>>[
      [],
      ['hello', 'second\nline']
    ]) {
      connector.response = {'logs': logs, 'count': logs.length};
      final result = await tools['get_logs']!.execute({}, extra);
      validate('get_logs', result);
      expect(result.structuredContent, {'logs': logs, 'count': logs.length});
      expect(
          (result.content.single as TextContent).text,
          logs.isEmpty
              ? 'No logs collected'
              : 'Collected 2 log entries:\n\nhello\nsecond\nline\n');
    }
  });

  test('extension discovery preserves empty and extensible entries', () async {
    for (final extensions in <List<Map<String, dynamic>>>[
      [],
      [
        {'name': 'app.status', 'description': 'Status', 'extra': 1}
      ],
    ]) {
      connector.response = {'extensions': extensions};
      final result = await tools['list_custom_extensions']!.execute({}, extra);
      validate('list_custom_extensions', result);
      expect(result.structuredContent,
          {'extensions': extensions, 'count': extensions.length});
      expect(
          (result.content.single as TextContent).text,
          extensions.isEmpty
              ? 'No custom extensions registered.'
              : 'Found 1 custom extension(s):\n\n- app.status: Status\n');
    }
  });

  test('generic extension response uses a required extensible envelope',
      () async {
    connector.response = {
      'custom': {
        'nested': [1, true, null]
      },
      'ok': true
    };
    final result = await tools['call_custom_extension']!
        .execute({'extension': 'app.status'}, extra);
    validate('call_custom_extension', result);
    expect(result.structuredContent, {'response': connector.response});
    expect((result.content.single as TextContent).text,
        jsonEncode(connector.response));
  });

  test('inline screenshots preserve images without duplicating base64',
      () async {
    connector.response = {
      'screenshots': ['aGVsbG8=', 'd29ybGQ=']
    };
    final result = await tools['take_screenshots']!.execute({}, extra);
    validate('take_screenshots', result);
    expect(result.structuredContent, {'count': 2, 'inline': true});
    expect(result.content.map((c) => (c as ImageContent).data),
        ['aGVsbG8=', 'd29ybGQ=']);
    expect(
        result.content
            .every((c) => (c as ImageContent).mimeType == 'image/png'),
        isTrue);
  });

  test('empty screenshots retain the requested inline mode', () async {
    connector.response = {'screenshots': []};
    for (final inline in [true, false]) {
      final result =
          await tools['take_screenshots']!.execute({'inline': inline}, extra);
      validate('take_screenshots', result);
      expect(result.structuredContent, {'count': 0, 'inline': inline});
      expect((result.content.single as TextContent).text,
          'No screenshots captured');
    }
  });

  test('saved screenshots report the actual written paths', () async {
    final directory =
        Directory.systemTemp.createTempSync('structured-screenshots-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final session = Session.open(directory);
    connector.response = {
      'screenshots': ['aGVsbG8=']
    };
    final tool = TakeScreenshotsTool(
      ScreenshotService(connector),
      logging.Logger.detached('structured-screenshots'),
      () => session,
    );
    final result = await tool.execute({'inline': false}, extra);
    validate('take_screenshots', result);
    final paths = (result.structuredContent!['paths'] as List<String>);
    expect(result.structuredContent,
        {'count': 1, 'inline': false, 'paths': paths});
    expect(File(paths.single).readAsBytesSync(), utf8.encode('hello'));
    expect((result.content.single as TextContent).text,
        'Saved 1 screenshot(s):\n${paths.single}');
  });

  test('connector failures preserve error results without structured content',
      () async {
    connector.fails = true;
    for (final entry
        in actionCases.entries.where((e) => !e.key.startsWith('hot_'))) {
      final result = await tools[entry.key]!.execute(entry.value.$1, extra);
      expect(result.isError, isTrue, reason: entry.key);
      expect(result.structuredContent, isNull);
      expect((result.content.single as TextContent).text, contains('offline'));
    }
  });

  test('screenshot connector failures retain the standard error wrapper',
      () async {
    connector.fails = true;
    final result = await tools['take_screenshots']!.execute({}, extra);
    expect(result.isError, isTrue);
    expect(result.structuredContent, isNull);
    expect((result.content.single as TextContent).text, 'Bad state: offline');
  });

  test('validation and system failures retain isError semantics', () async {
    connector.systemSuccess = false;
    for (final (name, args) in <(String, Map<String, dynamic>)>[
      ('set_device_config', {}),
      ('double_tap', {'delay': 0}),
      ('swipe', {}),
      ('pinch_zoom', {'scale': 2}),
      ('press_key', {'key': 'enter', 'modifiers': 'invalid'}),
      ('enter_text', {'input': 'hello'}),
      ('get_interactive_elements', {'compaction': 'invalid'}),
      ('hot_reload', {}),
      ('hot_restart', {}),
    ]) {
      final result = await tools[name]!.execute(args, extra);
      expect(result.isError, isTrue, reason: name);
      expect(result.structuredContent, isNull, reason: name);
    }
    connector.response = {
      'screenshots': ['aGVsbG8=']
    };
    final result =
        await tools['take_screenshots']!.execute({'inline': false}, extra);
    expect(result.isError, isTrue);
    expect(result.structuredContent, isNull);
    expect(
      (result.content.single as TextContent).text,
      'inline: false requires an active session, which is '
      'only created once connect succeeds and only when the app '
      'enables session reports '
      '(MarionetteConfiguration.enableSessionReports).',
    );
  });
}
