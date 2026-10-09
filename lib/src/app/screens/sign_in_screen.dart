import 'dart:async';

import 'package:flutter/material.dart';

import '../kiosk_controller.dart';
import '../widgets.dart';

/// Card panel on the left; clock number then PIN on the right.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.controller});

  final KioskController controller;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  String _clockNumber = '';
  String _pin = '';
  bool _pinStep = false;
  String? _localError;
  Timer? _blockTimer;

  KioskController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _blockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && c.signInBlockedUntil != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _blockTimer?.cancel();
    super.dispose();
  }

  void _digit(String d) {
    setState(() {
      _localError = null;
      if (_pinStep) {
        if (_pin.length < 12) _pin += d;
      } else {
        if (_clockNumber.length < 9) _clockNumber += d;
      }
    });
  }

  void _backspace() {
    setState(() {
      if (_pinStep) {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_clockNumber.isNotEmpty) {
        _clockNumber = _clockNumber.substring(0, _clockNumber.length - 1);
      }
    });
  }

  void _clear() => setState(() => _pinStep ? _pin = '' : _clockNumber = '');

  Future<void> _next() async {
    if (!_pinStep) {
      if (_clockNumber.isEmpty) {
        setState(() => _localError = 'Enter your clock number.');
        return;
      }
      setState(() {
        _pinStep = true;
        _localError = null;
      });
      return;
    }
    if (_pin.length < 4 || _pin.length > 12) {
      setState(() => _localError = 'Your PIN is 4 to 12 digits.');
      return;
    }
    await c.signInWithPin(clockNumber: _clockNumber, pin: _pin);
    if (!mounted) return;
    setState(() => _pin = '');
  }

  void _back() {
    if (_pinStep) {
      setState(() {
        _pinStep = false;
        _pin = '';
        _localError = null;
      });
    } else {
      c.goWake();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = c.signingIn;
    final blocked = c.signInBlocked;
    final error = _localError ?? c.signInError;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: kInk,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kGreen.withValues(alpha: 0.15),
                          border: Border.all(color: kGreen, width: 3),
                        ),
                        child: busy
                            ? const Padding(
                                padding: EdgeInsets.all(52),
                                child: CircularProgressIndicator(
                                  color: kGreen,
                                  strokeWidth: 5,
                                ),
                              )
                            : const Icon(
                                Icons.contactless_outlined,
                                size: 92,
                                color: kGreen,
                              ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        busy ? 'Signing you in…' : 'Tap your card',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Hold your card against the reader',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                flex: 6,
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _pinStep ? 'PIN' : 'Clock number',
                            key: const Key('sign-in-step'),
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _pinStep
                                ? 'Enter your clock PIN for clock number $_clockNumber.'
                                : 'Or sign in with your clock number and PIN.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          EntryDisplay(
                            value: _pinStep ? _pin : _clockNumber,
                            obscure: _pinStep,
                          ),
                          const SizedBox(height: 10),
                          if (error != null) ...[
                            ErrorNote(error),
                            const SizedBox(height: 10),
                          ],
                          NumericKeypad(
                            enabled: !busy,
                            onDigit: _digit,
                            onBackspace: _backspace,
                            onClear: _clear,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              SizedBox(
                                height: 64,
                                width: 140,
                                child: OutlinedButton(
                                  key: const Key('sign-in-back'),
                                  onPressed: busy ? null : _back,
                                  child: const Text('Back'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: BigButton(
                                  key: const Key('sign-in-next'),
                                  label: _pinStep ? 'Sign in' : 'Next',
                                  busy: busy,
                                  onPressed: blocked && _pinStep
                                      ? null
                                      : () => unawaited(_next()),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
