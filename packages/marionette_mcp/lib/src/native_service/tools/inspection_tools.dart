import 'dart:async';
import 'dart:convert';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_selector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/native_service/tools/selector_args.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

const _defaultWaitTimeoutMs = 10000;
const _maxWaitTimeoutMs = 60000;

/// Consecutive failed tree reads `native_wait_for` retries before failing.
const _maxFailedWaitReads = 3;

const _defaultWaitIntervalMs = 500;
const _minWaitIntervalMs = 50;

/// What `native_wait_for` waits for.
enum NativeWaitState {
  /// At least one element matches.
  visible,

  /// No element matches.
  gone;

  static NativeWaitState? tryParse(Object? raw) => switch (raw) {
        null || 'visible' => visible,
        'gone' => gone,
        _ => null,
      };
}

/// Registers native UI hierarchy inspection tools.
void registerNativeInspectionTools(
  McpServer server,
  NativeServiceContext context,
) {
  server
    ..registerTool(
      'native_get_elements',
      description: 'Returns the native UI hierarchy as JSON: '
          '{ elements: [...], foregroundApp: string? }. '
          'Each element has type, optional text/id, bounds in screenshot '
          'pixels (the pixel grid of native_take_screenshot), and clickable; '
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
          '$nativeRoutingPreferFlutter '
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
          'UI tree every intervalMs (default $_defaultWaitIntervalMs) for up '
          'to timeoutMs (default $_defaultWaitTimeoutMs, max '
          '$_maxWaitTimeoutMs). Returns the first matching element for '
          '"visible". Use it instead of fixed sleeps for system dialogs, '
          'toasts, and screens that appear after a delay. To wait for a '
          'system screen (a picker, a browser), wait for an element you '
          'expect on it: a package name is not element text and can match '
          'a label of the app — foregroundApp of native_get_elements tells '
          'which app is in front. '
          '$nativeRoutingPreferFlutter '
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
                '$_defaultWaitTimeoutMs, max $_maxWaitTimeoutMs).',
          ),
          'intervalMs': JsonSchema.integer(
            description: 'Pause between checks in milliseconds (default '
                '$_defaultWaitIntervalMs, min $_minWaitIntervalMs).',
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
  return runTool(logger, 'get native elements', () async {
    final connector = context.requireConnector();
    // foregroundApp is a diagnostic hint: fetch it alongside the tree and
    // report null rather than failing the whole call when it is unavailable.
    final foregroundApp = includeForegroundApp
        ? connector.foregroundApp
            .then<String?>((value) => value, onError: (Object _) => null)
        : null;
    // Off-screen (zero-size) nodes are left out, as for every selector, so
    // index counts what is listed;
    // a toast has no bounds but is listed.
    final elements = (await connector.getNativeElements()).where(
      (element) =>
          element.isListed &&
          (!clickableOnly || element.clickable) &&
          filter.matches(element),
    );
    final foreground = await foregroundApp;
    final payload = <String, dynamic>{
      'elements': elements.map((e) => e.toJson()).toList(),
      if (foregroundApp != null) 'foregroundApp': foreground,
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
  final state = NativeWaitState.tryParse(args['state']);
  final timeoutMs = intArg(args, 'timeoutMs') ?? _defaultWaitTimeoutMs;
  final intervalMs = intArg(args, 'intervalMs') ?? _defaultWaitIntervalMs;

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
  return runTool(logger, 'native wait for', () async {
    final connector = context.requireConnector();
    // A system surface in front of the app is the usual reason an element
    // never appears, so the error names the foreground app.
    Future<Never> timedOut() async {
      final foregroundApp = await connector.foregroundApp
          .then<String?>((value) => value, onError: (Object _) => null);
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

    final stopwatch = Stopwatch()..start();
    var reads = 0;
    var failedReads = 0;
    while (true) {
      // One read can be slow (a server waiting for an animating UI to go
      // idle); never let it stretch the wait past timeoutMs.
      final budget = timeoutMs - stopwatch.elapsedMilliseconds;
      final List<NativeElement> elements;
      try {
        elements = await connector
            .getNativeElements()
            .timeout(Duration(milliseconds: budget > 0 ? budget : 1));
      } on TimeoutException {
        // Earlier reads worked: the element just did not change in time.
        if (reads > 0) return timedOut();
        throw NativeOperationFailedException(
          'Reading the native UI tree did not finish within ${timeoutMs}ms, '
          'so ${selector.describe()} could not be checked.',
          hint: 'The screen may be animating continuously (video, map); '
              'raise timeoutMs or check with native_take_screenshot.',
        );
      } on NativeNotConnectedException {
        rethrow;
      } catch (error) {
        // A read can fail while the app is starting (seen on iOS right
        // after a terminated app was activated): try again, but
        // let a lasting failure through instead of waiting out timeoutMs.
        failedReads++;
        final remaining = timeoutMs - stopwatch.elapsedMilliseconds;
        if (failedReads > _maxFailedWaitReads || remaining <= 0) rethrow;
        logger.info('Reading the native UI tree failed ($error); retrying');
        await Future<void>.delayed(
          Duration(
            milliseconds: remaining < intervalMs ? remaining : intervalMs,
          ),
        );
        continue;
      }
      reads++;
      failedReads = 0;
      final match =
          elements.where((e) => e.isListed && selector.matches(e)).firstOrNull;
      final done = switch (state) {
        NativeWaitState.visible => match != null,
        NativeWaitState.gone => match == null,
      };
      if (done) {
        return _waitResult(selector, state, stopwatch.elapsedMilliseconds,
            match: match);
      }

      final remaining = timeoutMs - stopwatch.elapsedMilliseconds;
      if (remaining <= 0) return timedOut();
      await Future<void>.delayed(
        Duration(milliseconds: remaining < intervalMs ? remaining : intervalMs),
      );
    }
  });
}

CallToolResult _waitResult(
  NativeSelector selector,
  NativeWaitState state,
  int elapsedMs, {
  NativeElement? match,
}) =>
    CallToolResult(
      content: [
        TextContent(
          text: jsonEncode({
            'state': state.name,
            'selector': selector.describe(),
            'elapsedMs': elapsedMs,
            if (match != null) 'element': match.toJson(),
          }),
        ),
      ],
    );
