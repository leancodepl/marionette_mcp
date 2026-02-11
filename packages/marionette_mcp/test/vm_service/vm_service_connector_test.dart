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

    test('throws NotConnectedException when not connected', () {
      expect(
        () => connector.callCustomExtension('myExtension'),
        throwsA(isA<NotConnectedException>()),
      );
    });

    test('accepts valid extension name with default empty args', () {
      // Should throw NotConnectedException (not ArgumentError),
      // meaning validation passed.
      expect(
        () => connector.callCustomExtension('deckNavigation.goToSlide'),
        throwsA(isA<NotConnectedException>()),
      );
    });

    test('accepts valid extension name with custom args', () {
      expect(
        () => connector.callCustomExtension('deckNavigation.goToSlide', {
          'slideNumber': '3',
        }),
        throwsA(isA<NotConnectedException>()),
      );
    });
  });
}
