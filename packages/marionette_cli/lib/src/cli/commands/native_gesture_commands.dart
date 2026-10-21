import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/gesture_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Adds `--x` / `--y` for gestures at a point instead of an element.
void _addPointOptions(NativeCommand command) {
  command.argParser
    ..addOption('x', help: 'X in screenshot pixels (with --y).')
    ..addOption('y', help: 'Y in screenshot pixels (with --x).');
}

class NativeTapCommand extends NativeCommand {
  NativeTapCommand(this.nativeRegistry) {
    addSelectorOptions();
    _addPointOptions(this);
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-tap';

  @override
  String get description =>
      'Tap a native element chosen by a selector, or a point.';

  @override
  Map<String, dynamic> toolArguments() => NativeCommand.compact({
        ...selectorArgs(),
        'x': number('x'),
        'y': number('y'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeTap(context, args);
}

class NativeSwipeCommand extends NativeCommand {
  NativeSwipeCommand(this.nativeRegistry) {
    for (final option in ['start-x', 'start-y', 'end-x', 'end-y']) {
      argParser.addOption(
        option,
        help: 'In screenshot pixels.',
        mandatory: true,
      );
    }
    argParser.addOption('duration-ms', help: 'Swipe duration (default 300).');
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-swipe';

  @override
  String get description =>
      'Swipe one finger between two points — drags, sliders, edge gestures '
      '(iOS back: start at x=1).';

  @override
  Map<String, dynamic> toolArguments() => NativeCommand.compact({
        'startX': number('start-x'),
        'startY': number('start-y'),
        'endX': number('end-x'),
        'endY': number('end-y'),
        'durationMs': integer('duration-ms'),
      });

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeSwipe(context, args);
}

class NativeScrollCommand extends NativeCommand {
  NativeScrollCommand(this.nativeRegistry) {
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
      ..addOption('max-swipes', help: 'Search limit (default 10).')
      ..addOption('distance', help: 'Swipe length in screenshot pixels.')
      ..addOption('start-x', help: 'Swipe start (with --start-y).')
      ..addOption('start-y', help: 'Swipe start (with --start-x).');
  }

  @override
  final NativeSessionRegistry nativeRegistry;

  @override
  String get name => 'native-scroll';

  @override
  String get description =>
      'Swipe in a direction, optionally until an element matching the '
      'selector is visible; --within-* scrolls inside a container.';

  @override
  Map<String, dynamic> toolArguments() {
    final within = NativeCommand.compact({
      'text': string('within-text'),
      'textContains': string('within-text-contains'),
      'id': string('within-id'),
      'type': string('within-type'),
      'index': integer('within-index'),
    });
    return NativeCommand.compact({
      'direction': string('direction'),
      ...selectorArgs(withIndex: false),
      if (within.isNotEmpty) 'within': within,
      'maxSwipes': integer('max-swipes'),
      'distance': number('distance'),
      'startX': number('start-x'),
      'startY': number('start-y'),
    });
  }

  @override
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  ) =>
      handleNativeScroll(context, args);
}
