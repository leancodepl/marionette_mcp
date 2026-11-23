import 'dart:async';

import 'package:marionette_mcp/src/vm_service/ui_support_library.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_state.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import 'fake_vm_service.dart';

void main() {
  late FakeVmService app;
  late VmServiceConnector connector;

  setUp(() async {
    app = await FakeVmService.start();
    connector = VmServiceConnector();
  });

  tearDown(() async {
    await connector.disconnect();
    await app.close();
  });

  group('inspectUiSupport', () {
    test('reads the declared integrations and the loaded UI packages',
        () async {
      app
        ..configuration = {
          'uiLibraries': ['material_ui'],
        }
        ..libraryUris = [
          'package:material_ui/material.dart',
          'package:cupertino_ui/cupertino.dart',
          'package:flutter/widgets.dart',
        ];
      await connector.connect(app.uri);

      final report = await connector.inspectUiSupport(
        requiredLibraries: {UiSupportLibrary.materialUi},
      );

      expect(report.configuredLibraries, {UiSupportLibrary.materialUi});
      expect(
        report.observedLibraries,
        {UiSupportLibrary.materialUi, UiSupportLibrary.cupertinoUi},
      );
      expect(report.state, UiSupportState.configured);
      expect(report.diagnostic, isNull);
    });

    test('reports the declarations of an older binding as unknown', () async {
      app.configuration = {'enableSessionReports': false};
      await connector.connect(app.uri);

      final report = await connector.inspectUiSupport(
        requiredLibraries: {UiSupportLibrary.materialUi},
      );

      expect(report.configuredLibraries, isNull);
      expect(report.state, UiSupportState.unknown);
      expect(report.diagnostic, contains('binding'));
    });

    test('does not call getConfiguration on a binding without it', () async {
      app.extensionRPCs = ['ext.flutter.marionette.getLogs'];
      await connector.connect(app.uri);

      final report = await connector.inspectUiSupport();

      expect(report.configuredLibraries, isNull);
      expect(
        app.receivedMethods,
        isNot(contains('ext.flutter.marionette.getConfiguration')),
      );
    });

    test('confirms a missing integration without library metadata', () async {
      app.libraryUris = [];
      await connector.connect(app.uri);

      final report = await connector.inspectUiSupport(
        requiredLibraries: {UiSupportLibrary.cupertinoUi},
      );

      expect(report.observedLibraries, isNull);
      expect(report.state, UiSupportState.missing);
      expect(report.diagnostic, contains('library metadata'));
    });

    test('fails on a VM service error instead of reporting unknown', () async {
      await connector.connect(app.uri);
      app.getIsolateError = 'isolate is gone';

      await expectLater(
        connector.inspectUiSupport(),
        throwsA(isA<RPCError>()),
      );
    });

    test('fails on a malformed declaration', () async {
      app.configuration = {'uiLibraries': 'material_ui'};
      await connector.connect(app.uri);

      await expectLater(connector.inspectUiSupport(), throwsFormatException);
    });
  });

  group('inspectUiSupport lifecycle', () {
    int countOf(String method) =>
        app.receivedMethods.where((received) => received == method).length;

    test('reads the app once per isolate, sharing the configuration', () async {
      await connector.connect(app.uri);
      final isolateReadsAtConnect = countOf('getIsolate');

      await connector.getSessionReportsEnabled();
      await connector.inspectUiSupport();
      await connector.inspectUiSupport();

      expect(countOf('ext.flutter.marionette.getConfiguration'), 1);
      expect(countOf('getIsolate'), isolateReadsAtConnect + 1);

      await connector.inspectUiSupport(refresh: true);

      expect(countOf('getIsolate'), isolateReadsAtConnect + 2);
    });

    test('reads the fresh isolate after a hot restart', () async {
      await connector.connect(app.uri);
      expect((await connector.inspectUiSupport()).configuredLibraries, isEmpty);
      app
        ..isolateId = 'isolates/2'
        ..configuration = {
          'uiLibraries': ['cupertino_ui'],
        }
        ..registerService('hotRestart', 's0.hotRestart');

      expect(await connector.hotRestart(), isTrue);

      expect(
        (await connector.inspectUiSupport()).configuredLibraries,
        {UiSupportLibrary.cupertinoUi},
      );
    });

    test('reads the reloaded code after a hot reload', () async {
      await connector.connect(app.uri);
      app
        ..registerService('reloadSources', 's0.reloadSources')
        ..hold = Completer<void>()
        ..heldMethod = 's0.reloadSources';

      final reload = connector.hotReload();
      await app.requests.stream.firstWhere(
        (method) => method == 's0.reloadSources',
      );
      expect((await connector.inspectUiSupport()).configuredLibraries, isEmpty);
      app.configuration = {
        'uiLibraries': ['material_ui'],
      };
      app.hold!.complete();
      expect(await reload, isTrue);

      expect(
        (await connector.inspectUiSupport()).configuredLibraries,
        {UiSupportLibrary.materialUi},
      );
    });

    test('a read overtaken by a hot restart does not report', () async {
      await connector.connect(app.uri);
      app
        ..hold = Completer<void>()
        ..heldMethod = 'ext.flutter.marionette.getConfiguration';

      final overtaken = expectLater(
        connector.inspectUiSupport(),
        throwsA(isA<StateError>()),
      );
      await app.requests.stream.firstWhere(
        (method) => method == 'ext.flutter.marionette.getConfiguration',
      );
      app
        ..isolateId = 'isolates/2'
        ..registerService('hotRestart', 's0.hotRestart');
      expect(await connector.hotRestart(), isTrue);
      app.hold!.complete();

      await overtaken;
    });
  });
}
