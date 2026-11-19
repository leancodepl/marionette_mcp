import 'dart:io';

import 'package:marionette_mcp/src/native_service/bootstrap_helpers.dart';
import 'package:test/test.dart';

void main() {
  group('nativeCacheDir', () {
    test('uses XDG_CACHE_HOME when it is set', () {
      expect(
        nativeCacheDir(
          'wda',
          environment: {'XDG_CACHE_HOME': '/xdg', 'HOME': '/home/me'},
        ).path,
        '/xdg/marionette_mcp/wda',
      );
    });

    test('falls back to .cache under HOME when XDG_CACHE_HOME is empty', () {
      expect(
        nativeCacheDir(
          'wda',
          environment: {'XDG_CACHE_HOME': '', 'HOME': '/home/me'},
        ).path,
        '/home/me/.cache/marionette_mcp/wda',
      );
    });

    test('falls back to the system temp directory without a home', () {
      expect(
        nativeCacheDir('wda', environment: {'HOME': ''}).path,
        '${Directory.systemTemp.path}/marionette_mcp/wda',
      );
    });
  });
}
