import 'dart:async';

import 'package:flutter/material.dart';

import '../../kiosk/kiosk_service.dart';
import '../kiosk_controller.dart';
import '../widgets.dart';

/// PIN keypad used for opening settings and confirming unpairing. The PIN is
/// always checked by the server.
class AdminPinPad extends StatefulWidget {
  const AdminPinPad({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onSubmit,
    required this.onCancel,
    this.description,
  });

  final String title;
  final String? description;
  final String actionLabel;

  /// Returns an error message, or null when accepted.
  final Future<String?> Function(String pin) onSubmit;
  final VoidCallback onCancel;

  @override
  State<AdminPinPad> createState() => _AdminPinPadState();
}

class _AdminPinPadState extends State<AdminPinPad> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    if (_pin.length < 4) {
      setState(() => _error = 'Enter the kiosk admin PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error != null) _pin = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          if (widget.description != null) ...[
            const SizedBox(height: 4),
            Text(widget.description!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          EntryDisplay(value: _pin, obscure: true),
          const SizedBox(height: 10),
          if (_error != null) ...[
            ErrorNote(_error!),
            const SizedBox(height: 10),
          ],
          NumericKeypad(
            enabled: !_busy,
            onDigit: (d) => setState(() {
              if (_pin.length < 12) _pin += d;
              _error = null;
            }),
            onBackspace: () => setState(() {
              if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
            }),
            onClear: () => setState(() => _pin = ''),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                height: 64,
                width: 140,
                child: OutlinedButton(
                  onPressed: _busy ? null : widget.onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BigButton(
                  key: const Key('admin-pin-submit'),
                  label: widget.actionLabel,
                  busy: _busy,
                  onPressed: () => unawaited(_submit()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AdminPinScreen extends StatelessWidget {
  const AdminPinScreen({super.key, required this.controller});

  final KioskController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AdminPinPad(
              title: 'Tablet settings',
              description: 'Enter the kiosk admin PIN.',
              actionLabel: 'Open settings',
              onSubmit: controller.checkAdminPin,
              onCancel: controller.goWake,
            ),
          ),
        ),
      ),
    );
  }
}

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key, required this.controller});

  final KioskController controller;

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen>
    with WidgetsBindingObserver {
  bool _confirmUnpair = false;
  KioskStatus? _kiosk;

  /// True once the admin has exited kiosk mode here; leaving settings by any
  /// route (Return to kiosk, idle time-out, unpair) locks the tablet again.
  bool _exitedKiosk = false;

  KioskController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(KioskService.setAdminOpen(true));
    unawaited(_loadKioskStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_exitedKiosk) {
      unawaited(KioskService.resumeKioskMode());
    } else {
      unawaited(KioskService.setAdminOpen(false));
    }
    super.dispose();
  }

  /// Back from an Android settings page: show what the admin changed there.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadKioskStatus());
  }

  Future<void> _loadKioskStatus() async {
    final status = await KioskService.status();
    if (mounted) setState(() => _kiosk = status);
  }

  Future<void> _lockTablet() async {
    final status = await KioskService.startLockTask();
    if (mounted) setState(() => _kiosk = status);
  }

  Future<void> _exitKiosk() async {
    _exitedKiosk = true;
    final status = await KioskService.exitKioskMode();
    if (mounted) setState(() => _kiosk = status);
  }

  Future<void> _allowReturn() async {
    final status = await KioskService.openReturnPermission();
    if (mounted) setState(() => _kiosk = status);
  }

  Future<void> _setHomeApp(bool enabled) async {
    final status = await KioskService.setHomeApp(enabled);
    if (mounted) setState(() => _kiosk = status);
  }

  /// A normal (not dedicated) Android tablet.
  bool get _ordinaryTablet {
    final kiosk = _kiosk;
    return kiosk != null && kiosk.lockTaskAvailable && !kiosk.isDeviceOwner;
  }

  Future<void> _releaseTablet() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Release this tablet?'),
        content: const Text(
          'This turns off dedicated kiosk mode and returns the tablet to '
          'normal use. To make it a dedicated kiosk again, the tablet must be '
          'factory reset or set up again with the setup command.',
        ),
        actions: [
          TextButton(
            key: const Key('admin-release-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('admin-release-confirm'),
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Release tablet'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final status = await KioskService.releaseDeviceOwner();
    if (mounted) setState(() => _kiosk = status);
  }

  String _kioskLockText() {
    final kiosk = _kiosk;
    if (kiosk == null) return 'Checking…';
    // iPad and other platforms keep their own explanation.
    if (!kiosk.lockTaskAvailable) return kiosk.message;
    return kiosk.lockState.label;
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(
                color: kMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tablet = c.tablet;
    if (_confirmUnpair) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AdminPinPad(
                title: 'Unpair this tablet',
                description:
                    'Enter the kiosk admin PIN again to remove this tablet from Syncro Connect.',
                actionLabel: 'Unpair',
                onSubmit: c.unpair,
                onCancel: () => setState(() => _confirmUnpair = false),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tablet settings',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      SizedBox(
                        height: 60,
                        child: FilledButton.icon(
                          key: const Key('admin-back'),
                          onPressed: c.goWake,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Return to kiosk'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _row('Company', tablet.companyName),
                          _row('Tablet name', tablet.tabletName),
                          _row('Site', tablet.siteName),
                          _row(
                            'Sign-out after',
                            '${c.tabletIdleSeconds} seconds idle',
                          ),
                          _row('App version', c.appVersion),
                          _row('Kiosk lock', _kioskLockText()),
                          if (_ordinaryTablet) ...[
                            _row(
                              'Reopen if closed',
                              _kiosk!.canReturn ? 'On' : 'Needs permission',
                            ),
                            _row(
                              'Home screen',
                              _kiosk!.isHomeApp ? 'Syncro Kiosk' : 'Normal',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_kiosk != null &&
                      _kiosk!.lockTaskAvailable &&
                      (!_kiosk!.isDeviceOwner ||
                          _kiosk!.lockState == KioskLockState.none)) ...[
                    Text(
                      _kiosk!.message,
                      key: const Key('admin-kiosk-help'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: kMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_kiosk != null &&
                      _kiosk!.lockTaskAvailable &&
                      (_kiosk!.lockState != KioskLockState.none ||
                          (!_kiosk!.isDeviceOwner && !_kiosk!.suspended))) ...[
                    SizedBox(
                      height: 60,
                      child: OutlinedButton.icon(
                        key: const Key('admin-exit-kiosk'),
                        onPressed: () => unawaited(_exitKiosk()),
                        icon: const Icon(Icons.lock_open_outlined),
                        label: const Text('Exit kiosk mode'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_ordinaryTablet && !_kiosk!.canReturn) ...[
                    SizedBox(
                      height: 60,
                      child: OutlinedButton.icon(
                        key: const Key('admin-allow-return'),
                        onPressed: () => unawaited(_allowReturn()),
                        icon: const Icon(Icons.replay_outlined),
                        label: const Text('Allow kiosk to reopen itself'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_ordinaryTablet) ...[
                    SizedBox(
                      height: 60,
                      child: OutlinedButton.icon(
                        key: const Key('admin-home-app'),
                        onPressed: () =>
                            unawaited(_setHomeApp(!_kiosk!.isHomeApp)),
                        icon: const Icon(Icons.home_outlined),
                        label: Text(
                          _kiosk!.isHomeApp
                              ? 'Use normal home screen'
                              : 'Make kiosk the home screen',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_kiosk != null && _kiosk!.isDeviceOwner) ...[
                    SizedBox(
                      height: 60,
                      child: OutlinedButton.icon(
                        key: const Key('admin-release-tablet'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kDanger,
                          side: const BorderSide(color: kDanger),
                        ),
                        onPressed: () => unawaited(_releaseTablet()),
                        icon: const Icon(Icons.phonelink_erase_outlined),
                        label: const Text('Release this tablet'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_kiosk != null &&
                      _kiosk!.lockTaskAvailable &&
                      !_kiosk!.isDeviceOwner &&
                      !_kiosk!.lockTaskActive) ...[
                    SizedBox(
                      height: 60,
                      child: OutlinedButton.icon(
                        key: const Key('admin-pin-tablet'),
                        onPressed: () => unawaited(_lockTablet()),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Lock tablet to this app'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    height: 60,
                    child: OutlinedButton.icon(
                      key: const Key('admin-unpair'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kDanger,
                        side: const BorderSide(color: kDanger),
                      ),
                      onPressed: () => setState(() => _confirmUnpair = true),
                      icon: const Icon(Icons.link_off_rounded),
                      label: const Text('Unpair this tablet'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
