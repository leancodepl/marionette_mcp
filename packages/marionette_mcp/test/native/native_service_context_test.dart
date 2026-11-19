import 'dart:async';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:test/test.dart';

import 'support/fake_native_connector.dart';

void main() {
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
      await context.requireConnector().tapAt(5, 6);
      expect(created.taps, [(x: 5, y: 6)]);
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

    group('overlapping connect', () {
      late List<Completer<NativeConnector>> pending;
      late NativeServiceContext context;

      setUp(() {
        pending = [];
        context = NativeServiceContext(
          connectorFactory: (platform, {serial, udid}) {
            final completer = Completer<NativeConnector>();
            pending.add(completer);
            return completer.future;
          },
        );
      });

      test('starts the next factory only after the stale connector is disposed',
          () async {
        final first = FakeNativeConnector()
          ..disposeCompleter = Completer<void>();
        final second = FakeNativeConnector();
        final firstCall = context.connect(NativePlatform.android);
        await pumpEventQueue();
        final secondCall = context.connect(NativePlatform.android);
        await pumpEventQueue();

        expect(pending, hasLength(1));
        pending.single.complete(first);
        await pumpEventQueue();
        expect(first.disposeCalls, 1);
        expect(pending, hasLength(1));

        first.disposeCompleter!.complete();
        await expectLater(
          firstCall,
          throwsA(isA<NativeOperationFailedException>()),
        );
        await pumpEventQueue();
        expect(pending, hasLength(2));

        pending[1].complete(second);
        await secondCall;
        expect(context.connector, same(second));
        expect(second.disposeCalls, 0);
      });

      test('never runs the factory of a connect replaced while it waited',
          () async {
        final first = FakeNativeConnector();
        final third = FakeNativeConnector();
        final firstCall = context.connect(NativePlatform.android);
        await pumpEventQueue();
        final secondCall = context.connect(NativePlatform.android);
        final thirdCall = context.connect(NativePlatform.android);
        await pumpEventQueue();

        pending.single.complete(first);
        await expectLater(
          firstCall,
          throwsA(isA<NativeOperationFailedException>()),
        );
        await expectLater(
          secondCall,
          throwsA(isA<NativeOperationFailedException>()),
        );
        await pumpEventQueue();
        expect(pending, hasLength(2));

        pending[1].complete(third);
        await thirdCall;
        expect(context.connector, same(third));
      });

      test('dispose while the factory is pending cancels the connect',
          () async {
        final created = FakeNativeConnector();
        final call = context.connect(NativePlatform.android);
        await pumpEventQueue();

        await context.dispose();
        pending.single.complete(created);

        await expectLater(
          call,
          throwsA(isA<NativeOperationFailedException>()),
        );
        expect(created.disposeCalls, 1);
        expect(context.connector, isNull);
      });
    });
  });
}
