import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:test/test.dart';

import 'support/fake_native_connector.dart';

void main() {
  group('NativePlatform.tryParse', () {
    test('accepts known platforms case-insensitively', () {
      expect(NativePlatform.tryParse(' Android '), NativePlatform.android);
      expect(NativePlatform.tryParse('IOS'), NativePlatform.ios);
    });

    test('rejects anything else', () {
      expect(NativePlatform.tryParse('web'), isNull);
      expect(NativePlatform.tryParse(null), isNull);
    });
  });

  group('NativeServiceContext', () {
    test('requireConnector throws when disconnected', () {
      final context = NativeServiceContext();
      expect(
        context.requireConnector,
        throwsA(isA<NativeNotConnectedException>()),
      );
    });

    test('dispose tears down the active connector', () async {
      final context = NativeServiceContext();
      final connector = FakeNativeConnector();
      context.connector = connector;

      expect(context.requireConnector(), same(connector));

      await context.dispose();
      expect(context.connector, isNull);
      expect(connector.disposeCalls, 1);
      expect(
        context.requireConnector,
        throwsA(isA<NativeNotConnectedException>()),
      );
    });

    test('connect passes arguments to the factory and stores the connector',
        () async {
      final created = FakeNativeConnector();
      final calls = <(NativePlatform, String?, String?)>[];
      final context = NativeServiceContext(
        connectorFactory: (platform, {serial, udid}) async {
          calls.add((platform, serial, udid));
          return created;
        },
      );

      await context.connect(NativePlatform.android, serial: 'emulator-5554');

      expect(calls, [(NativePlatform.android, 'emulator-5554', null)]);
      expect(context.requireConnector(), same(created));
    });

    test('connect disposes the previous session first', () async {
      final previous = FakeNativeConnector();
      final context = NativeServiceContext(
        connectorFactory: (platform, {serial, udid}) async {
          expect(previous.disposeCalls, 1);
          return FakeNativeConnector();
        },
      )..connector = previous;

      await context.connect(NativePlatform.ios);

      expect(context.connector, isNot(same(previous)));
    });

    test('a failed connect leaves the context disconnected', () async {
      final previous = FakeNativeConnector();
      final context = NativeServiceContext(
        connectorFactory: (platform, {serial, udid}) =>
            Future<NativeConnector>.error(StateError('boom')),
      )..connector = previous;

      await expectLater(
        context.connect(NativePlatform.android),
        throwsA(isA<StateError>()),
      );
      expect(context.connector, isNull);
      expect(previous.disposeCalls, 1);
    });
  });
}
