import 'dart:async';

import 'package:flutter/material.dart';

import '../../kiosk/pairing_flow.dart';
import '../widgets.dart';

class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.onPair});

  final Future<void> Function(String code) onPair;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  String _code = '';
  bool _busy = false;
  String? _error;

  void _digit(String d) {
    if (_busy || _code.length >= 6) return;
    setState(() {
      _code += d;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code)) {
      setState(() => _error = 'Enter the 6-digit pairing code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPair(_code);
    } on PairingFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Pairing could not finish. Please try again. If this continues, contact support.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: kInk,
                padding: const EdgeInsets.all(48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const BrandMark(size: 64, light: true),
                    const SizedBox(height: 40),
                    const Text(
                      'Pair this tablet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'In Syncro Connect, open Settings › Syncro Kiosk and choose Pair a tablet.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 20,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Then enter the 6-digit code shown there.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Pairing code', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 16),
                        CodeBoxes(code: _code),
                        const SizedBox(height: 16),
                        if (_error != null) ...[
                          ErrorNote(_error!),
                          const SizedBox(height: 12),
                        ],
                        NumericKeypad(
                          enabled: !_busy,
                          onDigit: _digit,
                          onBackspace: () => setState(() {
                            if (_code.isNotEmpty) {
                              _code = _code.substring(0, _code.length - 1);
                            }
                          }),
                          onClear: () => setState(() => _code = ''),
                        ),
                        const SizedBox(height: 16),
                        BigButton(
                          key: const Key('pair-submit'),
                          label: 'Pair tablet',
                          busy: _busy,
                          onPressed: () => unawaited(_submit()),
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
    );
  }
}
