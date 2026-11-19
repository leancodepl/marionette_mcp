import 'package:args/args.dart';
import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/gesture_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Adds `--x` / `--y` for gestures at a point instead of an element.
void _addPointOptions(NativeCommand command) {
  command.argParser
    ..addOption('x', help: 'X in screen pixels (with --y).')
    ..addOption('y', help: 'Y in screen pixels (with --x).');
}

class NativeTapCommand extends NativeCommand {
  NativeTapCommand(super.nativeRegistry, super.environment) {
    addSelectorOptions();
    _addPointOptions(this);
  }

  @override
  String get name => 'native-tap';

  @override
  String get description =>
      'Tap a native element chosen by a selector, or a point.';

  @override
  Map<String, dynamic> toolArguments(ArgResults results) =>
      NativeCommand.compact({
        ...selectorArgs(results),
        'x': number(results, 'x'),
        'y': number(results, 'y'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeTap(context, args);
}

class NativeSwipeCommand extends NativeCommand {
  NativeSwipeCommand(super.nativeRegistry, super.environment) {
    for (final option in ['start-x', 'start-y', 'end-x', 'end-y']) {
      argParser.addOption(
        option,
        help: 'In screen pixels.',
        mandatory: true,
      );
    }
    argParser.addOption(
      'duration-ms',
      help: 'Swipe duration (default $defaultSwipeDurationMs).',
    );
  }

  @override
  String get name => 'native-swipe';

  @override
  String get description =>
      'Swipe one finger between two points — drags, sliders, edge gestures '
      '(iOS back: start at x=1).';

  @override
  Map<String, dynamic> toolArguments(ArgResults results) =>
      NativeCommand.compact({
        'startX': number(results, 'start-x'),
        'startY': number(results, 'start-y'),
        'endX': number(results, 'end-x'),
        'endY': number(results, 'end-y'),
        'durationMs': integer(results, 'duration-ms'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeSwipe(context, args);
}

class NativeScrollCommand extends NativeCommand {
  NativeScrollCommand(super.nativeRegistry, super.environment) {
    argParser.addOption(
      'direction',
      help: 'Finger-swipe direction.',
      allowed: [for (final d in SwipeDirection.values) d.wireName],
      mandatory: true,
    );
    // The target to scroll to; without one, a single swipe.
    addSelectorOptions(withIndex: false);
    argParser
      ..addOption('within-text', help: 'Container to swipe in: exact text.')
      ..addOption(
        'within-text-contains',
        help: 'Container to swipe in: text substring.',
      )
      ..addOption('within-id', help: 'Container to swipe in: id.')
      ..addOption('within-type', help: 'Container to swipe in: type.')
      ..addOption(
        'within-index',
        help: 'Container to swipe in: index among matches.',
      )
      ..addOption(
        'max-swipes',
        help: 'Search limit (default $defaultMaxSwipes).',
      )
      ..addOption('distance', help: 'Swipe length in screen pixels.')
      ..addOption('start-x', help: 'Swipe start (with --start-y).')
      ..addOption('start-y', help: 'Swipe start (with --start-x).');
  }

  @override
  String get name => 'native-scroll';

  @override
  String get description =>
      'Swipe in a direction, optionally until an element matching the '
      'selector is visible; --within-* scrolls inside a container.';

  @override
  Map<String, dynamic> toolArguments(ArgResults results) {
    final within = NativeCommand.compact({
      'text': string(results, 'within-text'),
      'textContains': string(results, 'within-text-contains'),
      'id': string(results, 'within-id'),
      'type': string(results, 'within-type'),
      'index': integer(results, 'within-index'),
    });
    return NativeCommand.compact({
      'direction': string(results, 'direction'),
      ...selectorArgs(results, withIndex: false),
      if (within.isNotEmpty) 'within': within,
      'maxSwipes': integer(results, 'max-swipes'),
      'distance': number(results, 'distance'),
      'startX': number(results, 'start-x'),
      'startY': number(results, 'start-y'),
    });
  }

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeScroll(context, args);
}
