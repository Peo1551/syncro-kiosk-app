import 'dart:convert';

import '../config/app_config.dart';

/// What the server says about this tablet (pair and heartbeat responses).
class TabletInfo {
  const TabletInfo({
    this.kioskTabletId = 0,
    this.tabletName = '',
    this.companyName = '',
    this.siteId,
    this.siteName = '',
    this.idleSeconds = AppConfig.defaultIdleSeconds,
    this.adminPinSet = false,
    this.serverTimeUtc,
  });

  final int kioskTabletId;
  final String tabletName;
  final String companyName;
  final int? siteId;
  final String siteName;
  final int idleSeconds;
  final bool adminPinSet;
  final DateTime? serverTimeUtc;

  factory TabletInfo.fromJson(Object? raw) {
    final json = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
    int? toInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    final idle = toInt(json['idle_seconds']) ?? AppConfig.defaultIdleSeconds;
    return TabletInfo(
      kioskTabletId: toInt(json['kiosk_tablet_id']) ?? 0,
      tabletName: (json['tablet_name'] ?? '').toString(),
      companyName: (json['company_name'] ?? '').toString(),
      siteId: toInt(json['site_id']),
      siteName: (json['site_name'] ?? '').toString(),
      idleSeconds: idle > 0 ? idle : AppConfig.defaultIdleSeconds,
      adminPinSet:
          json['admin_pin_set'] == true || '${json['admin_pin_set']}' == '1',
      serverTimeUtc: DateTime.tryParse(
        (json['server_time_utc'] ?? '').toString(),
      )?.toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'kiosk_tablet_id': kioskTabletId,
    'tablet_name': tabletName,
    'company_name': companyName,
    'site_id': siteId,
    'site_name': siteName,
    'idle_seconds': idleSeconds,
    'admin_pin_set': adminPinSet,
  };

  /// "Company · Site" for the wake screen.
  String get placeLabel => [
    companyName.trim(),
    siteName.trim(),
  ].where((part) => part.isNotEmpty).join(' · ');
}

/// The tablet's pairing: the only thing this app keeps in storage.
class TabletPairing {
  const TabletPairing({
    required this.accessToken,
    required this.tabletUuid,
    required this.tablet,
  });

  final String accessToken;
  final String tabletUuid;
  final TabletInfo tablet;

  TabletPairing withTablet(TabletInfo next) =>
      TabletPairing(accessToken: accessToken, tabletUuid: tabletUuid, tablet: next);

  String toStorageValue() => jsonEncode({
    'access_token': accessToken,
    'tablet_uuid': tabletUuid,
    'tablet': tablet.toJson(),
  });

  static TabletPairing fromStorageValue(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map) throw const FormatException('Invalid saved pairing.');
    final pairing = TabletPairing(
      accessToken: (json['access_token'] ?? '').toString(),
      tabletUuid: (json['tablet_uuid'] ?? '').toString(),
      tablet: TabletInfo.fromJson(json['tablet']),
    );
    if (pairing.accessToken.isEmpty || pairing.tabletUuid.isEmpty) {
      throw const FormatException('Invalid saved pairing.');
    }
    return pairing;
  }
}
