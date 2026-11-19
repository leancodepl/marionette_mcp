import 'dart:async';
import 'dart:convert';
import 'dart:math' show max, min;

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_selector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_runner.dart';
import 'package:marionette_mcp/src/native_service/tools/selector_args.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// `native_wait_for`'s timeout when `timeoutMs` is not given.
const defaultWaitTimeoutMs = 10000;
const _maxWaitTimeoutMs = 60000;

/// Consecutive failed tree reads `native_wait_for` retries before failing.
const _maxFailedWaitReads = 3;

/// `native_wait_for`'s pause between reads when `intervalMs` is not given.
const defaultWaitIntervalMs = 500;
const _minWaitIntervalMs = 50;

/// Longest a timed-out `native_wait_for` waits for the foregroundApp its
/// error names (a hung device server would hold it for minutes).
const _timedOutForegroundAppTimeout = Duration(seconds: 2);

const _toastLimitNote = 'A toast cannot be read on recent Android '
    'versions (the tree read fails while it shows) or on iOS; '
    'native_take_screenshot shows it.';

/// What `native_wait_for` waits for.
enum NativeWaitState {
  /// At least one element matches.
  visible,

  /// No element matches.
  gone,
}

/// Registers native UI hierarchy inspection tools.
void registerNativeInspectionTools(
  LoggedMcpServer server,
  NativeServiceContext context,
) {
  server
    ..registerTool(
      'native_get_elements',
      description: 'Returns the native UI hierarchy as JSON: '
          '{ elements: [...], foregroundApp: string? }. '
          'Each element has type, optional text/id, bounds in screen pixels '
          '(the units native x/y take), and clickable; '
          'state is included only when it carries information: value (typed '
          'content of a field — on iOS the only place a Flutter field shows '
          'it), enabled: false, focused: true (Android only), checked '
          '(switches, checkboxes, radios), selected: true, scrollable: true '
          '(containers usable as native_scroll within). '
          'Elements are listed in UI-tree order; the index selector of other '
          'native tools counts matches in this order. '
          'Optional filters (text, textContains, id, type, clickableOnly) '
          'shrink the output on busy screens. '
          'Use when the target is missing from get_interactive_elements or a '
          'system surface covers the app. foregroundApp (Android package / '
          'iOS bundle id) helps detect permission controllers and other '
          'system UIs on top of the Flutter app. Prefer Flutter '
          'get_interactive_elements first. '
          '$_toastLimitNote '
          'Requires native_connect.',
      annotations: const ToolAnnotations(
        title: 'Get Native Elements',
        readOnlyHint: true,
        idempotentHint: true,
      ),
      inputSchema: ToolInputSchema(
        properties: {
          ...nativeSelectorProperties(withIndex: false),
          'clickableOnly': JsonSchema.boolean(
            description: 'Return only clickable elements (default false).',
          ),
          'includeForegroundApp': JsonSchema.boolean(
            description: 'Include foregroundApp (default true). Skipping it '
                'saves a device call.',
          ),
        },
      ),
      callback: (args, extra) => handleNativeGetElements(context, args),
    )
    ..registerTool(
      'native_wait_for',
      description: 'Waits until a native element matching the selector (text, '
          'textContains, id, type — values from native_get_elements) is '
          'visible, or with state "gone" until none matches. Polls the native '
          'UI tree every intervalMs (default $defaultWaitIntervalMs) for up '
          'to timeoutMs (default $defaultWaitTimeoutMs, max '
          '$_maxWaitTimeoutMs). Returns the first matching element for '
          '"visible". Use it instead of fixed sleeps for system dialogs '
          'and screens that appear after a delay. To wait for a '
          'system screen (a picker, a browser), wait for an element you '
          'expect on it: a package name is not element text and can match '
          'a label of the app — foregroundApp of native_get_elements tells '
          'which app is in front. '
          '$_toastLimitNote '
          'Requires native_connect.',
      annotations: const ToolAnnotations(
        title: 'Native Wait For',
        readOnlyHint: true,
      ),
      inputSchema: ToolInputSchema(
        properties: {
          ...nativeSelectorProperties(withIndex: false),
          'state': JsonSchema.string(
            description: '"visible" (default) or "gone".',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Maximum wait in milliseconds (default '
                '$defaultWaitTimeoutMs, max $_maxWaitTimeoutMs).',
          ),
          'intervalMs': JsonSchema.integer(
            description: 'Pause between checks in milliseconds (default '
                '$defaultWaitIntervalMs, min $_minWaitIntervalMs).',
          ),
        },
      ),
      callback: (args, extra) => handleNativeWaitFor(context, args),
    );
}

/// Handles `native_get_elements`.
Future<CallToolResult> handleNativeGetElements(
  NativeServiceContext context, [
  Map<String, dynamic> args = const {},
]) {
  final logger = context.logger;
  final filter = nativeSelectorFromArgs(args);
  final clickableOnly = args['clickableOnly'] == true;
  final includeForegroundApp = args['includeForegroundApp'] != false;

  logger.info('Getting native elements (filter: ${filter.describe()}, '
      'clickableOnly: $clickableOnly)');
  return runNativeTool(logger, 'get native elements', () async {
    final connector = context.requireConnector();
    final treeRead = connector.getNativeElements();
    final lookup = includeForegroundApp
        ? _foregroundAppOrNull(connector.foregroundApp, logger)
        : Future<String?>.value();
    // eagerError: a failed tree read is not held by a hung lookup, and a
    // lookup error that comes after it is dropped, not left uncaught.
    await Future.wait([treeRead, lookup], eagerError: true);
    final tree = await treeRead;
    final foregroundApp = await lookup;
    // Off-screen (zero-size) nodes are left out, as for every selector, so
    // index counts what is listed;
    // a toast has no bounds but is listed.
    final elements = tree.where(
      (element) =>
          element.isListed &&
          (!clickableOnly || element.clickable) &&
          filter.matches(element),
    );
    final payload = <String, dynamic>{
      'elements': elements.map((e) => e.toJson()).toList(),
      if (includeForegroundApp) 'foregroundApp': foregroundApp,
    };
    return CallToolResult(
      content: [TextContent(text: jsonEncode(payload))],
    );
  });
}

/// Handles `native_wait_for`.
Future<CallToolResult> handleNativeWaitFor(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final selector = nativeSelectorFromArgs(args);
  final state = enumArg(
    args,
    'state',
    NativeWaitState.values,
    defaultValue: NativeWaitState.visible,
  );
  final timeoutMs = intArg(args, 'timeoutMs') ?? defaultWaitTimeoutMs;
  final intervalMs = intArg(args, 'intervalMs') ?? defaultWaitIntervalMs;

  if (selector.isEmpty) {
    return invalidArguments(
      'native_wait_for requires a selector (text, textContains, id, type).',
    );
  }
  if (state == null) {
    return invalidArguments(
      'native_wait_for state must be "visible" or "gone".',
    );
  }
  if (timeoutMs <= 0 || timeoutMs > _maxWaitTimeoutMs) {
    return invalidArguments(
      'Parameter "timeoutMs" must be between 1 and $_maxWaitTimeoutMs.',
    );
  }
  if (intervalMs < _minWaitIntervalMs) {
    return invalidArguments(
      'Parameter "intervalMs" must be at least $_minWaitIntervalMs.',
    );
  }

  logger.info('Native waiting for ${selector.describe()} to be '
      '${state.name} (timeout ${timeoutMs}ms)');
  return runNativeTool(
    logger,
    'native wait for',
    () => _NativeWait(
      context.requireConnector(),
      logger,
      selector: selector,
      state: state,
      timeoutMs: timeoutMs,
      intervalMs: intervalMs,
    ).run(),
  );
}

/// One `native_wait_for` call: reads the tree every [intervalMs] until
/// [state] holds for [selector], or fails after [timeoutMs].
final class _NativeWait {
  _NativeWait(
    this.connector,
    this.logger, {
    required this.selector,
    required this.state,
    required this.timeoutMs,
    required this.intervalMs,
  });

  final NativeConnector connector;
  final logging.Logger logger;
  final NativeSelector selector;
  final NativeWaitState state;
  final int timeoutMs;
  final int intervalMs;

  final _stopwatch = Stopwatch();
  var _reads = 0;

  int get _remainingMs => timeoutMs - _stopwatch.elapsedMilliseconds;

  Future<CallToolResult> run() async {
    _stopwatch.start();
    while (true) {
      final elements = await _readTree();
      final match =
          elements.where((e) => e.isListed && selector.matches(e)).firstOrNull;
      final done = switch (state) {
        NativeWaitState.visible => match != null,
        NativeWaitState.gone => match == null,
      };
      if (done) return _succeeded(match);

      final remaining = _remainingMs;
      if (remaining <= 0) return _timedOut();
      await Future<void>.delayed(
        Duration(milliseconds: min(remaining, intervalMs)),
      );
    }
  }

  /// Reads the tree within the time left. A failed read is tried again, up
  /// to [_maxFailedWaitReads] times in a row.
  Future<List<NativeElement>> _readTree() async {
    var failedReads = 0;
    while (true) {
      try {
        // One read can be slow (a server waiting for an animating UI to go
        // idle); never let it stretch the wait past timeoutMs.
        final elements = await connector
            .getNativeElements()
            .timeout(Duration(milliseconds: max(_remainingMs, 1)));
        _reads++;
        return elements;
      } on TimeoutException {
        // Earlier reads worked: the element just did not change in time.
        if (_reads > 0) return _timedOut();
        throw NativeOperationFailedException(
          'Reading the native UI tree did not finish within ${timeoutMs}ms, '
          'so ${selector.describe()} could not be checked.',
          hint: 'The screen may be animating continuously (video, map); '
              'raise timeoutMs or check with native_take_screenshot. If the '
              'screenshot hangs too, the device-side server is frozen: call '
              'native_connect again.',
        );
      } on NativeNotConnectedException {
        rethrow;
      } catch (error) {
        // A read can fail while the app is starting (seen on iOS right
        // after a terminated app was activated): try again, but
        // let a lasting failure through instead of waiting out timeoutMs.
        failedReads++;
        final remaining = _remainingMs;
        if (failedReads > _maxFailedWaitReads || remaining <= 0) rethrow;
        logger.info('Reading the native UI tree failed ($error); retrying');
        await Future<void>.delayed(
          Duration(milliseconds: min(remaining, intervalMs)),
        );
      }
    }
  }

  CallToolResult _succeeded(NativeElement? match) => CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'state': state.name,
              'selector': selector.describe(),
              'elapsedMs': _stopwatch.elapsedMilliseconds,
              if (match != null) 'element': match.toJson(),
            }),
          ),
        ],
      );

  /// Fails the wait. A system surface in front of the app is the usual
  /// reason an element never appears, so the error names the foreground app.
  Future<Never> _timedOut() async {
    final foregroundApp = await _foregroundAppOrNull(
      connector.foregroundApp.timeout(_timedOutForegroundAppTimeout),
      logger,
    );
    final inApp = foregroundApp == null ? '' : ' in $foregroundApp';
    throw switch (state) {
      NativeWaitState.visible => NativeElementNotFoundException(
          '${selector.describe()} within ${timeoutMs}ms$inApp',
          hint: 'Call native_get_elements to see the current screen, or '
              'raise timeoutMs if the element appears later.',
        ),
      NativeWaitState.gone => NativeOperationFailedException(
          'Native element ${selector.describe()} is still visible after '
          '${timeoutMs}ms.',
          hint: 'Dismiss it (e.g. native_tap) or raise timeoutMs.',
        ),
    };
  }
}

/// The result of [lookup] ([NativeConnector.foregroundApp]), or null when it
/// fails or times out. It only explains a result, so the tool goes on
/// without it and the failure is logged.
Future<String?> _foregroundAppOrNull(
  Future<String?> lookup,
  logging.Logger logger,
) async {
  try {
    return await lookup;
  } on Exception catch (error, stackTrace) {
    logger.warning('Failed to read foregroundApp', error, stackTrace);
    return null;
  }
}
