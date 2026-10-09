import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'src/app/kiosk_app.dart';
import 'src/app/kiosk_controller.dart';
import 'src/core/http/api_client.dart';
import 'src/kiosk/kiosk_service.dart';
import 'src/kiosk/tablet_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(KioskService.applySoftKiosk());
  var version = '';
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version}+${info.buildNumber}';
  } catch (_) {}
  final controller = KioskController(
    client: ApiClient(),
    store: const SecureTabletStore(),
    appVersion: version,
    prepareKiosk: KioskService.applySoftKiosk,
  );
  unawaited(controller.start());
  runApp(SyncroKioskApp(controller: controller));
}
