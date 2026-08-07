/// Native lane platforms accepted by [native_connect].
enum SupportedPlatform {
  android('android'),
  ios('ios'),
  web('web');

  const SupportedPlatform(this.wireName);

  /// MCP tool argument value (e.g. `"android"`).
  final String wireName;

  static String get commaSeparatedWireNames =>
      values.map((platform) => platform.wireName).join(', ');

  static String get quotedWireNames {
    final quoted =
        values.map((platform) => '"${platform.wireName}"').toList();
    if (quoted.length <= 1) return quoted.join();
    return '${quoted.sublist(0, quoted.length - 1).join(', ')}, or ${quoted.last}';
  }

  static SupportedPlatform? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.toLowerCase().trim();
    for (final platform in values) {
      if (platform.wireName == normalized) return platform;
    }
    return null;
  }
}
