import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

/// Minimal Marionette-compatible VM service without a Flutter dependency.
Future<void> main() async {
  for (final entry in <String, Map<String, Object?>>{
    'getLogs': {'logs': <String>[], 'count': 0},
    'getVersion': {'version': '0.7.0'},
    'getConfiguration': {'enableSessionReports': false},
    'listExtensions': {'extensions': <Object>[]},
  }.entries) {
    developer.registerExtension(
      'ext.flutter.marionette.${entry.key}',
      (_, __) async =>
          developer.ServiceExtensionResponse.result(jsonEncode(entry.value)),
    );
  }
  final info = await developer.Service.getInfo();
  final serverUri = info.serverUri;
  if (serverUri == null) throw StateError('VM service is not enabled');
  final websocketUri = serverUri.replace(scheme: 'ws').resolve('ws');
  print('READY:$websocketUri');
  Timer.periodic(const Duration(seconds: 10), (_) {});
}
