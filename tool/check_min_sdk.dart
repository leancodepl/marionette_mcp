#!/usr/bin/env dart
// Uses only dart: libraries, so it runs on an SDK that cannot resolve the
// full workspace.

import 'dart:io';

const _usage = '''
Usage: dart tool/check_min_sdk.dart <legacy|addons> [--lowest]

  legacy    Resolves, analyzes and tests the packages that keep Flutter 3.27
            support in a workspace without the UI integrations and the
            fixture app. Run it with Flutter 3.27 on PATH.
  addons    Resolves the core-only, Cupertino-only, Material-only and mixed
            consumer graphs and fails when one holds a package it must not,
            then analyzes and tests each integration in its own graph.
  --lowest  With addons: resolves the lowest allowed versions (pub
            downgrade), which checks the lowest supported material_ui and
            cupertino_ui. Run it with Flutter 3.44 on PATH.''';

const _uiPackages = [
  'material_ui',
  'cupertino_ui',
  'marionette_material',
  'marionette_cupertino',
];

const _legacy = _Workspace(
  'legacy',
  members: [
    _Member('packages/marionette_mcp', usesFlutter: false, isChecked: true),
    _Member('packages/marionette_cli', usesFlutter: false, isChecked: true),
    _Member('packages/marionette_flutter', usesFlutter: true, isChecked: true),
    _Member('packages/marionette_logger', usesFlutter: true, isChecked: true),
    _Member('packages/marionette_logging', usesFlutter: true, isChecked: true),
  ],
  forbidden: _uiPackages,
);

const _core = _Member('packages/marionette_flutter', usesFlutter: true);
const _cupertino = _Member(
  'packages/marionette_cupertino',
  usesFlutter: true,
  isChecked: true,
);
const _material = _Member(
  'packages/marionette_material',
  usesFlutter: true,
  isChecked: true,
);

/// The package a consumer graph generates, with dependencies on core and on
/// [_Workspace.consumerDependencies].
const _consumer = _Member('consumer', usesFlutter: true);

const _consumerGraphs = [
  _Workspace(
    'core only',
    members: [_core, _consumer],
    consumerDependencies: [],
    forbidden: _uiPackages,
  ),
  _Workspace(
    'Cupertino only',
    members: [_core, _cupertino, _consumer],
    consumerDependencies: ['marionette_cupertino'],
    forbidden: ['material_ui', 'marionette_material'],
  ),
  _Workspace(
    'Material only',
    members: [_core, _material, _consumer],
    consumerDependencies: ['marionette_material'],
    forbidden: ['marionette_cupertino'],
  ),
  _Workspace(
    'mixed',
    members: [
      _core,
      _Member('packages/marionette_cupertino', usesFlutter: true),
      _Member('packages/marionette_material', usesFlutter: true),
      _Member(
        'tool/fixtures/ui_integrations',
        usesFlutter: true,
        isChecked: true,
      ),
    ],
    forbidden: [],
  ),
];

Future<void> main(List<String> args) async {
  final workspaces = switch (args) {
    ['legacy'] => [_legacy],
    ['addons'] => _consumerGraphs,
    ['addons', '--lowest'] => _consumerGraphs,
    _ => null,
  };
  if (workspaces == null) {
    stderr.writeln(_usage);
    exit(64);
  }

  try {
    for (final workspace in workspaces) {
      await _check(workspace, lowest: args.contains('--lowest'));
    }
  } on _CheckFailure catch (failure) {
    stderr.writeln('ERROR: ${failure.message}');
    exit(failure.exitCode);
  }
  print('\nAll checks passed.');
}

/// Builds [workspace] in a temporary folder from this repository's files,
/// resolves it and fails when the lockfile holds a forbidden package. Then
/// analyzes and tests the checked members.
Future<void> _check(_Workspace workspace, {required bool lowest}) async {
  print('\n== ${workspace.name} workspace');
  final root = await Directory.systemTemp.createTemp('marionette_min_sdk_');
  try {
    await _writeRootPubspec(root, workspace.members);
    for (final member in workspace.members) {
      if (member == _consumer) {
        await _writeConsumer(root, workspace.consumerDependencies);
      } else {
        await _copyMember(member.path, root);
      }
    }

    await _run(
      'flutter',
      ['pub', if (lowest) 'downgrade' else 'get'],
      workingDirectory: root.path,
    );
    final lockedVersions = _lockedVersions(
      File('${root.path}/pubspec.lock').readAsStringSync(),
    );
    final present =
        workspace.forbidden.where(lockedVersions.containsKey).toList();
    if (present.isNotEmpty) {
      throw _CheckFailure(
        'the ${workspace.name} workspace resolves ${present.join(', ')}, '
        'which it must not depend on.',
      );
    }
    for (final library in ['material_ui', 'cupertino_ui']) {
      if (lockedVersions[library] case final version?) {
        print('$library resolved to $version');
      }
    }

    for (final member in workspace.members.where((m) => m.isChecked)) {
      await _analyzeAndTest(Directory('${root.path}/${member.path}'), member);
    }
  } finally {
    await root.delete(recursive: true);
  }
}

/// Writes the workspace pubspec: this repository's root pubspec up to its
/// `workspace:` list, followed by [members].
Future<void> _writeRootPubspec(Directory root, List<_Member> members) async {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final workspaceLine = lines.indexOf('workspace:');
  if (workspaceLine == -1) {
    throw _CheckFailure('no workspace list in pubspec.yaml');
  }
  await File('${root.path}/pubspec.yaml').writeAsString([
    ...lines.take(workspaceLine + 1),
    for (final member in members) '  - ${member.path}',
    '',
  ].join('\n'));
}

/// Copies the files of the package at [path] that git tracks or would
/// track, which leaves out build output and resolution state.
Future<void> _copyMember(String path, Directory root) async {
  final files = await Process.run(
    'git',
    ['ls-files', '--cached', '--others', '--exclude-standard', '--', path],
  );
  if (files.exitCode != 0) {
    throw _CheckFailure('git ls-files failed: ${files.stderr}');
  }
  final paths = (files.stdout as String).trim();
  if (paths.isEmpty) throw _CheckFailure('no files in $path');
  for (final file in paths.split('\n')) {
    final target = File('${root.path}/$file');
    await target.parent.create(recursive: true);
    await File(file).copy(target.path);
  }
}

Future<void> _writeConsumer(Directory root, List<String> dependencies) async {
  final consumer = Directory('${root.path}/${_consumer.path}');
  await consumer.create();
  await File('${consumer.path}/pubspec.yaml').writeAsString([
    'name: consumer',
    'publish_to: none',
    'resolution: workspace',
    'environment:',
    '  sdk: ^3.6.0',
    'dependencies:',
    '  flutter:',
    '    sdk: flutter',
    '  marionette_flutter: any',
    for (final dependency in dependencies) '  $dependency: any',
    '',
  ].join('\n'));
}

Future<void> _analyzeAndTest(Directory package, _Member member) async {
  final tool = member.usesFlutter ? 'flutter' : 'dart';
  final sources = [
    for (final source in ['lib', 'bin'])
      if (Directory('${package.path}/$source').existsSync()) source,
  ];
  await _run(
    tool,
    ['analyze', '--fatal-infos', ...sources],
    workingDirectory: package.path,
  );
  if (Directory('${package.path}/test').existsSync()) {
    await _run(
      tool,
      ['test', if (member.usesFlutter) '--no-pub'],
      workingDirectory: package.path,
    );
  }
}

/// The package names and versions in a pubspec.lock [content].
Map<String, String> _lockedVersions(String content) => {
      for (final match in RegExp(
        r'^  (\w+):\n(?:    .*\n)*?    version: "([^"]+)"',
        multiLine: true,
      ).allMatches(content))
        match.group(1)!: match.group(2)!,
    };

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final command = '$executable ${arguments.join(' ')}';
  print('\$ $command  ($workingDirectory)');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) throw _CheckFailure('"$command" failed', exitCode);
}

/// A temporary workspace of [members] whose lockfile may not hold any of
/// the [forbidden] packages.
class _Workspace {
  const _Workspace(
    this.name, {
    required this.members,
    this.consumerDependencies = const [],
    required this.forbidden,
  });

  final String name;
  final List<_Member> members;
  final List<String> consumerDependencies;
  final List<String> forbidden;
}

/// A workspace member at [path] relative to the repository root.
///
/// [isChecked] members are analyzed and tested.
class _Member {
  const _Member(this.path, {required this.usesFlutter, this.isChecked = false});

  final String path;
  final bool usesFlutter;
  final bool isChecked;
}

class _CheckFailure implements Exception {
  _CheckFailure(this.message, [this.exitCode = 1]);

  final String message;
  final int exitCode;
}
