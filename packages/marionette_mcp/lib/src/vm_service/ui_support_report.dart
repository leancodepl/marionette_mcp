import 'package:marionette_mcp/src/vm_service/ui_support_library.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_state.dart';

/// What the connected app declares, loads and needs of the extracted UI
/// libraries, from `VmServiceConnector.inspectUiSupport`.
///
/// A null set means the evidence is unavailable, never that it is empty.
final class UiSupportReport {
  UiSupportReport({
    required Set<UiSupportLibrary>? configuredLibraries,
    required Set<UiSupportLibrary>? observedLibraries,
    required Set<UiSupportLibrary>? requiredLibraries,
    this.diagnostic,
  })  : configuredLibraries = _unmodifiable(configuredLibraries),
        observedLibraries = _unmodifiable(observedLibraries),
        requiredLibraries = _unmodifiable(requiredLibraries);

  /// The libraries whose integrations the app's `MarionetteConfiguration`
  /// declares; null when the binding predates the declaration.
  final Set<UiSupportLibrary>? configuredLibraries;

  /// The libraries loaded in the app's isolate; null when the VM service
  /// gives no library metadata. A loaded library can come from a dependency,
  /// so it never makes the library required.
  final Set<UiSupportLibrary>? observedLibraries;

  /// The libraries the app's source uses, as confirmed by a source preflight;
  /// null when no one confirmed the scope.
  final Set<UiSupportLibrary>? requiredLibraries;

  /// Why some evidence is unavailable; null when all of it was read.
  final String? diagnostic;

  /// The required libraries without a configured integration; null when the
  /// scope or the configuration is unknown.
  Set<UiSupportLibrary>? get missingLibraries {
    final required = requiredLibraries;
    final configured = configuredLibraries;
    if (required == null || configured == null) return null;
    return required.difference(configured);
  }

  UiSupportState get state => switch (missingLibraries) {
        null => UiSupportState.unknown,
        final missing when missing.isEmpty => UiSupportState.configured,
        _ => UiSupportState.missing,
      };

  static Set<UiSupportLibrary>? _unmodifiable(
    Set<UiSupportLibrary>? libraries,
  ) =>
      libraries == null ? null : Set.unmodifiable(libraries);
}
