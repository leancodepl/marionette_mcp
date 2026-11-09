/// System and hardware keys `native_press_key` can press.
///
/// Names that also exist in the Flutter lane's `press_key` (`enter`, `tab`,
/// `backspace`) mean the same thing. Platform mapping lives in the
/// connectors; a key a platform does not have raises
/// `NativeUnsupportedException`.
enum NativeKey {
  back('back', 'Android Back (navigates back or closes the keyboard).'),
  home('home', 'Home: sends the app to the background.'),
  enter('enter', 'Enter / Return on the software keyboard.'),
  backspace('backspace', 'Deletes the character before the cursor.'),
  tab('tab', 'Tab: moves focus to the next field (Android only).'),
  recents('recents', 'Android recent-apps overview.'),
  volumeUp('volume_up', 'Hardware volume up.'),
  volumeDown('volume_down', 'Hardware volume down.');

  const NativeKey(this.wireName, this.summary);

  /// Tool argument value.
  final String wireName;

  /// One-line description for the tool schema.
  final String summary;

  /// Parses a tool argument (case-insensitive), or returns null.
  static NativeKey? tryParse(String? raw) {
    final normalized = raw?.toLowerCase().trim();
    for (final key in values) {
      if (key.wireName == normalized) return key;
    }
    return null;
  }
}
