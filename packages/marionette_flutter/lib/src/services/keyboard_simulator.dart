import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A resolved key: the physical/logical pair plus the base character it
/// produces (lower-case, or `null` for non-printable keys like Enter/Tab).
typedef _KeyDef = ({
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey logical,
  String? character,
});

/// Simulates hardware key presses against the currently focused element.
///
/// Unlike [TextInputSimulator], which rewrites a field's value directly, this
/// produces real [KeyEvent]s that flow through [HardwareKeyboard] and the
/// focus system. That lets `Focus.onKeyEvent`, `Shortcuts`/`Actions`, focus
/// traversal (Tab), and editing intents (arrows, Backspace, Enter) all respond
/// exactly as they would to a physical keyboard.
class KeyboardSimulator {
  KeyboardSimulator();

  // KeyData/KeyEvent timestamps must be monotonically increasing. Real
  // timestamps don't matter for dispatch, so a simple counter suffices.
  int _timeStampMicros = 0;

  /// Presses [keyName] once (down then up), optionally with [modifiers] held
  /// for the duration of the press.
  ///
  /// [keyName] is matched case-insensitively against [supportedKeyNames] (and
  /// single characters `a`-`z` / `0`-`9`). [modifiers] is any subset of
  /// `control`, `shift`, `alt`, `meta`.
  ///
  /// Throws [ArgumentError] for an unknown key or modifier; the extension layer
  /// turns that into an `invalidParams` response.
  Future<void> pressKey(
    String keyName, {
    Set<String> modifiers = const {},
  }) async {
    final keyDef = _resolveKey(keyName);
    if (keyDef == null) {
      throw ArgumentError(
        'Unknown key "$keyName". Supported keys: '
        '${supportedKeyNames.join(', ')}, plus single characters a-z and 0-9.',
      );
    }

    final modifierDefs = <_KeyDef>[];
    var hasShift = false;
    var hasNonShiftModifier = false;
    for (final modifier in modifiers) {
      final normalized = modifier.toLowerCase();
      final def = _modifierKeys[normalized];
      if (def == null) {
        throw ArgumentError(
          'Unknown modifier "$modifier". Supported modifiers: '
          '${_modifierKeys.keys.join(', ')}.',
        );
      }
      modifierDefs.add(def);
      if (normalized == 'shift') {
        hasShift = true;
      } else {
        hasNonShiftModifier = true;
      }
    }

    // A character is only delivered for an unmodified (or shift-only) printable
    // key — Ctrl+A must not also type "a".
    String? character;
    if (!hasNonShiftModifier && keyDef.character != null) {
      character = hasShift ? keyDef.character!.toUpperCase() : keyDef.character;
    }

    // Press modifiers, then the key down/up, then release modifiers in reverse
    // so the keyboard never ends a press with a key still logically held.
    for (final modifier in modifierDefs) {
      _dispatch(_downEvent(modifier, character: null));
    }
    _dispatch(_downEvent(keyDef, character: character));
    _dispatch(_upEvent(keyDef));
    for (final modifier in modifierDefs.reversed) {
      _dispatch(_upEvent(modifier));
    }

    WidgetsBinding.instance.scheduleFrame();
  }

  KeyEvent _downEvent(_KeyDef def, {required String? character}) =>
      KeyDownEvent(
        physicalKey: def.physical,
        logicalKey: def.logical,
        character: character,
        timeStamp: Duration(microseconds: _timeStampMicros++),
      );

  KeyEvent _upEvent(_KeyDef def) => KeyUpEvent(
        physicalKey: def.physical,
        logicalKey: def.logical,
        timeStamp: Duration(microseconds: _timeStampMicros++),
      );

  void _dispatch(KeyEvent event) {
    // Updates the pressed-key state and notifies HardwareKeyboard handlers.
    HardwareKeyboard.instance.handleKeyEvent(event);
    // FocusManager routes key events to Focus/Shortcuts via keyMessageHandler;
    // there is no non-deprecated injection path for this yet.
    // ignore: deprecated_member_use
    ServicesBinding.instance.keyEventManager.keyMessageHandler
        // ignore: deprecated_member_use
        ?.call(KeyMessage(<KeyEvent>[event], null));
  }

  _KeyDef? _resolveKey(String name) {
    final lower = name.toLowerCase();

    final named = _namedKeys[lower];
    if (named != null) {
      return named;
    }

    if (lower.length == 1) {
      final code = lower.codeUnitAt(0);
      // Logical key ids for letters and digits are their lower-case ASCII
      // code points (e.g. 'a' == 0x61, '0' == 0x30).
      if (code >= 0x61 && code <= 0x7a) {
        return (
          physical: _letterPhysicalKeys[lower]!,
          logical: LogicalKeyboardKey(code),
          character: lower,
        );
      }
      if (code >= 0x30 && code <= 0x39) {
        return (
          physical: _digitPhysicalKeys[lower]!,
          logical: LogicalKeyboardKey(code),
          character: lower,
        );
      }
    }

    return null;
  }

  /// All explicitly named keys this simulator understands (in addition to
  /// single characters `a`-`z` and `0`-`9`).
  static List<String> get supportedKeyNames =>
      _namedKeys.keys.toList(growable: false);
}

const Map<String, _KeyDef> _namedKeys = {
  'enter': (
    physical: PhysicalKeyboardKey.enter,
    logical: LogicalKeyboardKey.enter,
    character: null,
  ),
  'tab': (
    physical: PhysicalKeyboardKey.tab,
    logical: LogicalKeyboardKey.tab,
    character: null,
  ),
  'escape': (
    physical: PhysicalKeyboardKey.escape,
    logical: LogicalKeyboardKey.escape,
    character: null,
  ),
  'backspace': (
    physical: PhysicalKeyboardKey.backspace,
    logical: LogicalKeyboardKey.backspace,
    character: null,
  ),
  'delete': (
    physical: PhysicalKeyboardKey.delete,
    logical: LogicalKeyboardKey.delete,
    character: null,
  ),
  'space': (
    physical: PhysicalKeyboardKey.space,
    logical: LogicalKeyboardKey.space,
    character: ' ',
  ),
  'arrowup': (
    physical: PhysicalKeyboardKey.arrowUp,
    logical: LogicalKeyboardKey.arrowUp,
    character: null,
  ),
  'arrowdown': (
    physical: PhysicalKeyboardKey.arrowDown,
    logical: LogicalKeyboardKey.arrowDown,
    character: null,
  ),
  'arrowleft': (
    physical: PhysicalKeyboardKey.arrowLeft,
    logical: LogicalKeyboardKey.arrowLeft,
    character: null,
  ),
  'arrowright': (
    physical: PhysicalKeyboardKey.arrowRight,
    logical: LogicalKeyboardKey.arrowRight,
    character: null,
  ),
  'home': (
    physical: PhysicalKeyboardKey.home,
    logical: LogicalKeyboardKey.home,
    character: null,
  ),
  'end': (
    physical: PhysicalKeyboardKey.end,
    logical: LogicalKeyboardKey.end,
    character: null,
  ),
  'pageup': (
    physical: PhysicalKeyboardKey.pageUp,
    logical: LogicalKeyboardKey.pageUp,
    character: null,
  ),
  'pagedown': (
    physical: PhysicalKeyboardKey.pageDown,
    logical: LogicalKeyboardKey.pageDown,
    character: null,
  ),
};

/// Modifier name → the left-hand physical/logical key used to hold it.
/// `HardwareKeyboard.isControlPressed` (etc.) treats the left key as the
/// modifier being down, which is what `Shortcuts`/`SingleActivator` check.
const Map<String, _KeyDef> _modifierKeys = {
  'control': (
    physical: PhysicalKeyboardKey.controlLeft,
    logical: LogicalKeyboardKey.controlLeft,
    character: null,
  ),
  'shift': (
    physical: PhysicalKeyboardKey.shiftLeft,
    logical: LogicalKeyboardKey.shiftLeft,
    character: null,
  ),
  'alt': (
    physical: PhysicalKeyboardKey.altLeft,
    logical: LogicalKeyboardKey.altLeft,
    character: null,
  ),
  'meta': (
    physical: PhysicalKeyboardKey.metaLeft,
    logical: LogicalKeyboardKey.metaLeft,
    character: null,
  ),
};

const Map<String, PhysicalKeyboardKey> _letterPhysicalKeys = {
  'a': PhysicalKeyboardKey.keyA,
  'b': PhysicalKeyboardKey.keyB,
  'c': PhysicalKeyboardKey.keyC,
  'd': PhysicalKeyboardKey.keyD,
  'e': PhysicalKeyboardKey.keyE,
  'f': PhysicalKeyboardKey.keyF,
  'g': PhysicalKeyboardKey.keyG,
  'h': PhysicalKeyboardKey.keyH,
  'i': PhysicalKeyboardKey.keyI,
  'j': PhysicalKeyboardKey.keyJ,
  'k': PhysicalKeyboardKey.keyK,
  'l': PhysicalKeyboardKey.keyL,
  'm': PhysicalKeyboardKey.keyM,
  'n': PhysicalKeyboardKey.keyN,
  'o': PhysicalKeyboardKey.keyO,
  'p': PhysicalKeyboardKey.keyP,
  'q': PhysicalKeyboardKey.keyQ,
  'r': PhysicalKeyboardKey.keyR,
  's': PhysicalKeyboardKey.keyS,
  't': PhysicalKeyboardKey.keyT,
  'u': PhysicalKeyboardKey.keyU,
  'v': PhysicalKeyboardKey.keyV,
  'w': PhysicalKeyboardKey.keyW,
  'x': PhysicalKeyboardKey.keyX,
  'y': PhysicalKeyboardKey.keyY,
  'z': PhysicalKeyboardKey.keyZ,
};

const Map<String, PhysicalKeyboardKey> _digitPhysicalKeys = {
  '0': PhysicalKeyboardKey.digit0,
  '1': PhysicalKeyboardKey.digit1,
  '2': PhysicalKeyboardKey.digit2,
  '3': PhysicalKeyboardKey.digit3,
  '4': PhysicalKeyboardKey.digit4,
  '5': PhysicalKeyboardKey.digit5,
  '6': PhysicalKeyboardKey.digit6,
  '7': PhysicalKeyboardKey.digit7,
  '8': PhysicalKeyboardKey.digit8,
  '9': PhysicalKeyboardKey.digit9,
};
