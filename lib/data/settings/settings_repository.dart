import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/device_identity.dart';

class SettingsRepository {
  static const _deviceIdKey = 'device_id';
  static const _deviceNameKey = 'device_name';
  static const _receiveDirectoryKey = 'receive_directory';

  Future<DeviceIdentity> loadIdentity() async {
    final preferences = await SharedPreferences.getInstance();
    var id = preferences.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await preferences.setString(_deviceIdKey, id);
    }
    var name = preferences.getString(_deviceNameKey);
    if (name == null || name.trim().isEmpty) {
      name = await _defaultDeviceName();
      await preferences.setString(_deviceNameKey, name);
    }
    return DeviceIdentity(id: id, name: name);
  }

  Future<Directory> loadReceiveDirectory() async {
    final preferences = await SharedPreferences.getInstance();
    final savedPath = preferences.getString(_receiveDirectoryKey);
    if (savedPath != null && savedPath.isNotEmpty) {
      final saved = Directory(savedPath);
      await saved.create(recursive: true);
      return saved;
    }

    final Directory base;
    if (Platform.isLinux) {
      base =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final directory = Directory(path.join(base.path, 'LocalBridge'));
    await directory.create(recursive: true);
    await preferences.setString(_receiveDirectoryKey, directory.path);
    return directory;
  }

  Future<void> saveDeviceName(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 80) {
      throw ArgumentError('O nome deve ter entre 1 e 80 caracteres.');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_deviceNameKey, normalized);
  }

  Future<void> saveReceiveDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    await directory.create(recursive: true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_receiveDirectoryKey, directory.path);
  }

  Future<String> _defaultDeviceName() async {
    if (Platform.isAndroid) {
      try {
        final android = await DeviceInfoPlugin().androidInfo;
        if (android.model.trim().isNotEmpty) return android.model.trim();
      } on Object {
        // Hostname is a safe fallback when device metadata is unavailable.
      }
    }
    final hostname = Platform.localHostname.trim();
    return hostname.isEmpty ? 'Meu dispositivo' : hostname;
  }
}
