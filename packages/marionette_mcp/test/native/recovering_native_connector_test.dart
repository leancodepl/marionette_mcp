import 'dart:async';

import 'package:logging/logging.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/recovering_native_connector.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:test/test.dart';

import 'support/fake_native_connector.dart';

const _connectionLost = WebDriverException(
  'POST /actions failed: Connection reset by peer',
  error: webDriverConnectionLost,
);
const _unreachable = WebDriverException(
  'POST /actions failed: Connection refused',
  error: webDriverServerUnreachable,
);
const _invalidSession = WebDriverException(
  'session deleted',
  error: webDriverInvalidSessionId,
  httpStatus: 404,
);

void main() {
  group('RecoveringNativeConnector (D3)', () {
    late List<FakeNativeConnector> replacements;
    late int reconnects;
    late int closedCalls;

    setUp(() {
      replacements = [];
      reconnects = 0;
      closedCalls = 0;
    });

    RecoveringNativeConnector wrap(FakeNativeConnector initial) =>
        RecoveringNativeConnector(
          initial,
          reconnect: () async {
            reconnects++;
            return replacements.removeAt(0);
          },
          logger: Logger('test'),
          onClosed: () => closedCalls++,
        );

    test('passes operations through while the session is healthy', () async {
      final inner = FakeNativeConnector.single([nativeElement(text: 'OK')]);
      final connector = wrap(inner);

      await connector.tapAt(1, 2);
      final elements = await connector.getNativeElements();

      expect(inner.taps, [(x: 1, y: 2)]);
      expect(elements.single.text, 'OK');
      expect(reconnects, 0);
    });

    for (final (name, error) in [
      ('connection lost', _connectionLost),
      ('server unreachable', _unreachable),
      ('invalid session id', _invalidSession),
    ]) {
      test('a read is retried on a fresh session after $name', () async {
        final first = FakeNativeConnector()..errorsOnce.add(error);
        replacements.add(FakeNativeConnector(screenshot: 'fresh'));
        final connector = wrap(first);

        expect(await connector.takeScreenshot(), 'fresh');
        expect(reconnects, 1);
        expect(first.disposeCalls, 1);
      });
    }

    for (final (name, error) in [
      ('invalid session id', _invalidSession),
      ('server unreachable', _unreachable),
    ]) {
      test('an action is retried after $name (it certainly did not run)',
          () async {
        final first = FakeNativeConnector()..errorsOnce.add(error);
        final second = FakeNativeConnector();
        replacements.add(second);
        final connector = wrap(first);

        await connector.tapAt(3, 4);

        expect(first.taps, isEmpty);
        expect(second.taps, [(x: 3, y: 4)]);
      });
    }

    test('an action replaces a server that is already gone before acting',
        () async {
      final first = FakeNativeConnector()..serverResponding = false;
      final second = FakeNativeConnector();
      replacements.add(second);
      final connector = wrap(first);

      await connector.tapAt(7, 8);

      expect(first.taps, isEmpty);
      expect(first.disposeCalls, 1);
      expect(second.taps, [(x: 7, y: 8)]);
      expect(reconnects, 1);
    });

    test('an action on a responding server checks health once', () async {
      final inner = FakeNativeConnector();
      final connector = wrap(inner);

      await connector.enterText(nativeElement(id: 'field'), 'x');

      expect(inner.healthChecks, 1);
      expect(reconnects, 0);
    });

    test('reads do not probe the server first', () async {
      final inner = FakeNativeConnector();
      final connector = wrap(inner);

      await connector.getNativeElements();
      await connector.takeScreenshot();
      await connector.foregroundApp;

      expect(inner.healthChecks, 0);
    });

    test('an action interrupted by connection loss is not repeated', () async {
      final first = FakeNativeConnector()..errorsOnce.add(_connectionLost);
      final second = FakeNativeConnector();
      replacements.add(second);
      final connector = wrap(first);

      await expectLater(
        connector.swipe(startX: 0, startY: 0, endX: 0, endY: 9),
        throwsA(
          isA<NativeSessionLostException>()
              .having((e) => e.message, 'message', contains('may or may not'))
              .having((e) => e.hint, 'hint', contains('native_get_elements')),
        ),
      );
      expect(reconnects, 0, reason: 'reconnect is deferred to the next call');
      expect(second.swipes, isEmpty);

      await connector.getNativeElements();
      expect(reconnects, 1);
      expect(first.disposeCalls, 1);
    });

    test('a second loss right after reconnecting closes the connector',
        () async {
      final first = FakeNativeConnector()..errorsOnce.add(_connectionLost);
      final second = FakeNativeConnector()..error = _connectionLost;
      replacements.add(second);
      final connector = wrap(first);

      await expectLater(
        connector.getNativeElements(),
        throwsA(
          isA<NativeSessionLostException>()
              .having((e) => e.hint, 'hint', contains('native_connect')),
        ),
      );
      expect(second.disposeCalls, 1);
      expect(closedCalls, 1);
      await expectLater(
        connector.getNativeElements(),
        throwsA(isA<NativeNotConnectedException>()),
      );
    });

    test('a failed reconnect reports the cause and closes the connector',
        () async {
      final connector = RecoveringNativeConnector(
        FakeNativeConnector()..errorsOnce.add(_connectionLost),
        reconnect: () => Future.error(StateError('emulator is gone')),
        logger: Logger('test'),
        onClosed: () => closedCalls++,
      );

      await expectLater(
        connector.getNativeElements(),
        throwsA(
          isA<NativeSessionLostException>()
              .having((e) => e.message, 'message', contains('emulator is gone'))
              .having((e) => e.hint, 'hint', contains('native_connect')),
        ),
      );
      expect(closedCalls, 1);
    });

    test('other WebDriver errors are passed through untouched', () async {
      final connector = wrap(
        FakeNativeConnector()
          ..errorsOnce.add(
            const WebDriverException('nope', error: 'no such element'),
          ),
      );

      await expectLater(
        connector.getNativeElements(),
        throwsA(
          isA<WebDriverException>()
              .having((e) => e.error, 'error', 'no such element'),
        ),
      );
      expect(reconnects, 0);
    });

    test('concurrent reads that both hit the loss reconnect only once',
        () async {
      final first = FakeNativeConnector()
        ..errorsOnce.addAll([_connectionLost, _connectionLost]);
      replacements.add(
        FakeNativeConnector.single([nativeElement(text: 'OK')]),
      );
      final connector = wrap(first);

      final results = await Future.wait([
        connector.getNativeElements(),
        connector.getNativeElements(),
      ]);

      expect(results.map((r) => r.single.text), ['OK', 'OK']);
      expect(reconnects, 1);
    });

    test('dispose disposes the current connector', () async {
      final inner = FakeNativeConnector();
      final connector = wrap(inner);

      await connector.dispose();

      expect(inner.disposeCalls, 1);
      await expectLater(
        connector.tapAt(0, 0),
        throwsA(isA<NativeNotConnectedException>()),
      );
    });
  });
}
