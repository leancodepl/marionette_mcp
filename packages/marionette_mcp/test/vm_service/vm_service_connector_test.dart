import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

void main() {
  group('VmServiceConnector.callCustomExtension', () {
    late VmServiceConnector connector;

    setUp(() {
      connector = VmServiceConnector();
    });

    test('throws ArgumentError when extension name is empty', () {
      expect(
        () => connector.callCustomExtension(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'throws ArgumentError when extension name contains ext.flutter. prefix',
      () {
        expect(
          () => connector.callCustomExtension('ext.flutter.myExtension'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('must not include the "ext.flutter." prefix'),
            ),
          ),
        );
      },
    );

    test('throws NotConnectedException when not connected', () async {
      await expectLater(
        connector.callCustomExtension('myExtension'),
        throwsA(isA<NotConnectedException>()),
      );
    });

    test('accepts valid extension name with default empty args', () async {
      // Should throw NotConnectedException (not ArgumentError),
      // meaning validation passed.
      await expectLater(
        connector.callCustomExtension('deckNavigation.goToSlide'),
        throwsA(isA<NotConnectedException>()),
      );
    });

    test('accepts valid extension name with custom args', () async {
      await expectLater(
        connector.callCustomExtension('deckNavigation.goToSlide', {
          'slideNumber': '3',
        }),
        throwsA(isA<NotConnectedException>()),
      );
    });
  });

  group('VmServiceConnector.longPress', () {
    late VmServiceConnector connector;

    setUp(() {
      connector = VmServiceConnector();
    });

    test('throws NotConnectedException with default duration', () async {
      await expectLater(
        connector.longPress({'key': 'my_button'}),
        throwsA(isA<NotConnectedException>()),
      );
    });

    test('throws NotConnectedException with custom duration', () async {
      await expectLater(
        connector.longPress({'key': 'my_button'}, durationMs: 300),
        throwsA(isA<NotConnectedException>()),
      );
    });

    test('throws NotConnectedException with coordinate matcher', () async {
      await expectLater(
        connector.longPress({'x': 100, 'y': 200}),
        throwsA(isA<NotConnectedException>()),
      );
    });
  });

  group('VmServiceConnector.enterText', () {
    late VmServiceConnector connector;

    setUp(() {
      connector = VmServiceConnector();
    });

    test(
      'accepts focused matcher and falls through to connection validation',
      () async {
        await expectLater(
          connector.enterText({'focused': true}, 'Hello'),
          throwsA(isA<NotConnectedException>()),
        );
      },
    );
  });

  group('VmServiceConnector.pinchZoom', () {
    late VmServiceConnector connector;

    setUp(() {
      connector = VmServiceConnector();
    });

    test('throws NotConnectedException when not connected', () async {
      await expectLater(
        connector.pinchZoom({'key': 'map'}, scale: 2.0),
        throwsA(isA<NotConnectedException>()),
      );
    });

    test(
      'throws NotConnectedException with coordinates and custom distance',
      () async {
        await expectLater(
          connector.pinchZoom(
            {'x': 100, 'y': 200},
            scale: 0.5,
            startDistance: 300,
          ),
          throwsA(isA<NotConnectedException>()),
        );
      },
    );
  });
}
