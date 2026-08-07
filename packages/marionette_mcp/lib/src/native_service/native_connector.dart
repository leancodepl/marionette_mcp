/// Barrel export for the native automation lane.
///
/// Import this library for [NativeConnector], [NativeElement], and all
/// platform UI parsers. Core types live in [native_models.dart]; parsers
/// live under `parsing/`.
library;

export 'native_models.dart';
export 'parsing/android_ui_parser.dart';
export 'parsing/ios_ui_parser.dart';
export 'parsing/ui_tree_parser.dart';
export 'parsing/web_ui_parser.dart';
