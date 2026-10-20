// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/client.dart';

import 'package:marionette_website/components/copy_button.dart'
    deferred as _copy_button;
import 'package:marionette_website/components/docs_toc.dart'
    deferred as _docs_toc;
import 'package:marionette_website/components/loop_player.dart'
    deferred as _loop_player;

/// Default [ClientOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.client.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultClientOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ClientOptions get defaultClientOptions => ClientOptions(
  clients: {
    'copy_button': ClientLoader(
      (p) => _copy_button.CopyButton(
        text: p['text'] as String,
        label: p['label'] as String?,
      ),
      loader: _copy_button.loadLibrary,
    ),
    'docs_toc': ClientLoader(
      (p) => _docs_toc.DocsToc(
        path: p['path'] as String,
        ids: (p['ids'] as List<Object?>).cast<String>(),
        labels: (p['labels'] as List<Object?>).cast<String>(),
      ),
      loader: _docs_toc.loadLibrary,
    ),
    'loop_player': ClientLoader(
      (p) => _loop_player.LoopPlayer(
        targetId: p['targetId'] as String,
        beats: p['beats'] as int,
      ),
      loader: _loop_player.loadLibrary,
    ),
  },
);
