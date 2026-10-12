import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/kiosk_ui.dart';

/// "Request sent": the employee chooses to carry on, or is signed out when
/// the short countdown runs out.
class RequestSentPage extends StatefulWidget {
  const RequestSentPage({
    super.key,
    required this.onDoSomethingElse,
    required this.onSignOut,
    this.seconds = 8,
  });

  final VoidCallback onDoSomethingElse;
  final VoidCallback onSignOut;
  final int seconds;

  @override
  State<RequestSentPage> createState() => _RequestSentPageState();
}

class _RequestSentPageState extends State<RequestSentPage> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _timer?.cancel();
        widget.onSignOut();
        return;
      }
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kKioskBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: KioskPanel(
              padding: const EdgeInsets.fromLTRB(48, 44, 48, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    decoration: const BoxDecoration(
                      color: kKioskGreenSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 72,
                      color: kKioskPositive,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Request sent',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: kKioskText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Your manager will review it. You can follow it in Request History.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, color: kKioskMuted),
                  ),
                  const SizedBox(height: 36),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 76,
                          child: OutlinedButton(
                            key: const Key('sent-other'),
                            onPressed: () {
                              _timer?.cancel();
                              widget.onDoSomethingElse();
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: kKioskLine,
                                width: 2,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: const Text('Do something else'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 76,
                          child: FilledButton(
                            key: const Key('sent-sign-out'),
                            onPressed: () {
                              _timer?.cancel();
                              widget.onSignOut();
                            },
                            style: FilledButton.styleFrom(
                              textStyle: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text('Sign out now ($_left)'),
                          ),
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
    );
  }
}
