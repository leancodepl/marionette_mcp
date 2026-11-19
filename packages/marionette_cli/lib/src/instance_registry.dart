import 'package:marionette_cli/src/json_file_registry.dart';

/// Metadata for a registered Flutter app instance.
class InstanceInfo implements JsonFileEntry {
  InstanceInfo({
    required this.name,
    required this.uri,
    required this.registeredAt,
  });

  factory InstanceInfo.fromJson(Map<String, dynamic> json) {
    return InstanceInfo(
      name: json['name'] as String,
      uri: json['uri'] as String,
      registeredAt: DateTime.parse(json['registeredAt'] as String),
    );
  }

  @override
  final String name;
  final String uri;
  final DateTime registeredAt;

  @override
  Map<String, dynamic> toJson() => {
        'name': name,
        'uri': uri,
        'registeredAt': registeredAt.toUtc().toIso8601String(),
      };
}

/// File-based registry for named Flutter app instances, stored in
/// `~/.marionette/instances/`.
class InstanceRegistry extends JsonFileRegistry<InstanceInfo> {
  InstanceRegistry({super.baseDir})
      : super(directoryName: 'instances', fromJson: InstanceInfo.fromJson);

  /// Registers an instance. Overwrites if already exists.
  ///
  /// Returns true if an existing instance was overwritten.
  Future<bool> register(String name, String uri) async {
    final existed = contains(name);

    save(
      InstanceInfo(
        name: name,
        uri: uri,
        registeredAt: DateTime.now(),
      ),
    );

    return existed;
  }
}
