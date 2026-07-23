import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/account.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shared setup helpers for the unit tests. Kept in one place so every test
/// file gets the same in-memory/temp-dir treatment for the plugins that
/// would otherwise reach out to real platform channels.

/// A distinct [Account] per test. Using a unique [user] gives a unique
/// `account.key`, which keeps the per-account singleton services
/// (Favorites/Playback/History/PinLock) from leaking state between tests -
/// each key is loaded fresh rather than short-circuiting on the last one.
Account accountNamed(String user) => Account(
      name: user,
      serverUrl: 'http://host:8080',
      username: user,
      password: 'pw-$user',
    );

/// Points path_provider at a throwaway temp dir and switches sqflite to its
/// FFI (desktop/VM) factory, so [CatalogDatabase] can open a real on-disk
/// database inside the test's isolate. Returns the temp dir so a test can
/// clean up if it wants to.
Future<Directory> initDbEnvironment() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = await Directory.systemTemp.createTemp('iptv_player_test_');
  PathProviderPlatform.instance = _FakePathProvider(dir.path);
  return dir;
}

/// Installs an in-memory stand-in for flutter_secure_storage's platform
/// channel and returns the backing map so a test can seed or inspect it.
Map<String, String> mockSecureStorage() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  const channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    switch (call.method) {
      case 'write':
        store[args['key'] as String] = args['value'] as String;
        return null;
      case 'read':
        return store[args['key'] as String];
      case 'delete':
        store.remove(args['key'] as String);
        return null;
      case 'deleteAll':
        store.clear();
        return null;
      case 'readAll':
        return Map<String, String>.from(store);
      case 'containsKey':
        return store.containsKey(args['key'] as String);
      default:
        return null;
    }
  });
  return store;
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
  @override
  Future<String?> getLibraryPath() async => root;
  @override
  Future<String?> getDownloadsPath() async => root;
}
