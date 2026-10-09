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

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  bool _confirmUnpair = false;
  KioskStatus? _kiosk;

  KioskController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_loadKioskStatus());
  }

  Future<void> _loadKioskStatus() async {
    final status = await KioskService.status();
    if (mounted) setState(() => _kiosk = status);
  }

  Future<void> _lockTablet() async {
    final status = await KioskService.startLockTask();
    if (mounted) setState(() => _kiosk = status);
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
              style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600),
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
                          label: const Text('Back to kiosk'),
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
                          _row('Kiosk lock', _kiosk?.message ?? 'Checking…'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_kiosk != null &&
                      _kiosk!.lockTaskAvailable &&
                      !_kiosk!.lockTaskActive) ...[
                    SizedBox(
                      height: 60,
                      child: OutlinedButton.icon(
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
