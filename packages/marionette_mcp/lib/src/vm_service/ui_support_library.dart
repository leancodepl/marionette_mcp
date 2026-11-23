/// An extracted Flutter UI library that a Marionette integration package
/// adds rules for.
///
/// Mirrors the `marionette_flutter` `MarionetteUiLibrary` enum, which the CLI
/// and MCP server can't import; [wireName] is the name
/// `marionette.getConfiguration` reports in `uiLibraries`.
enum UiSupportLibrary {
  materialUi('material_ui', 'marionette_material', 'withMaterialUi'),
  cupertinoUi('cupertino_ui', 'marionette_cupertino', 'withCupertinoUi');

  const UiSupportLibrary(
    this.wireName,
    this.integrationPackage,
    this.integrationExtension,
  );

  /// The library's pub package name, used on the wire.
  final String wireName;

  /// The Marionette package that adds the library's rules.
  final String integrationPackage;

  /// The `MarionetteConfiguration` extension method of [integrationPackage].
  final String integrationExtension;

  /// The prefix of the URI of every library of this package.
  String get libraryUriPrefix => 'package:$wireName/';

  /// The library [uri] belongs to; null when it is none of these packages.
  static UiSupportLibrary? fromLibraryUri(String uri) => values
      .where((library) => uri.startsWith(library.libraryUriPrefix))
      .firstOrNull;

  /// Reads a list of unique [wireName]s, such as `uiLibraries` or
  /// `required_ui_libraries`.
  ///
  /// Throws a [FormatException] when [wireNames] is not a list, or holds a
  /// value that is not a [wireName] or that repeats.
  static Set<UiSupportLibrary> parseAll(Object? wireNames) {
    if (wireNames is! List<Object?>) {
      throw FormatException(
        'Expected a list of UI library names, got $wireNames',
      );
    }
    final libraries = <UiSupportLibrary>{};
    for (final wireName in wireNames) {
      final library =
          values.where((library) => library.wireName == wireName).firstOrNull;
      if (library == null) {
        throw FormatException(
          'Unsupported UI library: $wireName. Supported values: '
          '${values.map((library) => library.wireName).join(', ')}.',
        );
      }
      if (!libraries.add(library)) {
        throw FormatException('UI library $wireName is listed twice');
      }
    }
    return libraries;
  }
}
