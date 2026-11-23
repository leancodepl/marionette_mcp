import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('composes optional support without changing app provenance',
      (tester) async {
    await tester.pumpWidget(const _Probe());
    final element = tester.element(find.byType(_Probe));
    final configuration = MarionetteConfiguration(
      shouldStopTraversalAtElement: (_) => false,
      controlKind: (_) => MarionetteControlKind.textField,
      extractFieldLabel: (_) => 'app label',
    ).withAdditionalWidgetSupport(
      library: MarionetteUiLibrary.materialUi,
      isInteractiveElement: (_) => true,
      shouldStopTraversalAtElement: (_) => true,
      extractText: (_) => 'integration text',
      controlKind: (_) => MarionetteControlKind.toggle,
      extractFieldLabel: (_) => 'integration label',
    );

    expect(configuration.uiLibraries, {MarionetteUiLibrary.materialUi});
    expect(configuration.isElementInteractive(element), isTrue);
    expect(configuration.shouldStopAtElement(element), isTrue);
    expect(configuration.shouldAppStopAtElement(element), isFalse,
        reason: 'integration stop must not become app provenance');
    expect(
        configuration.controlKindFor(element), MarionetteControlKind.textField,
        reason: 'app scalar callbacks have precedence');
    expect(configuration.fieldLabelFor(element), 'app label');
    expect(configuration.extractTextFromWidget(element), 'integration text');
  });

  testWidgets('repeating a library is idempotent and preserves settings',
      (tester) async {
    await tester.pumpWidget(const _Probe());
    final element = tester.element(find.byType(_Probe));
    final configuration = const MarionetteConfiguration(
      compaction: CompactionMode.none,
      enableSessionReports: true,
    ).withAdditionalWidgetSupport(
      library: MarionetteUiLibrary.cupertinoUi,
      isInteractiveElement: (_) => true,
      shouldStopTraversalAtElement: (_) => false,
      extractText: (_) => null,
      controlKind: (_) => null,
      extractFieldLabel: (_) => null,
    );
    final repeated = configuration.withAdditionalWidgetSupport(
      library: MarionetteUiLibrary.cupertinoUi,
      isInteractiveElement: (_) => false,
      shouldStopTraversalAtElement: (_) => true,
      extractText: (_) => 'wrong',
      controlKind: (_) => MarionetteControlKind.radio,
      extractFieldLabel: (_) => 'wrong',
    );

    expect(identical(repeated, configuration), isTrue);
    expect(repeated.uiLibraries, {MarionetteUiLibrary.cupertinoUi});
    expect(repeated.compaction, CompactionMode.none);
    expect(repeated.enableSessionReports, isTrue);
    expect(repeated.isElementInteractive(element), isTrue);
  });
}
