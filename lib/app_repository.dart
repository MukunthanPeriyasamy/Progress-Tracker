import 'package:flutter/services.dart';

class InstalledApp {
  InstalledApp(Map<Object?, Object?> data)
    : package = data['package'] as String,
      name = data['name'] as String,
      icon = data['icon'] as Uint8List?,
      system = data['system'] as bool? ?? false,
      protected = data['protected'] as bool? ?? false;
  final String package, name;
  final Uint8List? icon;
  final bool system;
  final bool protected;
}

/// Android owns both consent and selections, stored locally in preferences.
class AppRepository {
  static const channel = MethodChannel('focus_flow/apps');
  Future<Map<Object?, Object?>> preferences() async =>
      await channel.invokeMapMethod<Object?, Object?>('preferences') ?? {};
  Future<void> consent() => channel.invokeMethod('consent');
  Future<Map<Object?, Object?>> permissions() async =>
      await channel.invokeMapMethod<Object?, Object?>('permissions') ?? {};
  Future<void> openSettings(String target, {String? package}) => channel
      .invokeMethod('openSettings', {'target': target, 'package': package});
  Future<List<InstalledApp>> apps() async {
    final items = await channel.invokeListMethod<Object?>('apps') ?? [];
    return items
        .map((item) => InstalledApp(item as Map<Object?, Object?>))
        .toList();
  }

  Future<void> save(Set<String> packages) =>
      channel.invokeMethod('save', packages.toList());
}
