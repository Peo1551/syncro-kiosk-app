import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../config/app_config.dart';
import '../features/work/employee_workspace.dart';
import '../kiosk/kiosk_service.dart';
import '../theme/app_theme.dart';
import 'kiosk_controller.dart';
import 'screens/admin_screens.dart';
import 'screens/pair_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/signed_in_shell.dart';
import 'screens/status_screens.dart';
import 'screens/wake_screen.dart';

class SyncroKioskApp extends StatefulWidget {
  const SyncroKioskApp({
    super.key,
    required this.controller,
    this.takePhoto,
    this.today,
  });

  final KioskController controller;
  final PhotoTaker? takePhoto;
  final DateTime? today;

  @override
  State<SyncroKioskApp> createState() => _SyncroKioskAppState();
}

class _SyncroKioskAppState extends State<SyncroKioskApp>
    with WidgetsBindingObserver {
  KioskController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    c.addListener(_changed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool _onKey(KeyEvent event) {
    c.touch();
    return c.cardReader.handleKeyEvent(event);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      c.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(KioskService.applySoftKiosk());
      unawaited(c.heartbeat());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('en', 'GB'),
      supportedLocales: const [Locale('en', 'GB')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, _) {
          unawaited(KioskService.applySoftKiosk());
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => c.touch(),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey('${c.mode}-${c.sessionGeneration}'),
              child: _screen(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _screen() {
    switch (c.mode) {
      case KioskMode.boot:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case KioskMode.pair:
        return PairScreen(onPair: c.pair);
      case KioskMode.recovery:
        return RecoveryScreen(
          message: c.recoveryMessage ?? '',
          onRetry: () => unawaited(c.retryRecovery()),
        );
      case KioskMode.wake:
        return WakeScreen(
          tablet: c.tablet,
          onSignIn: c.openSignIn,
          onSettings: c.openAdminPin,
        );
      case KioskMode.signIn:
        return SignInScreen(controller: c);
      case KioskMode.adminPin:
        return AdminPinScreen(controller: c);
      case KioskMode.admin:
        return AdminSettingsScreen(controller: c);
      case KioskMode.signedIn:
        final session = c.session;
        if (session == null) {
          return const Scaffold(body: SizedBox.shrink());
        }
        return SignedInShell(
          controller: c,
          session: session,
          takePhoto: widget.takePhoto,
          today: widget.today,
        );
      case KioskMode.signedOut:
        return SignedOutScreen(message: c.signedOutMessage, onDone: c.goWake);
      case KioskMode.unlicensed:
        return UnlicensedScreen(onRetry: () => unawaited(c.heartbeat()));
    }
  }
}
