import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'tablet.dart';

/// Secure storage for the tablet pairing. Nothing about employees is ever
/// stored: sessions, names and leave data stay in memory.
abstract class TabletStore {
  Future<String> getOrCreateTabletUuid();
  Future<TabletPairing?> readPairing();
  Future<void> savePairing(TabletPairing pairing);
  Future<void> clearPairing();
}

class SecureTabletStore implements TabletStore {
  const SecureTabletStore()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  final FlutterSecureStorage _storage;

  static const _pairingKey = 'syncro_kiosk_pairing_v1';
  static const _uuidKey = 'syncro_kiosk_uuid_v1';

  @override
  Future<String> getOrCreateTabletUuid() async {
    final existing = await _storage.read(key: _uuidKey);
    if ((existing ?? '').isNotEmpty) return existing!;
    final uuid = newTabletUuid();
    await _storage.write(key: _uuidKey, value: uuid);
    return uuid;
  }

  @override
  Future<TabletPairing?> readPairing() async {
    final raw = await _storage.read(key: _pairingKey);
    if (raw == null || raw.isEmpty) return null;
    return TabletPairing.fromStorageValue(raw);
  }

  @override
  Future<void> savePairing(TabletPairing pairing) =>
      _storage.write(key: _pairingKey, value: pairing.toStorageValue());

  @override
  Future<void> clearPairing() => _storage.delete(key: _pairingKey);
}

String newTabletUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// In-memory store for tests and previews.
class MemoryTabletStore implements TabletStore {
  MemoryTabletStore({this.pairing, this.uuid = 'test-tablet-uuid'});

  TabletPairing? pairing;
  String uuid;
  int clears = 0;

  @override
  Future<String> getOrCreateTabletUuid() async => uuid;

  @override
  Future<TabletPairing?> readPairing() async => pairing;

  @override
  Future<void> savePairing(TabletPairing next) async => pairing = next;

  @override
  Future<void> clearPairing() async {
    clears++;
    pairing = null;
  }
}
