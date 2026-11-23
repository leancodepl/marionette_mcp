import 'dart:convert';

import 'package:marionette_mcp/src/vm_service/ui_support_library.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_report.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_state.dart';

/// Builds a widget matcher map from tool/CLI arguments.
///
/// Supports matching by key, identifier, text, type, and coordinates, plus the
/// optional `ancestor_keys` scope.
Map<String, dynamic> buildMatcher(Map<String, dynamic> args) {
  final matcher = <String, dynamic>{};
  if (args['focused_element'] == true) {
    matcher['focused'] = true;
  }
  // Flatten coordinates for VM service (which only supports string->string)
  if (args['coordinates'] case final Map<String, dynamic> coordinates) {
    matcher['x'] = coordinates['x'];
    matcher['y'] = coordinates['y'];
  }
  if (args.containsKey('key')) {
    matcher['key'] = args['key'];
  }
  if (args.containsKey('identifier')) {
    matcher['identifier'] = args['identifier'];
  }
  if (args.containsKey('text')) {
    matcher['text'] = args['text'];
  }
  if (args.containsKey('type')) {
    matcher['type'] = args['type'];
  }
  if (args.containsKey('x')) {
    matcher['x'] = args['x'];
  }
  if (args.containsKey('y')) {
    matcher['y'] = args['y'];
  }
  // The VM service only carries string values, so the scope chain travels
  // JSON-encoded rather than as a list (whose toString() is un-parseable) or
  // a delimited string (whose delimiter could appear inside a key).
  if (args['ancestor_keys'] case final List<dynamic> ancestorKeys
      when ancestorKeys.isNotEmpty) {
    matcher['ancestor_keys'] = jsonEncode(ancestorKeys);
  }
  return matcher;
}

/// Whether [matcher] identifies an element to act on.
///
/// `ancestor_keys` only narrows where the search happens, so a matcher
/// carrying nothing but a scope still selects nothing.
bool hasSelector(Map<String, dynamic> matcher) {
  return matcher.keys.any((field) => field != 'ancestor_keys');
}

/// Formats an element map for human-readable display.
String formatElement(Map<String, dynamic> element) {
  final buffer = StringBuffer();

  // Element type
  if (element['type'] != null) {
    buffer.write('Type: ${_escapeForOneLine(element['type'])}');
  }

  // Key
  if (element['key'] != null) {
    buffer.write(', Key: "${_escapeForOneLine(element['key'])}"');
  }

  // Text content
  if (element['text'] != null && element['text'] != '') {
    buffer.write(', Text: "${_escapeForOneLine(element['text'])}"');
  }

  // Additional properties
  final additionalProps = <String>[];
  element.forEach((key, value) {
    if (key != 'type' && key != 'key' && key != 'text' && value != null) {
      additionalProps.add('${_escapeForOneLine(key)}: ${formatValue(value)}');
    }
  });

  if (additionalProps.isNotEmpty) {
    buffer.write(', ${additionalProps.join(', ')}');
  }

  return buffer.toString();
}

/// Formats a value for human-readable display.
String formatValue(dynamic value) {
  if (value is String) {
    return '"${_escapeForOneLine(value)}"';
  }
  if (value is Map || value is List) {
    return jsonEncode(value);
  }
  return value.toString();
}

/// Escapes line breaks so a formatted element stays on one line, and
/// backslashes so an escaped line break differs from a literal `\n`.
String _escapeForOneLine(Object value) => value
    .toString()
    .replaceAll('\\', '\\\\')
    .replaceAll('\r', '\\r')
    .replaceAll('\n', '\\n');

/// A warning for a `marionette.interactiveElements` [response] taken while
/// the app is not in front (`appLifecycleState` other than `resumed`):
/// system UI or another screen covers it, and the listed widgets may not be
/// reachable. Null when the app is in front or the binding does not report
/// the state (only Android and iOS do). [nativeElements] names the tool /
/// command that reads the screen; null when the native lane is off.
String? coveredAppWarning(
  Map<String, dynamic> response, {
  required String? nativeElements,
}) {
  final state = response['appLifecycleState'];
  if (state is! String || state == 'resumed') return null;
  return 'Warning: the app is not in front (lifecycle: $state) — system UI '
      '(a dialog, the notification shade, a biometric prompt, a browser) or '
      'another screen covers it. The widgets below may be hidden and not '
      'reachable${nativeElements == null ? '' : '; check $nativeElements'}.';
}

/// The UI integration status of a [report] of
/// `VmServiceConnector.inspectUiSupport`, with the repair for each missing
/// integration. [scopeHint] tells how this transport takes the scope a
/// source preflight confirmed.
String describeUiSupport(
  UiSupportReport report, {
  required String scopeHint,
}) {
  final status = switch (report.missingLibraries) {
    final missing? when missing.isEmpty =>
      'UI integrations: configured (required: '
          '${_libraryNames(report.requiredLibraries)}).',
    final missing? => [
        'UI integrations: missing ${_libraryNames(missing)}.',
        for (final library in missing)
          'Add ${library.integrationPackage} (flutter pub add '
              '${library.integrationPackage}) and call '
              '.${library.integrationExtension}() on the '
              'MarionetteConfiguration.',
        'Then hot restart or relaunch the app: a hot reload does not run '
            'main() again.',
      ].join(' '),
    null when report.requiredLibraries == null =>
      'UI integrations: unverified (configured: '
          '${_libraryNames(report.configuredLibraries)}; loaded: '
          '${_libraryNames(report.observedLibraries)}). A loaded library can '
          'come from a dependency, so it does not need an integration by '
          "itself. Check which UI libraries the app's source uses, then "
          '$scopeHint.',
    null => 'UI integrations: unknown.',
  };
  return [status, if (report.diagnostic case final diagnostic?) diagnostic]
      .join(' ');
}

/// A warning with [describeUiSupport] for a listing, when [report] shows a
/// missing integration, a confirmed scope that cannot be checked, or a loaded
/// library that has no integration and that no other loaded library loads.
/// Null when there is nothing to act on.
String? uiSupportWarning(
  UiSupportReport report, {
  required String scopeHint,
}) {
  final actionable = switch (report.state) {
    UiSupportState.configured => false,
    UiSupportState.missing => true,
    UiSupportState.unknown when report.requiredLibraries?.isNotEmpty ?? false =>
      true,
    UiSupportState.unknown => switch (report.observedLibraries) {
        null => false,
        final observed => observed.difference({
            ...?report.configuredLibraries,
            for (final library in observed) ...library.transitiveLibraries,
          }).isNotEmpty,
      },
  };
  return actionable
      ? 'Warning: ${describeUiSupport(report, scopeHint: scopeHint)}'
      : null;
}

/// [libraries] by wire name, "none" when empty and "unknown" when null.
String _libraryNames(Set<UiSupportLibrary>? libraries) => switch (libraries) {
      null => 'unknown',
      final libraries when libraries.isEmpty => 'none',
      final libraries =>
        libraries.map((library) => library.wireName).join(', '),
    };
