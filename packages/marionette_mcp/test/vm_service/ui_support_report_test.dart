import 'package:marionette_mcp/src/vm_service/ui_support_library.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_report.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_state.dart';
import 'package:test/test.dart';

void main() {
  group('UiSupportReport.state', () {
    test('is missing for a required library the app does not configure', () {
      final report = UiSupportReport(
        configuredLibraries: {UiSupportLibrary.materialUi},
        observedLibraries: null,
        requiredLibraries: {
          UiSupportLibrary.materialUi,
          UiSupportLibrary.cupertinoUi,
        },
      );

      expect(report.state, UiSupportState.missing);
      expect(report.missingLibraries, {UiSupportLibrary.cupertinoUi});
    });

    test('is configured when Cupertino is loaded only through Material', () {
      final report = UiSupportReport(
        configuredLibraries: {UiSupportLibrary.materialUi},
        observedLibraries: {
          UiSupportLibrary.materialUi,
          UiSupportLibrary.cupertinoUi,
        },
        requiredLibraries: {UiSupportLibrary.materialUi},
      );

      expect(report.state, UiSupportState.configured);
      expect(report.missingLibraries, isEmpty);
    });

    test('is unknown without a confirmed scope, whatever is loaded', () {
      final report = UiSupportReport(
        configuredLibraries: {},
        observedLibraries: {UiSupportLibrary.cupertinoUi},
        requiredLibraries: null,
      );

      expect(report.state, UiSupportState.unknown);
      expect(report.missingLibraries, isNull);
    });

    test('is unknown when the binding does not declare its integrations', () {
      final report = UiSupportReport(
        configuredLibraries: null,
        observedLibraries: {},
        requiredLibraries: {UiSupportLibrary.cupertinoUi},
      );

      expect(report.state, UiSupportState.unknown);
      expect(report.missingLibraries, isNull);
    });
  });

  test('UiSupportReport cannot be changed through the sets it holds', () {
    final configured = {UiSupportLibrary.materialUi};
    final report = UiSupportReport(
      configuredLibraries: configured,
      observedLibraries: null,
      requiredLibraries: null,
    );

    configured.add(UiSupportLibrary.cupertinoUi);

    expect(report.configuredLibraries, {UiSupportLibrary.materialUi});
    expect(
      () => report.configuredLibraries!.add(UiSupportLibrary.cupertinoUi),
      throwsUnsupportedError,
    );
  });

  group('UiSupportLibrary.parseAll', () {
    test('reads the canonical names', () {
      expect(
        UiSupportLibrary.parseAll(['cupertino_ui', 'material_ui']),
        {UiSupportLibrary.cupertinoUi, UiSupportLibrary.materialUi},
      );
    });

    test('rejects an unknown, repeated or non-string name', () {
      expect(
        () => UiSupportLibrary.parseAll(['materialUi']),
        throwsFormatException,
      );
      expect(
        () => UiSupportLibrary.parseAll(['material_ui', 'material_ui']),
        throwsFormatException,
      );
      expect(() => UiSupportLibrary.parseAll([1]), throwsFormatException);
      expect(() => UiSupportLibrary.parseAll('material_ui'),
          throwsFormatException);
    });
  });
}
