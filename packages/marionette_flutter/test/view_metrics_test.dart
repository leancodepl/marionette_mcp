import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/binding/extensions/info_extensions.dart';

void main() {
  testWidgets('viewMetricsOf reports physical and logical size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1320, 2868)
      ..devicePixelRatio = 3
      ..padding = const FakeViewPadding(top: 186, bottom: 102);
    addTearDown(tester.view.reset);

    expect(viewMetricsOf(tester.view), {
      'devicePixelRatio': 3.0,
      'physicalWidth': 1320.0,
      'physicalHeight': 2868.0,
      'logicalWidth': 440.0,
      'logicalHeight': 956.0,
      'padding': {'top': 186.0, 'right': 0.0, 'bottom': 102.0, 'left': 0.0},
    });
  });
}
