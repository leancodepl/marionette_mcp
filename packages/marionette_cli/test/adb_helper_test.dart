import 'dart:io';

import 'package:marionette_cli/src/cli/adb_helper.dart';
import 'package:test/test.dart';

void main() {
  group('AdbHelper', () {
    group('isAvailable()', () {
      test('When adb version exits with code 0, Then returns true', () async {
        final helper = AdbHelper(
          processRunner: (executable, arguments) async {
            return ProcessResult(
              0,
              0,
              'Android Debug Bridge version 1.0.41',
              '',
            );
          },
        );
        expect(await helper.isAvailable(), isTrue);
      });

      test(
        'When adb throws ProcessException (not found), Then returns false',
        () async {
          final helper = AdbHelper(
            processRunner: (executable, arguments) async {
              throw ProcessException(
                'adb',
                arguments,
                'No such file or directory',
                2,
              );
            },
          );
          expect(await helper.isAvailable(), isFalse);
        },
      );

      test(
        'When checking isAvailable, Then calls adb with [version]',
        () async {
          String? capturedExecutable;
          List<String>? capturedArguments;
          final helper = AdbHelper(
            processRunner: (executable, arguments) async {
              capturedExecutable = executable;
              capturedArguments = arguments;
              return ProcessResult(0, 0, '', '');
            },
          );
          await helper.isAvailable();
          expect(capturedExecutable, equals('adb'));
          expect(capturedArguments, equals(['version']));
        },
      );
    });

    group('setupReverse()', () {
      test(
        'When adb reverse exits with code 0, Then returns success',
        () async {
          final helper = AdbHelper(
            processRunner: (executable, arguments) async {
              return ProcessResult(0, 0, '', '');
            },
          );
          final result = await helper.setupReverse(8080);
          expect(result.success, isTrue);
        },
      );

      test(
        'When adb reverse exits with code 1 and stderr, Then returns failure with stderr message',
        () async {
          final helper = AdbHelper(
            processRunner: (executable, arguments) async {
              return ProcessResult(0, 1, '', 'error: device not found');
            },
          );
          final result = await helper.setupReverse(8080);
          expect(result.success, isFalse);
          expect(result.stderr, equals('error: device not found'));
        },
      );

      test(
        'When setupReverse is called with port 8080, Then calls adb with [reverse, tcp:8080, tcp:8080]',
        () async {
          String? capturedExecutable;
          List<String>? capturedArguments;
          final helper = AdbHelper(
            processRunner: (executable, arguments) async {
              capturedExecutable = executable;
              capturedArguments = arguments;
              return ProcessResult(0, 0, '', '');
            },
          );
          await helper.setupReverse(8080);
          expect(capturedExecutable, equals('adb'));
          expect(
            capturedArguments,
            equals(['reverse', 'tcp:8080', 'tcp:8080']),
          );
        },
      );
    });

    group('removeReverse()', () {
      test(
        'When adb reverse --remove exits with code 0, Then returns success',
        () async {
          final helper = AdbHelper(
            processRunner: (executable, arguments) async {
              return ProcessResult(0, 0, '', '');
            },
          );
          final result = await helper.removeReverse(8080);
          expect(result.success, isTrue);
        },
      );

      test(
        'When adb reverse --remove exits with code 1, Then returns failure (does not throw)',
        () async {
          final helper = AdbHelper(
            processRunner: (executable, arguments) async {
              return ProcessResult(0, 1, '', 'error: failed to remove reverse');
            },
          );
          final result = await helper.removeReverse(8080);
          expect(result.success, isFalse);
        },
      );

      test(
        'When removeReverse is called with port 8080, Then calls adb with [reverse, --remove, tcp:8080]',
        () async {
          String? capturedExecutable;
          List<String>? capturedArguments;
          final helper = AdbHelper(
            processRunner: (executable, arguments) async {
              capturedExecutable = executable;
              capturedArguments = arguments;
              return ProcessResult(0, 0, '', '');
            },
          );
          await helper.removeReverse(8080);
          expect(capturedExecutable, equals('adb'));
          expect(
            capturedArguments,
            equals(['reverse', '--remove', 'tcp:8080']),
          );
        },
      );
    });
  });
}
