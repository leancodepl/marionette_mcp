import 'dart:io';

import 'package:marionette_mcp/src/permissions/permission_accepter.dart';
import 'package:test/test.dart';

/// A fake `Process.run` recorder/replayer. Each call consumes a planned
/// response in order; unexpected calls raise a test failure.
class _FakeRunner {
  _FakeRunner();

  final List<List<String>> calls = [];
  final List<ProcessResult Function(String, List<String>)> _responses = [];

  void plan(ProcessResult Function(String executable, List<String> args) fn) {
    _responses.add(fn);
  }

  Future<ProcessResult> call(String executable, List<String> args) async {
    calls.add([executable, ...args]);
    if (_responses.isEmpty) {
      throw StateError(
        'Unexpected process call: $executable ${args.join(' ')}',
      );
    }
    return _responses.removeAt(0)(executable, args);
  }
}

void main() {
  group('findAcceptButton', () {
    test('matches Allow button and returns its bounds center', () {
      const xml = '''
<hierarchy>
  <node class="android.widget.FrameLayout" bounds="[0,0][1080,2400]">
    <node text="Allow this app to access your location?" bounds="[0,100][1080,300]"/>
    <node text="Deny" bounds="[100,2000][500,2100]"/>
    <node text="Allow" bounds="[600,2000][1000,2100]"/>
  </node>
</hierarchy>
''';
      final match = findAcceptButton(xml);
      expect(match, isNotNull);
      expect(match!.label, equals('Allow'));
      expect(match.x, equals(800)); // (600+1000)/2
      expect(match.y, equals(2050)); // (2000+2100)/2
    });

    test(
      'prefers "Allow only while using the app" over plain "Allow"',
      () {
        const xml = '''
<hierarchy>
  <node text="Allow" bounds="[0,0][100,100]"/>
  <node text="Allow only while using the app" bounds="[200,200][400,400]"/>
</hierarchy>
''';
        final match = findAcceptButton(xml);
        expect(match, isNotNull);
        expect(match!.label, equals('Allow only while using the app'));
        expect(match.x, equals(300));
        expect(match.y, equals(300));
      },
    );

    test('returns null when no accept-style button is present', () {
      const xml = '''
<hierarchy>
  <node text="Cancel" bounds="[0,0][100,100]"/>
  <node text="Deny" bounds="[200,200][400,400]"/>
</hierarchy>
''';
      expect(findAcceptButton(xml), isNull);
    });

    test('match is case-insensitive on the button text', () {
      const xml = '''
<hierarchy>
  <node text="ALLOW" bounds="[10,20][30,40]"/>
</hierarchy>
''';
      final match = findAcceptButton(xml);
      expect(match, isNotNull);
      expect(match!.x, equals(20));
      expect(match.y, equals(30));
    });

    test('ignores nodes without bounds', () {
      const xml = '''
<hierarchy>
  <node text="Allow"/>
</hierarchy>
''';
      expect(findAcceptButton(xml), isNull);
    });
  });

  group('PermissionAccepter.accept', () {
    test(
      'When no devices and no booted simulators, '
      'Then returns failure with actionable message',
      () async {
        final runner = _FakeRunner()
          // adb devices → header only
          ..plan(
            (_, __) => ProcessResult(0, 0, 'List of devices attached\n', ''),
          )
          // xcrun simctl list devices booted → empty
          ..plan(
            (_, __) => ProcessResult(0, 0, '== Devices ==\n', ''),
          );

        final accepter = PermissionAccepter(processRunner: runner.call);
        final result = await accepter.accept();

        expect(result.success, isFalse);
        expect(result.platform, isNull);
        expect(result.message, contains('No connected Android devices'));
      },
    );

    test(
      'When adb and xcrun are missing from PATH, '
      'Then surfaces the no-devices error rather than crashing',
      () async {
        final runner = _FakeRunner()
          ..plan(
            (executable, args) =>
                throw ProcessException(executable, args, 'not found', 2),
          )
          ..plan(
            (executable, args) =>
                throw ProcessException(executable, args, 'not found', 2),
          );

        final accepter = PermissionAccepter(processRunner: runner.call);
        final result = await accepter.accept();

        expect(result.success, isFalse);
        expect(result.message, contains('No connected Android devices'));
      },
    );

    test(
      'When one Android device and one booted simulator, '
      'Then returns failure with both listed',
      () async {
        final runner = _FakeRunner()
          ..plan(
            (_, __) => ProcessResult(
              0,
              0,
              'List of devices attached\nemulator-5554\tdevice\n',
              '',
            ),
          )
          ..plan(
            (_, __) => ProcessResult(
              0,
              0,
              '== Devices ==\n-- iOS 17.0 --\n'
                  '    iPhone 15 Pro (12345678-90AB-CDEF-1234-567890ABCDEF) '
                  '(Booted)\n',
              '',
            ),
          );

        final accepter = PermissionAccepter(processRunner: runner.call);
        final result = await accepter.accept();

        expect(result.success, isFalse);
        expect(result.message, contains('Multiple targets'));
        expect(result.message, contains('emulator-5554'));
        expect(
          result.message,
          contains('12345678-90AB-CDEF-1234-567890ABCDEF'),
        );
      },
    );

    test(
      'On Android with exactly one device, '
      'Then dumps UI, parses bounds, and taps the Allow button',
      () async {
        const dump = '''
<hierarchy>
  <node text="Allow notifications?" bounds="[0,100][1080,300]"/>
  <node text="Deny" bounds="[100,2000][500,2100]"/>
  <node text="Allow" bounds="[600,2000][1000,2100]"/>
</hierarchy>
''';

        final runner = _FakeRunner()
          // adb devices
          ..plan(
            (_, __) => ProcessResult(
              0,
              0,
              'List of devices attached\nemulator-5554\tdevice\n',
              '',
            ),
          )
          // xcrun simctl list booted → none
          ..plan((_, __) => ProcessResult(0, 0, '', ''))
          // adb -s emulator-5554 shell uiautomator dump ...
          ..plan((_, __) => ProcessResult(0, 0, 'UI hierchary dumped to: ...', ''))
          // adb -s emulator-5554 shell cat ...
          ..plan((_, __) => ProcessResult(0, 0, dump, ''))
          // adb -s emulator-5554 shell input tap 800 2050
          ..plan((_, __) => ProcessResult(0, 0, '', ''));

        final accepter = PermissionAccepter(processRunner: runner.call);
        final result = await accepter.accept();

        expect(result.success, isTrue);
        expect(result.platform, equals('android'));
        expect(result.buttonLabel, equals('Allow'));
        expect(result.message, contains('800'));
        expect(result.message, contains('2050'));
        expect(result.message, contains('emulator-5554'));

        expect(
          runner.calls,
          containsAllInOrder(<List<String>>[
            ['adb', 'devices'],
            ['xcrun', 'simctl', 'list', 'devices', 'booted'],
            [
              'adb',
              '-s',
              'emulator-5554',
              'shell',
              'uiautomator',
              'dump',
              '/sdcard/marionette_permission_dump.xml',
            ],
            [
              'adb',
              '-s',
              'emulator-5554',
              'shell',
              'cat',
              '/sdcard/marionette_permission_dump.xml',
            ],
            [
              'adb',
              '-s',
              'emulator-5554',
              'shell',
              'input',
              'tap',
              '800',
              '2050',
            ],
          ]),
        );
      },
    );

    test(
      'When Android UI dump contains no accept button, '
      'Then returns failure without tapping',
      () async {
        const dump = '''
<hierarchy>
  <node text="Cancel" bounds="[0,0][100,100]"/>
</hierarchy>
''';

        final runner = _FakeRunner()
          ..plan(
            (_, __) => ProcessResult(
              0,
              0,
              'List of devices attached\nemulator-5554\tdevice\n',
              '',
            ),
          )
          ..plan((_, __) => ProcessResult(0, 0, '', ''))
          ..plan((_, __) => ProcessResult(0, 0, '', ''))
          ..plan((_, __) => ProcessResult(0, 0, dump, ''));

        final accepter = PermissionAccepter(processRunner: runner.call);
        final result = await accepter.accept();

        expect(result.success, isFalse);
        expect(result.platform, equals('android'));
        expect(result.message, contains('No accept-permission button'));
        // No tap call should have been issued.
        expect(
          runner.calls.any((c) => c.contains('tap')),
          isFalse,
        );
      },
    );

    test(
      'On iOS Simulator with exactly one booted device, '
      'Then drives osascript and reports the clicked label',
      () async {
        const udid = '12345678-90AB-CDEF-1234-567890ABCDEF';

        final runner = _FakeRunner()
          ..plan((_, __) => ProcessResult(0, 0, '', '')) // adb devices: none
          ..plan(
            (_, __) => ProcessResult(
              0,
              0,
              '== Devices ==\n-- iOS 17.0 --\n'
                  '    iPhone 15 Pro ($udid) (Booted)\n',
              '',
            ),
          )
          // First osascript attempt ("Allow only while using the app") fails…
          ..plan((_, __) => ProcessResult(0, 1, '', 'button not found'))
          // …"While using the app" fails…
          ..plan((_, __) => ProcessResult(0, 1, '', 'button not found'))
          // …"Only this time" fails…
          ..plan((_, __) => ProcessResult(0, 1, '', 'button not found'))
          // …"Allow all the time" fails…
          ..plan((_, __) => ProcessResult(0, 1, '', 'button not found'))
          // …"Allow" fails (Android-style label not present in iOS dialog)…
          ..plan((_, __) => ProcessResult(0, 1, '', 'button not found'))
          // …"Allow While Using App" succeeds.
          ..plan((_, __) => ProcessResult(0, 0, '', ''));

        final accepter = PermissionAccepter(processRunner: runner.call);
        final result = await accepter.accept();

        expect(result.success, isTrue);
        expect(result.platform, equals('ios'));
        expect(result.buttonLabel, equals('Allow While Using App'));
        expect(result.message, contains(udid));

        // Every osascript call should target the Simulator process.
        for (final call in runner.calls.where((c) => c[0] == 'osascript')) {
          expect(call.last, contains('process "Simulator"'));
        }
      },
    );

    test(
      'On iOS Simulator with no matching button, '
      'Then returns a failure mentioning the Accessibility prerequisite',
      () async {
        final runner = _FakeRunner()
          ..plan((_, __) => ProcessResult(0, 0, '', '')) // adb devices: none
          ..plan(
            (_, __) => ProcessResult(
              0,
              0,
              '    iPhone (12345678-90AB-CDEF-1234-567890ABCDEF) (Booted)\n',
              '',
            ),
          );
        // Every osascript attempt fails.
        for (var i = 0; i < 9; i++) {
          runner.plan((_, __) => ProcessResult(0, 1, '', 'not found'));
        }

        final accepter = PermissionAccepter(processRunner: runner.call);
        final result = await accepter.accept();

        expect(result.success, isFalse);
        expect(result.platform, equals('ios'));
        expect(result.message, contains('Accessibility'));
      },
    );
  });
}
