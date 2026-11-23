import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_library.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_report.dart';
import 'package:test/test.dart';

void main() {
  group('buildMatcher', () {
    test('forwards key and identifier', () {
      expect(
        buildMatcher({'key': 'join_button', 'identifier': 'join'}),
        equals({'key': 'join_button', 'identifier': 'join'}),
      );
    });

    test('flattens coordinates', () {
      expect(
        buildMatcher({
          'coordinates': <String, dynamic>{'x': 10, 'y': 20},
        }),
        equals({'x': 10, 'y': 20}),
      );
    });

    test('encodes ancestor_keys as JSON for the string-only wire', () {
      expect(
        buildMatcher({
          'key': 'join_button',
          'ancestor_keys': ['session_2', 'grid.cell_3'],
        }),
        equals({
          'key': 'join_button',
          'ancestor_keys': '["session_2","grid.cell_3"]',
        }),
      );
    });

    test('omits ancestor_keys when it is absent', () {
      expect(
        buildMatcher({'key': 'join_button'}),
        equals({'key': 'join_button'}),
      );
    });

    test('omits an empty ancestor_keys array', () {
      expect(
        buildMatcher({'key': 'join_button', 'ancestor_keys': <String>[]}),
        equals({'key': 'join_button'}),
        reason: 'an empty chain means no scope, so nothing should go on the '
            'wire and behavior must match omitting the field',
      );
    });
  });

  group('hasSelector', () {
    test('empty matcher has no selector', () {
      expect(hasSelector(buildMatcher({})), isFalse);
    });

    test('a scope alone is not a selector', () {
      expect(
        hasSelector(buildMatcher({
          'ancestor_keys': ['grid.cell_2'],
        })),
        isFalse,
      );
    });

    test('a scoped key is a selector', () {
      expect(
        hasSelector(buildMatcher({
          'key': 'join_button',
          'ancestor_keys': ['grid.cell_2'],
        })),
        isTrue,
      );
    });
  });

  group('formatElement', () {
    test('keeps an element on one line, escaping every field', () {
      final line = formatElement({
        'type': 'Button\nType',
        'key': 'save\rbutton',
        'text': 'Accept terms\nRequired',
        'hint\nname': r'C:\temp',
        'bounds': {'label': 'a\nb'},
      });

      expect(
        line,
        r'Type: Button\nType, Key: "save\rbutton", '
        r'Text: "Accept terms\nRequired", hint\nname: "C:\\temp", '
        r'bounds: {"label":"a\nb"}',
      );
    });
  });

  group('coveredAppWarning', () {
    test('warns while the app is not in front', () {
      for (final state in ['inactive', 'paused', 'hidden']) {
        expect(
          coveredAppWarning(
            {'elements': [], 'appLifecycleState': state},
            nativeElements: 'native_get_elements',
          ),
          allOf(contains('lifecycle: $state'), contains('native_get_elements')),
        );
      }
    });

    test('points to no native tool when the native lane is off', () {
      expect(
        coveredAppWarning(
          {'appLifecycleState': 'paused'},
          nativeElements: null,
        ),
        allOf(contains('not in front'), endsWith('hidden and not reachable.')),
      );
    });

    test('names the given native command', () {
      expect(
        coveredAppWarning(
          {'appLifecycleState': 'paused'},
          nativeElements: 'marionette native-get-elements',
        ),
        contains('marionette native-get-elements'),
      );
    });

    test('says nothing when resumed or not reported (older binding)', () {
      expect(
        coveredAppWarning(
          {'appLifecycleState': 'resumed'},
          nativeElements: 'native_get_elements',
        ),
        isNull,
      );
      expect(
        coveredAppWarning(
          {'elements': []},
          nativeElements: 'native_get_elements',
        ),
        isNull,
      );
    });
  });

  group('describeUiSupport', () {
    test('gives the repair for each missing integration only', () {
      final text = describeUiSupport(
        UiSupportReport(
          configuredLibraries: {UiSupportLibrary.materialUi},
          observedLibraries: {},
          requiredLibraries: {
            UiSupportLibrary.materialUi,
            UiSupportLibrary.cupertinoUi,
          },
        ),
        scopeHint: 'pass required_ui_libraries',
      );

      expect(
        text,
        allOf(
          contains('missing cupertino_ui'),
          contains('flutter pub add marionette_cupertino'),
          contains('.withCupertinoUi()'),
          isNot(contains('marionette_material')),
        ),
      );
    });

    test('recommends no package for a library that is only loaded', () {
      final text = describeUiSupport(
        UiSupportReport(
          configuredLibraries: {UiSupportLibrary.materialUi},
          observedLibraries: {
            UiSupportLibrary.materialUi,
            UiSupportLibrary.cupertinoUi,
          },
          requiredLibraries: null,
        ),
        scopeHint: 'pass required_ui_libraries',
      );

      expect(
        text,
        allOf(
          contains('pass required_ui_libraries'),
          isNot(contains('marionette_cupertino')),
        ),
      );
    });
  });

  group('uiSupportWarning', () {
    test('says nothing when the confirmed scope is configured', () {
      expect(
        uiSupportWarning(
          UiSupportReport(
            configuredLibraries: {UiSupportLibrary.materialUi},
            observedLibraries: {
              UiSupportLibrary.materialUi,
              UiSupportLibrary.cupertinoUi,
            },
            requiredLibraries: {UiSupportLibrary.materialUi},
          ),
          scopeHint: 'pass required_ui_libraries',
        ),
        isNull,
      );
    });

    test('does not warn without a scope about Cupertino loaded by Material',
        () {
      expect(
        uiSupportWarning(
          UiSupportReport(
            configuredLibraries: {UiSupportLibrary.materialUi},
            observedLibraries: {
              UiSupportLibrary.materialUi,
              UiSupportLibrary.cupertinoUi,
            },
            requiredLibraries: null,
          ),
          scopeHint: 'pass required_ui_libraries',
        ),
        isNull,
      );
      expect(
        uiSupportWarning(
          UiSupportReport(
            configuredLibraries: {},
            observedLibraries: {UiSupportLibrary.cupertinoUi},
            requiredLibraries: null,
          ),
          scopeHint: 'pass required_ui_libraries',
        ),
        startsWith('Warning: '),
      );
    });

    test('warns about an older binding only when a UI library is loaded', () {
      expect(
        uiSupportWarning(
          UiSupportReport(
            configuredLibraries: null,
            observedLibraries: null,
            requiredLibraries: null,
          ),
          scopeHint: 'pass required_ui_libraries',
        ),
        isNull,
      );
      expect(
        uiSupportWarning(
          UiSupportReport(
            configuredLibraries: null,
            observedLibraries: {UiSupportLibrary.materialUi},
            requiredLibraries: null,
          ),
          scopeHint: 'pass required_ui_libraries',
        ),
        startsWith('Warning: '),
      );
    });

    test('warns about an older binding when a scope is confirmed', () {
      expect(
        uiSupportWarning(
          UiSupportReport(
            configuredLibraries: null,
            observedLibraries: null,
            requiredLibraries: {UiSupportLibrary.materialUi},
          ),
          scopeHint: 'pass required_ui_libraries',
        ),
        startsWith('Warning: '),
      );
      expect(
        uiSupportWarning(
          UiSupportReport(
            configuredLibraries: null,
            observedLibraries: null,
            requiredLibraries: {},
          ),
          scopeHint: 'pass required_ui_libraries',
        ),
        isNull,
      );
    });
  });
}
